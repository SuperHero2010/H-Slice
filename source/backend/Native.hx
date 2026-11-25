package backend;

import lime.app.Application;
import lime.system.Display;
import lime.system.System;

import flixel.FlxG;
import flixel.util.FlxColor;

#if (cpp && windows)
@:buildXml('
<target id="haxe">
	<lib name="dwmapi.lib" if="windows"/>
	<lib name="gdi32.lib" if="windows"/>
</target>
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
			typedef enum _DPI_AWARENESS_CONTEXT {
				DPI_AWARENESS_CONTEXT_UNAWARE = -1,
				DPI_AWARENESS_CONTEXT_SYSTEM_AWARE = -2,
				DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE = -3,
				DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2 = -4,
				DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V3 = -5
			} DPI_AWARENESS_CONTEXT;

			HMODULE hUser32 = LoadLibraryA("user32.dll");
			if (hUser32) {
				typedef BOOL (WINAPI *SetProcessDpiAwarenessContextProc)(DPI_AWARENESS_CONTEXT);
				SetProcessDpiAwarenessContextProc pSetProcessDpiAwarenessContext = (SetProcessDpiAwarenessContextProc)GetProcAddress(hUser32, "SetProcessDpiAwarenessContext");
				if (pSetProcessDpiAwarenessContext) {
					pSetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
				} else {
					typedef BOOL (WINAPI *SetProcessDPIAwareProc)(void);
					SetProcessDPIAwareProc pSetProcessDPIAware = (SetProcessDPIAwareProc)GetProcAddress(hUser32, "SetProcessDPIAware");
					if (pSetProcessDPIAware) {
						pSetProcessDPIAware();
					}
				}
				FreeLibrary(hUser32);
			}
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
			@:privateAccess Application.current.window.width = Std.int(FlxG.width * dpiScale);
			@:privateAccess Application.current.window.height = Std.int(FlxG.height * dpiScale);

			Application.current.window.x = Std.int((Application.current.window.display.bounds.width - Application.current.window.width) / 2);
			Application.current.window.y = Std.int((Application.current.window.display.bounds.height - Application.current.window.height) / 2);
		}
		#end
	}
}