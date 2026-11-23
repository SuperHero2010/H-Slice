package backend.play;

import backend.cache.BinCache;
import backend.cache.BinCache.BlockInfo;
import backend.cache.CacheEntry;
import backend.cache.CacheReader;
import backend.cache.NoteCodec;
import backend.play.NoteBlock.LaneData;

class NoteStore
{
	public static inline final OPP:Int = 0;
	public static inline final PLAYER:Int = 1;

	static inline final KEEP_BEHIND_MS:Float = 3000;

	public var entry(default, null):CacheEntry;
	public var blocks(default, null):Array<NoteBlock> = [];
	public var keys(default, null):Int;
	public var laneCount(default, null):Int;
	public var mergeMs(default, null):Float;

	public var totals(default, null):Array<Float> = [0, 0];

	public var streaming(default, null):Bool = false;
	public var aheadMs:Float = 8000;

	public var songTime:Float = 0;

	public var chartNoteCount(default, null):Float = 0;
	public var chartNotesLoaded(default, null):Float = 0;
	public var cacheLoadSeconds(default, null):Float = 0;

	public var streamMadeUntil(default, null):Float = 0;

	public var streamFinished(default, null):Bool = false;
	public var streamError(default, null):String = null;

	var cache:BinCache;
	var stop:Bool = false;
	var threadDone:sys.thread.Lock = null;
	var wake:sys.thread.Lock = new sys.thread.Lock();

	public function new(cache:BinCache, entry:CacheEntry, mergeMs:Float)
	{
		this.cache = cache;
		this.entry = entry;
		this.mergeMs = mergeMs;
		keys = entry.keys;
		laneCount = keys * 2;

		// Calculate optimal merge window based on chart density
		final totalNotes:Float = entry.blocks.reduce((acc, b) -> acc + b.entries, 0);
		final duration:Float = entry.blocks.length > 0 ? (entry.blocks[entry.blocks.length - 1].endUs - entry.blocks[0].startUs) / 1000 : 1;
		final nps:Float = totalNotes / Math.max(1, duration);

		// Auto-adjust merge window for very dense charts
		if (nps > 20 && mergeMs < 25) {
			this.mergeMs = 25; // Merge notes within 25ms for dense charts
		} else if (nps > 15 && mergeMs < 15) {
			this.mergeMs = 15; // Merge notes within 15ms for medium density
		}
		var opp:Float = 0, pl:Float = 0;
		for (i in 0...entry.blocks.length) {
			final info:BlockInfo = entry.blocks[i];
			final b:NoteBlock = new NoteBlock(i, info.startUs / 1000, info.endUs / 1000);
			b.before = [opp, pl];
			opp += info.opp;
			pl += info.player;
			blocks.push(b);
		}
		totals = [opp, pl];
		chartNoteCount = opp + pl;
	}

	public inline function sideOf(lane:Int):Int
		return lane < keys ? OPP : PLAYER;

	public function loadAll(?onProgress:Float->Void):Void
	{
		final t0:Float = haxe.Timer.stamp();
		final r:CacheReader = cache.reader();
		try {
			for (b in blocks) {
				decodeInto(r, b);
				if (onProgress != null) onProgress((b.index + 1) / blocks.length);
			}
		} catch (e:Dynamic) {
			r.close();
			throw e;
		}
		r.close();
		cacheLoadSeconds = haxe.Timer.stamp() - t0;
		streamFinished = true;
		streamMadeUntil = Math.POSITIVE_INFINITY;
		countLoaded();
	}

	public function startStream(fromMs:Float, aheadMs:Float):Void
	{
		this.aheadMs = aheadMs;
		songTime = fromMs;
		final t0:Float = haxe.Timer.stamp();
		final r:CacheReader = cache.reader();
		try {
			for (b in blocks) if (b.endMs > fromMs - KEEP_BEHIND_MS && b.startMs < fromMs + Math.min(aheadMs, 3000)) decodeInto(r, b);
		} catch (e:Dynamic) {
			r.close();
			throw e;
		}
		r.close();
		cacheLoadSeconds = haxe.Timer.stamp() - t0;
		countLoaded();
		streaming = true;
		threadDone = new sys.thread.Lock();
		sys.thread.Thread.create(streamLoop);
	}

	function decodeInto(r:CacheReader, b:NoteBlock):Void
	{
		final info:BlockInfo = entry.blocks[b.index];
		NoteCodec.decode(r.readBlock(info), info.startUs, mergeMs, b);
	}

	function streamLoop():Void
	{
		var r:CacheReader = null;
		try {
			r = cache.reader();
			while (!stop) {
				final now:Float = songTime;
				var did:Bool = false;

				for (b in blocks) if (b.lanes != null && b.endMs < now - KEEP_BEHIND_MS) b.lanes = null;

				for (b in blocks) {
					if (b.startMs > now + aheadMs) break;
					if (b.endMs < now - KEEP_BEHIND_MS || b.lanes != null) continue;
					decodeInto(r, b);
					did = true;
					break;
				}
				updateMadeUntil(now);
				countLoaded();
				if (!did) wake.wait(0.05);
			}
		} catch (e:Dynamic) {
			streamError = Std.string(e);
			trace('stream json stopped: $e');
		}
		if (r != null) r.close();
		threadDone.release();
	}

	function updateMadeUntil(now:Float):Void
	{
		var until:Float = now;
		var all:Bool = true;
		for (b in blocks) {
			if (b.endMs <= now) continue;
			if (b.lanes == null) {
				all = false;
				break;
			}
			until = b.endMs;
		}
		streamMadeUntil = all ? Math.POSITIVE_INFINITY : until;
		streamFinished = all;
	}

	function countLoaded():Void
	{
		var n:Float = 0;
		for (b in blocks) if (b.lanes != null) n += b.drawn;
		chartNotesLoaded = n;
	}

	public function blockAt(t:Float):Int
	{
		var lo:Int = 0, hi:Int = blocks.length - 1, found:Int = 0;
		while (lo <= hi) {
			final mid:Int = (lo + hi) >> 1;
			if (blocks[mid].startMs <= t) {
				found = mid;
				lo = mid + 1;
			} else hi = mid - 1;
		}
		return found;
	}

	public function passed(t:Float, side:Int):Float
	{
		if (blocks.length == 0) return 0;
		final k:Int = blockAt(t);
		final b:NoteBlock = blocks[k];
		final lanes:Array<LaneData> = b.lanes;
		if (t >= b.endMs) return b.before[side] + (side == OPP ? entry.blocks[k].opp : entry.blocks[k].player);
		if (lanes == null) {
			final f:Float = Math.max(0, Math.min(1, (t - b.startMs) / Math.max(1, b.endMs - b.startMs)));
			return b.before[side] + f * (side == OPP ? entry.blocks[k].opp : entry.blocks[k].player);
		}
		var n:Float = b.before[side];
		final from:Int = side == OPP ? 0 : keys;
		for (l in from...from + keys) {
			final lane:LaneData = lanes[l];
			n += lane.notesBefore(lane.lowerBound(t));
		}
		return n;
	}

	public var lastLen(default, null):Float = 0;

	public function lastBefore(lane:Int, t:Float):Float
	{
		lastLen = 0;
		var k:Int = blockAt(t);
		while (k >= 0) {
			final lanes:Array<LaneData> = blocks[k].lanes;
			if (lanes == null) return Math.NEGATIVE_INFINITY;
			final l:LaneData = lanes[lane];
			final i:Int = l.lowerBound(t);
			if (i > 0) {
				if (l.lens != null) lastLen = l.lens[i - 1];
				return l.times[i - 1];
			}
			if (blocks[k].startMs < t - 10000) return Math.NEGATIVE_INFINITY;
			k--;
		}
		return Math.NEGATIVE_INFINITY;
	}

	public function dispose():Void
	{
		if (streaming) {
			stop = true;
			wake.release();
			threadDone.wait(5);
			streaming = false;
		}
		for (b in blocks) b.lanes = null;
	}
}