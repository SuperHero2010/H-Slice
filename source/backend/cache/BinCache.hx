package backend.cache;

import haxe.io.Bytes;
import backend.ChartMeta;
import backend.chart.NoteBuilder;
import backend.chart.NoteBuilder.BuilderLane;
import backend.Native;
import backend.Paths;
import backend.cache.CacheEntry;

class BinCache
{
	public static inline final MAGIC:String = 'HSLICE';
	public static inline final VERSION:Int = 1;
	static inline final HEADER:Int = 64;

	public static inline final BLOCK_ENTRIES:Int = 1 << 19;

	public var path(default, null):String;

	var entries:Map<String, CacheEntry> = new Map();
	var lock:sys.thread.Mutex = new sys.thread.Mutex();
	var fileEnd:Float = HEADER;

	public static var status:String = null;
	public static var progress:Float = -1;

	public function new(path:String)
	{
		this.path = path;
		try load() catch (e:Dynamic) {
			trace('Cache "$path" not readable, starting a new one: $e');
			entries = new Map();
		}
	}

	public function find(key:String, stamp:String):CacheEntry
	{
		lock.acquire();
		final e:CacheEntry = entries.get(key);
		lock.release();
		return e != null && e.stamp == stamp ? e : null;
	}

	public function anyEntry(key:String):CacheEntry
	{
		lock.acquire();
		final e:CacheEntry = entries.get(key);
		lock.release();
		return e;
	}

	public function fileBytes():Float
		return fileEnd;

	function load():Void
	{
		if (!sys.FileSystem.exists(path)) return;
		final f = sys.io.File.read(path, false);
		if (f == null) throw 'cannot open';
		try {
			final stat:sys.FileStat = sys.FileSystem.stat(path);
			final size:Float = stat.size;
			if (size < HEADER) throw 'too small';
			final head:Bytes = Bytes.alloc(HEADER);
			f.readBytes(head, 0, HEADER);
			if (head.getString(0, 6) != MAGIC) throw 'not a H-Slice cache';
			if (head.getInt32(8) > VERSION) throw 'made by a newer version';
			final at:Float = head.getDouble(16);
			final comp:Int = Std.int(head.getDouble(24));
			final rawLen:Int = Std.int(head.getDouble(32));
			if (comp <= 0 || at + comp > size) throw 'index missing';
			final data:Bytes = Bytes.alloc(comp + 5);
			data.blit(0, head, 40, 5);
			f.readBytes(data, 5, comp);
			final raw:Bytes = NoteCodec.decompress(data, comp + 5, rawLen);
			final index:Dynamic = haxe.Json.parse(raw.toString());
			final list:Array<Dynamic> = index.entries;
			for (o in list) {
				final e:CacheEntry = CacheEntry.fromObject(o);
				entries.set(e.key, e);
			}
			fileEnd = at + comp;
		} catch (e:Dynamic) {
			f.close();
			throw e;
		}
		f.close();
	}

	public function reader():CacheReader
		return new CacheReader(path);

	public function store(key:String, stamp:String, meta:ChartMeta, b:NoteBuilder, threads:Int):CacheEntry
	{
		status = 'cutting into blocks';
		progress = 0;
		final cuts:Array<Float> = cutTimes(b);
		var firstUs:Float = Math.POSITIVE_INFINITY, lastUs:Float = 0;
		for (l in b.lanes) if (l.length > 0) {
			if (l.times[0] < firstUs) firstUs = l.times[0];
			if (l.times[l.length - 1] > lastUs) lastUs = l.times[l.length - 1];
		}
		if (firstUs == Math.POSITIVE_INFINITY) firstUs = 0;
		final blockCount:Int = cuts.length + 1;
		final from:Array<Array<Int>> = [];
		final to:Array<Array<Int>> = [];
		final pos:Array<Int> = [for (l in 0...b.laneCount) 0];
		for (k in 0...blockCount) {
			final cut:Float = k < cuts.length ? cuts[k] : Math.POSITIVE_INFINITY;
			final f:Array<Int> = [];
			final t:Array<Int> = [];
			for (l in 0...b.laneCount) {
				final lane:BuilderLane = b.lanes[l];
				f.push(pos[l]);
				var e:Int = cut == Math.POSITIVE_INFINITY ? lane.length : lowerBound(lane.times, lane.length, cut, pos[l]);
				t.push(e);
				pos[l] = e;
			}
			from.push(f);
			to.push(t);
		}

		final entry:CacheEntry = new CacheEntry();
		entry.key = key;
		entry.stamp = stamp;
		entry.meta = meta;
		entry.keys = b.keys;
		final results:Array<Bytes> = [for (k in 0...blockCount) null];
		final raws:Array<Int> = [for (k in 0...blockCount) 0];
		final errors:Array<String> = [];
		var nextJob:Int = 0;
		var finished:Int = 0;
		final jobLock:sys.thread.Mutex = new sys.thread.Mutex();
		final done:sys.thread.Lock = new sys.thread.Lock();
		final workers:Int = threads < 1 ? 1 : threads > blockCount ? blockCount : threads;
		status = 'compressing';
		for (w in 0...workers) {
			sys.thread.Thread.create(function() {
				while (true) {
					jobLock.acquire();
					final k:Int = nextJob++;
					jobLock.release();
					if (k >= blockCount || errors.length > 0) break;
					try {
						final base:Float = k == 0 ? firstUs : cuts[k - 1];
						final raw:Bytes = NoteCodec.encode(b, from[k], to[k], base);
						final comp:Bytes = NoteCodec.compress(raw);
						jobLock.acquire();
						results[k] = comp;
						raws[k] = raw.length;
						finished++;
						progress = finished / blockCount;
						jobLock.release();
					} catch (e:Dynamic) {
						jobLock.acquire();
						errors.push(Std.string(e));
						jobLock.release();
					}
				}
				done.release();
			});
		}
		for (w in 0...workers) done.wait();
		if (errors.length > 0) throw 'Could not make the cache: ' + errors[0];

		status = 'writing cache.bin';
		lock.acquire();
		try {
			final f = sys.io.File.write(path, true);
			try {
				var at:Float = fileEnd;
				f.seek(Std.int(at), sys.io.FileSeek.SeekBegin);
				for (k in 0...blockCount) {
					final comp:Bytes = results[k];
					f.write(comp);
					final info:CacheEntry.BlockInfo = new CacheEntry.BlockInfo();
					info.offset = at;
					info.comp = comp.length;
					info.raw = raws[k];
					info.startUs = k == 0 ? firstUs : cuts[k - 1];
					info.endUs = k < cuts.length ? cuts[k] : lastUs + 1;
					var opp:Float = 0, pl:Float = 0, n:Float = 0;
					for (l in 0...b.laneCount) {
						final lane:BuilderLane = b.lanes[l];
						var c:Float = 0;
						for (i in from[k][l]...to[k][l]) c += lane.counts[i];
						if (l < b.keys) opp += c;
						else pl += c;
						n += to[k][l] - from[k][l];
					}
					info.entries = n;
					info.opp = opp;
					info.player = pl;
					entry.blocks.push(info);
					at += comp.length;
					results[k] = null;
				}
				entries.set(key, entry);
				writeIndex(f, at);
				f.close();
			} catch (e:Dynamic) {
				f.close();
				throw e;
			}
		} catch (e:Dynamic) {
			lock.release();
			status = null;
			throw e;
		}
		lock.release();
		maybeCompact();
		status = null;
		progress = -1;
		return entry;
	}

	function writeIndex(f:sys.io.FileOutput, at:Float):Void
	{
		final list:Array<Dynamic> = [for (e in entries) e.toObject()];
		final raw:Bytes = Bytes.ofString(haxe.Json.stringify({entries: list}));
		final comp:Bytes = NoteCodec.compress(raw);
		f.seek(Std.int(at), sys.io.FileSeek.SeekBegin);
		f.write(comp.sub(5, comp.length - 5));
		f.flush();
		final head:Bytes = Bytes.alloc(HEADER);
		head.blit(0, Bytes.ofString(MAGIC), 0, 6);
		head.setInt32(8, VERSION);
		head.setDouble(16, at);
		head.setDouble(24, comp.length - 5);
		head.setDouble(32, raw.length);
		head.blit(40, comp, 0, 5);
		f.seek(0, sys.io.FileSeek.SeekBegin);
		f.write(head);
		f.flush();
		fileEnd = at + comp.length - 5;
	}

	function liveBytes():Float
	{
		var n:Float = HEADER;
		for (e in entries) for (b in e.blocks) n += b.comp;
		return n;
	}

	public function maybeCompact(force:Bool = false):Void
	{
		lock.acquire();
		try {
			final live:Float = liveBytes();
			final dead:Float = fileEnd - live;
			if (force || (dead > live && dead > 8 * 1048576.0)) compact();
		} catch (e:Dynamic) {
			trace('Could not tidy the cache: $e');
		}
		lock.release();
	}

	function compact():Void
	{
		status = 'tidying cache.bin';
		final temp:String = path + '.tmp';
		final src = sys.io.File.read(path, false);
		if (src == null) return;
		final dst = sys.io.File.write(temp, true);
		if (dst == null) {
			src.close();
			return;
		}
		try {
			final head:Bytes = Bytes.alloc(HEADER);
			head.blit(0, Bytes.ofString(MAGIC), 0, 6);
			head.setInt32(8, VERSION);
			dst.write(head);
			var at:Float = HEADER;
			var buf:Bytes = Bytes.alloc(1 << 20);
			final moved:Map<String, Array<Float>> = new Map();
			for (e in entries) {
				final offsets:Array<Float> = [];
				for (b in e.blocks) {
					if (buf.length < b.comp) buf = Bytes.alloc(b.comp);
					src.seek(Std.int(b.offset), sys.io.FileSeek.SeekBegin);
					src.readBytes(buf, 0, b.comp);
					dst.write(buf);
					offsets.push(at);
					at += b.comp;
				}
				moved.set(e.key, offsets);
			}
			for (e in entries) {
				final offsets:Array<Float> = moved.get(e.key);
				for (i in 0...e.blocks.length) e.blocks[i].offset = offsets[i];
			}
			writeIndex(dst, at);
			dst.close();
			src.close();
			sys.FileSystem.deleteFile(path);
			sys.FileSystem.rename(temp, path);
		} catch (e:Dynamic) {
			dst.close();
			src.close();
			try sys.FileSystem.deleteFile(temp) catch (x:Dynamic) {}
			entries = new Map();
			try load() catch (x:Dynamic) {}
			throw e;
		}
	}

	public function remove(key:String):Void
	{
		lock.acquire();
		try {
			if (entries.exists(key)) {
				entries.remove(key);
				final f = sys.io.File.write(path, true);
				writeIndex(f, fileEnd);
				f.close();
			}
		} catch (e:Dynamic) {
			trace('Could not update the cache: $e');
		}
		lock.release();
	}

	static function cutTimes(b:NoteBuilder):Array<Float>
	{
		final total:Float = b.totalEntries();
		if (total <= BLOCK_ENTRIES) return [];
		final step:Int = 64;
		final sample:Array<Float> = [];
		for (l in b.lanes) {
			var i:Int = 0;
			while (i < l.length) {
				sample.push(l.times[i]);
				i += step;
			}
		}
		sample.sort((x, y) -> x < y ? -1 : x > y ? 1 : 0);
		final per:Int = Std.int(BLOCK_ENTRIES / step);
		final cuts:Array<Float> = [];
		var k:Int = per;
		while (k < sample.length) {
			final t:Float = sample[k];
			if (cuts.length == 0 || t > cuts[cuts.length - 1]) cuts.push(t);
			k += per;
		}
		return cuts;
	}

	static function lowerBound(a:Array<Float>, n:Int, t:Float, from:Int):Int
	{
		var lo:Int = from, hi:Int = n;
		while (lo < hi) {
			final mid:Int = (lo + hi) >>> 1;
			if (a[mid] < t) lo = mid + 1;
			else hi = mid;
		}
		return lo;
	}

	public static function getCachePath():String
	{
		return Paths.getEnginePath() + 'cache.bin';
	}
}