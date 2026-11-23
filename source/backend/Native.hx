package backend;

import lime.app.Application;
import lime.system.Display;
import lime.system.System;

import flixel.util.FlxColor;

#if (cpp && windows)
@:buildXml('
<target id="haxe">
	<lib name="dwmapi.lib" if="windows"/>
	<lib name="gdi32.lib" if="windows"/>
	<lib name="lzma.lib" if="windows"/>
</target>
')
@:cppFileCode('
#include <windows.h>
#include <dwmapi.h>
#include <winuser.h>
#include <wingdi.h>

#include <LzmaDec.h>
#include <LzmaEnc.h>

static void *SzAlloc(void *p, size_t size) { p = p; return malloc(size); }
static void SzFree(void *p, void *address) { p = p; free(address); }
static ISzAlloc g_Alloc = { SzAlloc, SzFree };

extern "C" int lzmaEncode(unsigned char *src, int srcLen, unsigned char *dst, int dstLen, unsigned char *props, int level, int dictSize, int lc, int lp, int pb) {
	CLzmaEncProps props2;
	LzmaEncProps_Init(&props2);
	props2.level = level;
	props2.dictSize = dictSize;
	props2.lc = lc;
	props2.lp = lp;
	props2.pb = pb;
	LzmaEncProps_Normalize(&props2);

	SizeT propsSize = 5;
	LzmaEncode(props, &propsSize, src, srcLen, dst, &dstLen, &props2, &g_Alloc, &g_Alloc);
	return (int)dstLen;
}

extern "C" bool lzmaDecode(unsigned char *src, int srcLen, unsigned char *dst, int dstLen, unsigned char *props, int propsSize) {
	ELzmaStatus status;
	SizeT srcLen2 = srcLen;
	SizeT dstLen2 = dstLen;
	return LzmaDecode(dst, &dstLen2, src, &srcLen2, props, propsSize, LZMA_FINISH_END, &status, &g_Alloc) == SZ_OK;
}
')
#end
class Native
{
	public static function __init__():Void
	{
		registerDPIAware();
	}

	public static function registerDPIAware():Void
	{
		#if (cpp && windows)
		untyped __cpp__('
			SetProcessDPIAware();	
			#ifdef DPI_AWARENESS_CONTEXT
			SetProcessDpiAwarenessContext(
				#ifdef DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2
				DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2
				#else
				DPI_AWARENESS_CONTEXT_SYSTEM_AWARE
				#endif
			);
			#endif
		');
		#end
	}

	private static var fixedScaling:Bool = false;
	public static function fixScaling():Void
	{
		if (fixedScaling) return;
		fixedScaling = true;

		#if (cpp && windows)
		final display:Null<Display> = System.getDisplay(0);
		if (display != null)
		{
			final dpiScale:Float = display.dpi / 96;
			@:privateAccess Application.current.window.width = Std.int(Main.game.width * dpiScale);
			@:privateAccess Application.current.window.height = Std.int(Main.game.height * dpiScale);

			Application.current.window.x = Std.int((Application.current.window.display.bounds.width - Application.current.window.width) / 2);
			Application.current.window.y = Std.int((Application.current.window.display.bounds.height - Application.current.window.height) / 2);
		}
		#end
	}

	#if cpp
	@:cffi @:noCompletion
	public static function lzmaEncode(src:haxe.io.Bytes, srcOffset:Int, srcLen:Int, dst:haxe.io.Bytes, dstOffset:Int, props:haxe.io.Bytes, level:Int, dictSize:Int, lc:Int, lp:Int, pb:Int):Int;

	@:cffi @:noCompletion
	public static function lzmaDecode(src:haxe.io.Bytes, srcOffset:Int, srcLen:Int, dst:haxe.io.Bytes, dstOffset:Int, dstLen:Int, props:haxe.io.Bytes, propsSize:Int):Bool;
	#end
}