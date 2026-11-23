package backend;

class ChartMeta
{
	public var song:String = '';
	public var bpm:Float = 100;
	public var speed:Float = 1;
	public var keys:Int = 4;
	public var format:String = '';
	public var entries:Float = 0;
	public var firstMs:Float = 0;
	public var lastMs:Float = 0;
	public var nps:Float = 0;
	public var maxNps:Float = 0;
	public var parts:Array<SplitPart> = [];

	public function new() {}

	public function measure(b:backend.chart.NoteBuilder):Void
	{
		entries = b.totalEntries();
		if (entries > 0) {
			var first:Float = Math.POSITIVE_INFINITY;
			var last:Float = 0;
			for (l in b.lanes) {
				if (l.length > 0) {
					if (l.times[0] < first) first = l.times[0];
					if (l.times[l.length - 1] > last) last = l.times[l.length - 1];
				}
			}
			firstMs = first / 1000;
			lastMs = last / 1000;
			final duration:Float = (lastMs - firstMs) / 1000;
			if (duration > 0) nps = entries / duration;
		}
	}

	public function toObject():Dynamic
	{
		return {
			song: song,
			bpm: bpm,
			speed: speed,
			keys: keys,
			format: format,
			entries: entries,
			firstMs: firstMs,
			lastMs: lastMs,
			nps: nps,
			maxNps: maxNps,
			parts: parts
		};
	}

	public static function fromObject(o:Dynamic):ChartMeta
	{
		final m:ChartMeta = new ChartMeta();
		m.song = o.song != null ? o.song : '';
		m.bpm = o.bpm != null ? o.bpm : 100;
		m.speed = o.speed != null ? o.speed : 1;
		m.keys = o.keys != null ? Std.int(o.keys) : 4;
		m.format = o.format != null ? o.format : '';
		m.entries = o.entries != null ? o.entries : 0;
		m.firstMs = o.firstMs != null ? o.firstMs : 0;
		m.lastMs = o.lastMs != null ? o.lastMs : 0;
		m.nps = o.nps != null ? o.nps : 0;
		m.maxNps = o.maxNps != null ? o.maxNps : 0;
		if (o.parts != null) {
			for (p in o.parts) {
				final part:SplitPart = new SplitPart();
				part.speed = p.speed;
				part.bpm = p.bpm;
				part.startMs = p.startMs;
				part.endMs = p.endMs;
				m.parts.push(part);
			}
		}
		return m;
	}
}

class SplitPart
{
	public var speed:Float = 1;
	public var bpm:Float = 100;
	public var startMs:Float = 0;
	public var endMs:Float = 0;

	public function new() {}
}