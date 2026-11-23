package backend.cache;

import backend.ChartMeta;

class CacheEntry
{
	public var key:String;
	public var stamp:String;
	public var meta:ChartMeta;
	public var keys:Int = 4;
	public var blocks:Array<BlockInfo> = [];

	public function new() {}

	public function compBytes():Float
	{
		var n:Float = 0;
		for (b in blocks) n += b.comp;
		return n;
	}

	public function toObject():Dynamic
	{
		return {
			key: key,
			stamp: stamp,
			keys: keys,
			meta: meta != null ? meta.toObject() : null,
			blocks: [for (b in blocks) [b.offset, b.comp, b.raw, b.startUs, b.endUs, b.entries, b.opp, b.player]]
		};
	}

	public static function fromObject(o:Dynamic):CacheEntry
	{
		final e:CacheEntry = new CacheEntry();
		e.key = o.key;
		e.stamp = o.stamp;
		e.keys = o.keys != null ? Std.int(o.keys) : 4;
		e.meta = o.meta != null ? ChartMeta.fromObject(o.meta) : null;
		final list:Array<Dynamic> = o.blocks;
		if (list != null) {
			for (a in list) {
				final b:BlockInfo = new BlockInfo();
				b.offset = a[0];
				b.comp = Std.int(a[1]);
				b.raw = Std.int(a[2]);
				b.startUs = a[3];
				b.endUs = a[4];
				b.entries = a[5];
				b.opp = a[6];
				b.player = a[7];
				e.blocks.push(b);
			}
		}
		return e;
	}
}

class BlockInfo
{
	public var offset:Float = 0;
	public var comp:Int = 0;
	public var raw:Int = 0;
	public var startUs:Float = 0;
	public var endUs:Float = 0;
	public var entries:Float = 0;
	public var opp:Float = 0;
	public var player:Float = 0;

	public function new() {}
}
