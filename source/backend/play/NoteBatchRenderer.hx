package backend.play;

import flixel.FlxG;
import flixel.graphics.FlxGraphic;
import flixel.graphics.frames.FlxFrame;
import flixel.math.FlxMatrix;
import flixel.math.FlxPoint;
import flixel.math.FlxRect;
import flixel.util.FlxColor;
import openfl.display.BitmapData;
import openfl.display.Graphics;
import openfl.display.Sprite;
import openfl.geom.Matrix;

class NoteBatchRenderer
{
	public var layers:Array<NoteLayer> = [];
	public var skin:NoteSkin;

	var renderSprite:Sprite;
	var renderBitmap:BitmapData;

	public var viewY:Float = 0;
	public var viewHeight:Float = 720;
	public var cullDistance:Float = 2000;

	public function new(skin:NoteSkin, laneCount:Int)
	{
		this.skin = skin;

		// Create render sprite
		renderSprite = new Sprite();
		FlxG.stage.addChild(renderSprite);
		renderSprite.visible = false;

		// Create layers for each lane
		for (i in 0...laneCount) {
			layers.push(new NoteLayer(skin, i));
		}
	}

	public function addQuad(lane:Int, x:Float, y:Float, scaleX:Float, scaleY:Float, rotation:Float, anim:Int):Void
	{
		if (lane < 0 || lane >= layers.length) return;

		// Frustum culling - skip notes outside view
		if (y < viewY - cullDistance || y > viewY + viewHeight + cullDistance) return;

		// LOD (Level of Detail) - reduce scale for distant notes
		final distance:Float = Math.abs(y - (viewY + viewHeight / 2));
		if (distance > 1000) {
			final lodScale:Float = Math.max(0.5, 1 - (distance - 1000) / 2000);
			scaleX *= lodScale;
			scaleY *= lodScale;
		}

		final frame:FlxFrame = skin.getFrameByLane(lane, anim);
		layers[lane].addQuad(x, y, scaleX, scaleY, rotation, frame);
	}

	public function updateView(cameraY:Float, screenHeight:Float):Void
	{
		viewY = cameraY;
		viewHeight = screenHeight;
	}

	public function render():Void
	{
		if (renderBitmap == null) {
			renderBitmap = new BitmapData(FlxG.width, FlxG.height, true, FlxColor.TRANSPARENT);
		}

		renderBitmap.fillRect(renderBitmap.rect, FlxColor.TRANSPARENT);

		for (layer in layers) {
			if (layer.getQuadCount() == 0) continue;

			// Render quads for this layer
			renderLayer(layer);
		}
	}

	function renderLayer(layer:NoteLayer):Void
	{
		final graphics:Graphics = renderSprite.graphics;
		graphics.clear();

		// Draw all quads in this layer
		final data:Array<Float> = layer.quadData;
		final quadCount:Int = layer.quadCount;

		for (i in 0...quadCount) {
			final idx:Int = i * 24;
			final x1:Float = data[idx];
			final y1:Float = data[idx + 1];
			final x2:Float = data[idx + 4];
			final y2:Float = data[idx + 5];
			final x3:Float = data[idx + 8];
			final y3:Float = data[idx + 9];
			final x4:Float = data[idx + 12];
			final y4:Float = data[idx + 13];

			// Draw quad as polygon
			graphics.beginBitmapFill(skin.graphic.bitmap);
			graphics.moveTo(x1, y1);
			graphics.lineTo(x2, y2);
			graphics.lineTo(x3, y3);
			graphics.lineTo(x4, y4);
			graphics.endFill();
		}

		// Draw to bitmap
		renderBitmap.draw(renderSprite);
	}

	public function clear():Void
	{
		for (layer in layers) {
			layer.clear();
		}
	}

	public function getRenderBitmap():BitmapData
		return renderBitmap;

	public function dispose():Void
	{
		if (renderSprite != null) {
			if (renderSprite.parent != null) renderSprite.parent.removeChild(renderSprite);
			renderSprite = null;
		}
		if (renderBitmap != null) {
			renderBitmap.dispose();
			renderBitmap = null;
		}
		for (layer in layers) {
			layer.destroy();
		}
		layers = [];
		if (skin != null) {
			skin.dispose();
			skin = null;
		}
	}
}
