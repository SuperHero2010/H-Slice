package backend.cache;

import haxe.io.Bytes;
import haxe.zip.Compress;
import haxe.zip.Uncompress;
import backend.chart.NoteBuilder;
import backend.play.NoteBlock;
import backend.play.NoteBlock.LaneData;

class NoteCodec
{
	static inline final HAS_COUNTS:Int = 1;
	static inline final HAS_LENS:Int = 2;

	public static inline final LZMA_LEVEL:Int = 9;

	public static function encode(b:NoteBuilder, from:Array<Int>, to:Array<Int>, baseUs:Float):Bytes
	{
		final out:VarintWriter = new VarintWriter(1024);
		var flags:Int = 0;
		for (l in 0...b.laneCount) {
			final lane = b.lanes[l];
			for (i in from[l]...to[l]) {
				if (lane.counts[i] != 1) flags |= HAS_COUNTS;
				if (lane.lens[i] != 0) flags |= HAS_LENS;
			}
		}
		out.byte(flags);
		out.int(b.laneCount);
		for (l in 0...b.laneCount) out.int(to[l] - from[l]);
		for (l in 0...b.laneCount) {
			final lane = b.lanes[l];
			var prev:Float = baseUs;
			for (i in from[l]...to[l]) {
				final t:Float = lane.times[i];
				out.num(t - prev);
				prev = t;
			}
		}
		if (flags & HAS_COUNTS != 0) for (l in 0...b.laneCount) {
			final lane = b.lanes[l];
			for (i in from[l]...to[l]) out.int(lane.counts[i] - 1);
		}
		if (flags & HAS_LENS != 0) for (l in 0...b.laneCount) {
			final lane = b.lanes[l];
			for (i in from[l]...to[l]) out.num(lane.lens[i]);
		}
		return out.done();
	}

	public static function compress(raw:Bytes):Bytes
	{
		return Compress.run(raw, 9);
	}

	public static function decompress(comp:Bytes, compLen:Int, rawLen:Int):Bytes
	{
		return Uncompress.run(comp, rawLen);
	}

	public static function decode(raw:Bytes, baseUs:Float, mergeMs:Float, into:NoteBlock):Void
	{
		final r:VarintReader = new VarintReader(raw);
		final flags:Int = r.byte();
		final laneCount:Int = r.int();
		final sizes:Array<Int> = [for (l in 0...laneCount) r.int()];
		final timesUs:Array<Array<Float>> = [];
		for (l in 0...laneCount) {
			final n:Int = sizes[l];
			final t:Array<Float> = [];
			if (n > 0) t[n - 1] = 0;
			var prev:Float = baseUs;
			for (i in 0...n) {
				prev += r.num();
				t[i] = prev;
			}
			timesUs.push(t);
		}
		final counts:Array<Array<Int>> = [];
		if (flags & HAS_COUNTS != 0) for (l in 0...laneCount) {
			final n:Int = sizes[l];
			final c:Array<Int> = [];
			if (n > 0) c[n - 1] = 0;
			for (i in 0...n) c[i] = r.int() + 1;
			counts.push(c);
		}
		final lens:Array<Array<Float>> = [];
		if (flags & HAS_LENS != 0) for (l in 0...laneCount) {
			final n:Int = sizes[l];
			final c:Array<Float> = [];
			if (n > 0) c[n - 1] = 0;
			for (i in 0...n) c[i] = r.num();
			lens.push(c);
		}

		final mergeUs:Float = mergeMs > 0 ? mergeMs * 1000 : 0;
		final outLanes:Array<LaneData> = [];
		var total:Float = 0;
		var shown:Float = 0;
		for (l in 0...laneCount) {
			final src:Array<Float> = timesUs[l];
			final cnt:Array<Int> = counts.length > 0 ? counts[l] : null;
			final ln:Array<Float> = lens.length > 0 ? lens[l] : null;
			final n:Int = sizes[l];
			final lane:LaneData = new LaneData();
			final times:Array<Float> = [];
			final cum:Array<Float> = [];
			final outLens:Array<Float> = ln != null ? [] : null;
			var w:Int = 0;
			var run:Float = 0;
			var i:Int = 0;
			while (i < n) {
				final start:Float = src[i];
				var c:Float = cnt != null ? cnt[i] : 1;
				var hold:Float = ln != null ? ln[i] : 0;
				var j:Int = i + 1;
				if (mergeUs > 0) {
					while (j < n && src[j] - start < mergeUs) {
						c += cnt != null ? cnt[j] : 1;
						if (ln != null && ln[j] > hold) hold = ln[j];
						j++;
					}
				}
				run += c;
				times[w] = start / 1000;
				cum[w] = run;
				if (outLens != null) outLens[w] = hold / 1000;
				w++;
				i = j;
			}
			lane.n = w;
			lane.times = times;
			lane.cum = cum;
			lane.lens = outLens;
			total += run;
			shown += w;
			outLanes.push(lane);
		}
		into.notes = total;
		into.drawn = shown;
		into.lanes = outLanes;
	}
}

class VarintWriter
{
	var buf:Bytes;
	var pos:Int = 0;

	public function new(cap:Int)
		buf = Bytes.alloc(cap);

	inline function room(n:Int):Void
	{
		if (pos + n > buf.length) {
			var cap:Int = buf.length * 2;
			while (cap < pos + n) cap *= 2;
			final b:Bytes = Bytes.alloc(cap);
			b.blit(0, buf, 0, pos);
			buf = b;
		}
	}

	public inline function byte(v:Int):Void
	{
		room(1);
		buf.set(pos++, v);
	}

	public inline function int(v:Int):Void
	{
		room(5);
		var x:Int = v;
		while (x >>> 7 != 0) {
			buf.set(pos++, (x & 0x7F) | 0x80);
			x = x >>> 7;
		}
		buf.set(pos++, x);
	}

	public inline function num(v:Float):Void
	{
		if (v >= 0 && v < 2147483648.0) int(Std.int(v));
		else {
			room(10);
			var x:Float = v < 0 ? 0 : v;
			while (x >= 128) {
				final low:Float = x - Math.ffloor(x / 128) * 128;
				buf.set(pos++, Std.int(low) | 0x80);
				x = Math.ffloor(x / 128);
			}
			buf.set(pos++, Std.int(x));
		}
	}

	public function done():Bytes
		return buf.sub(0, pos);
}

class VarintReader
{
	var buf:Bytes;
	var pos:Int = 0;

	public function new(b:Bytes)
		buf = b;

	public inline function byte():Int
		return buf.get(pos++);

	public inline function int():Int
	{
		var v:Int = 0, shift:Int = 0;
		while (true) {
			final b:Int = buf.get(pos++);
			v |= (b & 0x7F) << shift;
			if (b < 0x80) break;
			shift += 7;
		}
		return v;
	}

	public inline function num():Float
	{
		var b:Int = buf.get(pos++);
		if (b < 0x80) return b;
		var v:Float = b & 0x7F;
		var mul:Float = 128;
		while (true) {
			b = buf.get(pos++);
			v += (b & 0x7F) * mul;
			if (b < 0x80) break;
			mul *= 128;
		}
		return v;
	}
}