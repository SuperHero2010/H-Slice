package backend.play;

import flixel.graphics.FlxGraphic;
import flixel.graphics.frames.FlxAtlasFrames;
import flixel.graphics.frames.FlxFrame;
import flixel.math.FlxRect;
import openfl.display.BitmapData;

class NoteSkin
{
	public var graphic:FlxGraphic;
	public var frames:FlxAtlasFrames;
	public var left:Array<FlxFrame> = [];
	public var down:Array<FlxFrame> = [];
	public var up:Array<FlxFrame> = [];
	public var right:Array<FlxFrame> = [];

	public var width:Float = 0;
	public var height:Float = 0;

	public function new(graphic:FlxGraphic, frames:FlxAtlasFrames)
	{
		this.graphic = graphic;
		this.frames = frames;

		// Load frames for each direction
		for (i in 0...4) {
			left.push(getFrame('purple' + i));
			down.push(getFrame('blue' + i));
			up.push(getFrame('green' + i));
			right.push(getFrame('red' + i));
		}

		if (left.length > 0 && left[0] != null) {
			width = left[0].frame.width;
			height = left[0].frame.height;
		}
	}

	function getFrame(name:String):FlxFrame
	{
		if (frames == null) return null;
		return frames.getByName(name);
	}

	public function getFrameByLane(lane:Int, anim:Int):FlxFrame
	{
		switch (lane % 4) {
			case 0: return left[anim % left.length];
			case 1: return down[anim % down.length];
			case 2: return up[anim % up.length];
			case 3: return right[anim % right.length];
		}
		return left[0];
	}

	public static function load(path:String):NoteSkin
	{
		final graphic:FlxGraphic = FlxGraphic.fromAsset(path);
		if (graphic == null) return null;

		final frames:FlxAtlasFrames = Paths.getSparrowAtlas(path);
		return new NoteSkin(graphic, frames);
	}

	public function dispose():Void
	{
		if (graphic != null) {
			graphic.destroy();
			graphic = null;
		}
		frames = null;
		left = [];
		down = [];
		up = [];
		right = [];
	}
}