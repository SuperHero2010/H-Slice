package backend.play;

class NoteBlock
{
	public var index:Int = 0;
	public var startMs:Float = 0;
	public var endMs:Float = 0;
	public var lanes:Array<LaneData> = null;
	public var notes:Float = 0;
	public var drawn:Float = 0;
	public var before:Array<Float> = [0, 0];

	public function new(index:Int, startMs:Float, endMs:Float)
	{
		this.index = index;
		this.startMs = startMs;
		this.endMs = endMs;
	}
}

class LaneData
{
	public var times:Array<Float> = [];
	public var cum:Array<Float> = [];
	public var lens:Array<Float> = null;
	public var n:Int = 0;

	public function new() {}

	public function lowerBound(t:Float):Int
	{
		var lo:Int = 0, hi:Int = n;
		while (lo < hi) {
			final mid:Int = (lo + hi) >>> 1;
			if (times[mid] < t) lo = mid + 1;
			else hi = mid;
		}
		return lo;
	}

	public function notesBefore(i:Int):Float
	{
		if (i <= 0) return 0;
		if (i >= n) return cum[n - 1];
		return cum[i - 1];
	}
}