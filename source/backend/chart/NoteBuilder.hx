package backend.chart;

class NoteBuilder
{
	public var keys(default, null):Int;
	public var laneCount(default, null):Int;
	public var lanes(default, null):Array<BuilderLane>;
	public var dropped:Float = 0;

	public function new(keys:Int)
	{
		this.keys = keys < 1 ? 4 : keys;
		laneCount = this.keys * 2;
		lanes = [for (i in 0...laneCount) new BuilderLane()];
	}

	public inline function add(timeMs:Float, lane:Int, lengthMs:Float):Void
	{
		if (Math.isNaN(timeMs) || lane < 0 || lane >= laneCount) {
			dropped++;
			return;
		}
		lanes[lane].add(Math.fround(timeMs * 1000), lengthMs > 0 ? Math.fround(lengthMs * 1000) : 0, 1);
	}

	public inline function laneOf(raw:Int, right:Bool):Int
		return (right ? keys : 0) + raw % keys;

	public function finish():Void
	{
		for (l in lanes) l.finish();
	}

	public function totalEntries():Float
	{
		var n:Float = 0;
		for (l in lanes) n += l.length;
		return n;
	}
}

class BuilderLane
{
	public var times:Array<Float> = [];
	public var counts:Array<Int> = [];

	public var lens:Array<Float> = [];
	public var length:Int = 0;
	public var notes:Float = 0;

	var sorted:Bool = true;
	var last:Float = Math.NEGATIVE_INFINITY;

	public function new() {}

	public inline function add(us:Float, lenUs:Float, count:Int):Void
	{
		notes += count;
		if (us == last) {
			final i:Int = length - 1;
			counts[i] += count;
			if (lenUs > lens[i]) lens[i] = lenUs;
			return;
		}
		if (us < last) sorted = false;
		times[length] = us;
		counts[length] = count;
		lens[length] = lenUs;
		length++;
		last = us;
	}

	public function takeFrom(o:BuilderLane):Void
	{
		if (o.length == 0) return;
		if (length == 0) {
			times = o.times;
			counts = o.counts;
			lens = o.lens;
			length = o.length;
			notes = o.notes;
			sorted = o.sorted;
			last = o.last;
		} else {
			for (i in 0...o.length) add(o.times[i], o.lens[i], o.counts[i]);
		}
		o.times = [];
		o.counts = [];
		o.lens = [];
		o.length = 0;
		o.notes = 0;
	}

	public function finish():Void
	{
		if (!sorted) {
			sortAll();
			mergeEqual();
			sorted = true;
		}
		last = length > 0 ? times[length - 1] : Math.NEGATIVE_INFINITY;
	}

	function sortAll():Void
	{
		final n:Int = length;
		var t:Array<Float> = times, c:Array<Int> = counts, l:Array<Float> = lens;
		var t2:Array<Float> = [], c2:Array<Int> = [], l2:Array<Float> = [];
		t2[n - 1] = 0;
		c2[n - 1] = 0;
		l2[n - 1] = 0;

		final runs:Array<Int> = [0];
		for (i in 1...n) if (t[i] < t[i - 1]) runs.push(i);
		runs.push(n);
		var bounds:Array<Int> = runs;
		while (bounds.length > 2) {
			final next:Array<Int> = [0];
			var r:Int = 0;
			while (r + 1 < bounds.length) {
				final a0:Int = bounds[r];
				final a1:Int = bounds[r + 1];
				final b1:Int = r + 2 < bounds.length ? bounds[r + 2] : a1;
				var i:Int = a0, j:Int = a1, k:Int = a0;
				while (i < a1 && j < b1) {
					if (t[j] < t[i]) {
						t2[k] = t[j];
						c2[k] = c[j];
						l2[k] = l[j];
						j++;
					} else {
						t2[k] = t[i];
						c2[k] = c[i];
						l2[k] = l[i];
						i++;
					}
					k++;
				}
				while (i < a1) {
					t2[k] = t[i];
					c2[k] = c[i];
					l2[k] = l[i];
					i++;
					k++;
				}
				while (j < b1) {
					t2[k] = t[j];
					c2[k] = c[j];
					l2[k] = l[j];
					j++;
					k++;
				}
				next.push(b1);
				r += 2;
			}
			bounds = next;
			final st = t; t = t2; t2 = st;
			final sc = c; c = c2; c2 = sc;
			final sl = l; l = l2; l2 = sl;
		}
		times = t;
		counts = c;
		lens = l;
	}

	function mergeEqual():Void
	{
		if (length == 0) return;
		var w:Int = 0;
		for (i in 1...length) {
			if (times[i] == times[w]) {
				counts[w] += counts[i];
				if (lens[i] > lens[w]) lens[w] = lens[i];
			} else {
				w++;
				times[w] = times[i];
				counts[w] = counts[i];
				lens[w] = lens[i];
			}
		}
		length = w + 1;
		times.resize(length);
		counts.resize(length);
		lens.resize(length);
	}
}
