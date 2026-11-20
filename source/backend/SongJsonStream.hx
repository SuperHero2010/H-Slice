package backend;

import haxe.Timer;
import haxe.ds.Vector;
import sys.io.FileInput;

/**
Streaming JSON parser for large files.
Reads file in chunks instead of loading entire file into memory.
**/
class SongJsonStream
{
	var file:FileInput;
	var buffer:haxe.io.Bytes;
	var bufferPos:Int;
	var bufferSize:Int;
	var filePos:Int;
	var time:Float = Timer.stamp();
	public static var skipChart:Bool = false;
	public static var log:Bool = true;
	var lastKey:String = null;

	static inline var CHUNK_SIZE = 1024 * 1024; // 1MB chunks

	function new(filePath:String)
	{
		this.file = sys.io.File.read(filePath, false);
		this.buffer = haxe.io.Bytes.alloc(CHUNK_SIZE);
		this.bufferPos = 0;
		this.bufferSize = 0;
		this.filePos = 0;
	}

	static public inline function parse(filePath:String):Dynamic
	{
		var parser = new SongJsonStream(filePath);
		var result = parser.doParse();
		parser.file.close();
		return result;
	}

	function doParse():Dynamic
	{
		var result = parseRec();
		if (log) Sys.println('Parsed $filePos bytes');
		return result;
	}

	function readByte():Int
	{
		if (bufferPos >= bufferSize)
		{
			fillBuffer();
		}
		if (bufferPos >= bufferSize)
		{
			return -1; // EOF
		}
		return buffer.get(bufferPos++);
	}

	function fillBuffer():Void
	{
		bufferSize = file.readBytes(buffer, 0, CHUNK_SIZE);
		bufferPos = 0;
	}

	function skipWhitespace():Void
	{
		while (true)
		{
			var c = readByte();
			if (c == -1) return;
			switch (c)
			{
				case ' '.code, '\r'.code, '\n'.code, '\t'.code:
					// continue
				default:
					bufferPos--; // put back
					return;
			}
		}
	}

	function parseRec():Dynamic
	{
		skipWhitespace();
		var c = readByte();
		if (c == -1) return null;

		switch (c)
		{
			case '{'.code:
				return parseObject();
			case '['.code:
				return parseArray();
			case '"'.code:
				return parseString();
			case 't'.code:
				return parseTrue();
			case 'f'.code:
				return parseFalse();
			case 'n'.code:
				return parseNull();
			case '-'.code, '0'.code, '1'.code, '2'.code, '3'.code, '4'.code, '5'.code, '6'.code, '7'.code, '8'.code, '9'.code:
				bufferPos--; // put back
				return parseNumber();
			default:
				throw 'Invalid JSON at position $filePos';
		}
	}

	function parseObject():Dynamic
	{
		var obj = {};
		skipWhitespace();

		while (true)
		{
			var c = readByte();
			if (c == -1) throw 'Unexpected EOF in object';

			if (c == '}'.code)
			{
				return obj;
			}

			if (c == '"'.code)
			{
				bufferPos--; // put back quote
				var key = parseString();
				lastKey = key; // Track last key for skip detection
				skipWhitespace();

				var colon = readByte();
				if (colon != ':'.code) throw 'Expected colon at position $filePos';

				skipWhitespace();
				var value = parseRec();
				Reflect.setField(obj, key, value);

				skipWhitespace();
				var next = readByte();
				if (next == ','.code)
				{
					skipWhitespace();
					continue;
				}
				else if (next == '}'.code)
				{
					return obj;
				}
				else
				{
					throw 'Expected comma or } at position $filePos';
				}
			}
		}
		return obj;
	}

	function parseArray():Dynamic
	{
		var arr:Array<Dynamic> = [];
		skipWhitespace();

		// Check if this is the notes array and we should skip it
		if (skipChart && isNotesArray())
		{
			skipArray();
			return [];
		}

		while (true)
		{
			var c = readByte();
			if (c == -1) throw 'Unexpected EOF in array';

			if (c == ']'.code)
			{
				return arr;
			}

			bufferPos--; // put back
			var value = parseRec();
			arr.push(value);

			skipWhitespace();
			var next = readByte();
			if (next == ','.code)
			{
				skipWhitespace();
				continue;
			}
			else if (next == ']'.code)
			{
				return arr;
			}
			else
			{
				throw 'Expected comma or ] at position $filePos';
			}
		}
	}

	function isNotesArray():Bool
	{
		// Check if the last key parsed was "notes"
		return lastKey == "notes";
	}

	function skipArray():Void
	{
		// Fast-forward to the end of the array
		var bracketCount = 1;
		var inString = false;
		var escapeNext = false;

		while (bracketCount > 0)
		{
			var c = readByte();
			if (c == -1) throw 'Unexpected EOF while skipping array';

			if (escapeNext)
			{
				escapeNext = false;
				continue;
			}

			if (c == '\\'.code)
			{
				escapeNext = true;
				continue;
			}

			if (c == '"'.code)
			{
				inString = !inString;
				continue;
			}

			if (!inString)
			{
				if (c == '['.code)
					bracketCount++;
				else if (c == ']'.code)
					bracketCount--;
				else if (c == '{'.code)
					bracketCount++;
				else if (c == '}'.code)
					bracketCount--;
			}

			if (filePos % (10 * 1024 * 1024) == 0 && log)
			{
				Sys.println('Skipping... $filePos bytes');
			}
		}
	}

	function parseString():String
	{
		var buf = new StringBuf();

		while (true)
		{
			var c = readByte();
			if (c == -1) throw 'Unexpected EOF in string';

			if (c == '\\'.code)
			{
				var next = readByte();
				switch (next)
				{
					case '"'.code: buf.addChar('"'.code);
					case '\\'.code: buf.addChar('\\'.code);
					case '/'.code: buf.addChar('/'.code);
					case 'b'.code: buf.addChar(8); // backspace
					case 'f'.code: buf.addChar(12); // form feed
					case 'n'.code: buf.addChar('\n'.code);
					case 'r'.code: buf.addChar('\r'.code);
					case 't'.code: buf.addChar('\t'.code);
					case 'u'.code:
						var hex = readHex(4);
						buf.addChar(hex);
					default:
						throw 'Invalid escape sequence at position $filePos';
				}
			}
			else if (c == '"'.code)
			{
				return buf.toString();
			}
			else
			{
				buf.addChar(c);
			}
		}
	}

	function readHex(len:Int):Int
	{
		var result = 0;
		for (i in 0...len)
		{
			var c = readByte();
			var digit = switch (c)
			{
				case '0'.code...'9'.code: c - '0'.code;
				case 'a'.code...'f'.code: c - 'a'.code + 10;
				case 'A'.code...'F'.code: c - 'A'.code + 10;
				default: throw 'Invalid hex digit at position $filePos';
			}
			result = (result << 4) | digit;
		}
		return result;
	}

	function parseNumber():Float
	{
		var buf = new StringBuf();
		var hasDecimal = false;
		var hasExponent = false;

		while (true)
		{
			var c = readByte();
			if (c == -1) break;

			switch (c)
			{
				case '0'.code...'9'.code:
					buf.addChar(c);
				case '-'.code:
					if (buf.length == 0) buf.addChar(c);
					else break;
				case '+'.code:
					if (hasExponent) buf.addChar(c);
					else break;
				case '.'.code:
					if (!hasDecimal && !hasExponent)
					{
						buf.addChar(c);
						hasDecimal = true;
					}
					else break;
				case 'e'.code, 'E'.code:
					if (!hasExponent)
					{
						buf.addChar(c);
						hasExponent = true;
					}
					else break;
				default:
					bufferPos--; // put back
					break;
			}
		}

		return Std.parseFloat(buf.toString());
	}

	function parseTrue():Bool
	{
		expect('r');
		expect('u');
		expect('e');
		return true;
	}

	function parseFalse():Bool
	{
		expect('a');
		expect('l');
		expect('s');
		expect('e');
		return false;
	}

	function parseNull():Dynamic
	{
		expect('u');
		expect('l');
		expect('l');
		return null;
	}

	function expect(expectedChar:String):Void
	{
		var c = readByte();
		if (c != expectedChar.charCodeAt(0))
		{
			throw 'Expected $expectedChar at position $filePos';
		}
	}
}