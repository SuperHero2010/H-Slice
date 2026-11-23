package backend.play;

import flixel.FlxSprite;
import flixel.graphics.frames.FlxFrame;
import flixel.math.FlxMatrix;
import flixel.math.FlxPoint;
import flixel.util.FlxColor;
import openfl.display.BitmapData;
import openfl.geom.Matrix;

class NoteLayer extends FlxSprite
{
	public var skin:NoteSkin;
	public var lane:Int = 0;

	var quadData:Array<Float> = [];
	var quadCount:Int = 0;
	static inline final QUAD_SIZE:Int = 24; // 6 vertices * 4 floats (x, y, u, v)

	public function new(skin:NoteSkin, lane:Int)
	{
		super();
		this.skin = skin;
		this.lane = lane;

		// Create a canvas for batch rendering
		makeGraphic(2000, 2000, FlxColor.TRANSPARENT, true);
		visible = false; // Don't render directly, used for texture
	}

	public function addQuad(x:Float, y:Float, scaleX:Float, scaleY:Float, rotation:Float, frame:FlxFrame):Void
	{
		if (frame == null) return;

		final fw:Float = frame.frame.width;
		final fh:Float = frame.frame.height;
		final u:Float = frame.frame.x / skin.graphic.bitmap.width;
		final v:Float = frame.frame.y / skin.graphic.bitmap.height;
		final uw:Float = frame.frame.width / skin.graphic.bitmap.width;
		final vh:Float = frame.frame.height / skin.graphic.bitmap.height;

		// Calculate transformed corners
		final cos:Float = Math.cos(rotation);
		final sin:Float = Math.sin(rotation);

		final x1:Float = -fw * scaleX / 2;
		final y1:Float = -fh * scaleY / 2;
		final x2:Float = fw * scaleX / 2;
		final y2:Float = fh * scaleY / 2;

		// Top-left
		quadData.push(x + x1 * cos - y1 * sin);
		quadData.push(y + x1 * sin + y1 * cos);
		quadData.push(u);
		quadData.push(v);

		// Top-right
		quadData.push(x + x2 * cos - y1 * sin);
		quadData.push(y + x2 * sin + y1 * cos);
		quadData.push(u + uw);
		quadData.push(v);

		// Bottom-right
		quadData.push(x + x2 * cos - y2 * sin);
		quadData.push(y + x2 * sin + y2 * cos);
		quadData.push(u + uw);
		quadData.push(v + vh);

		// Bottom-left
		quadData.push(x + x1 * cos - y2 * sin);
		quadData.push(y + x1 * sin + y2 * cos);
		quadData.push(u);
		quadData.push(v + vh);

		quadCount++;
	}

	public function clear():Void
	{
		quadData = [];
		quadCount = 0;
	}

	public function getQuadCount():Int
		return quadCount;

	override public function destroy():Void
	{
		super.destroy();
		if (skin != null) {
			skin.dispose();
			skin = null;
		}
		quadData = null;
	}
}