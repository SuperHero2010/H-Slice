package backend;

import haxe.Timer;
import haxe.ds.Vector;
import sys.io.FileInput;
import backend.chart.NoteBuilder;

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
	var fileSize:Int = 0;
	var time:Float = Timer.stamp();
	public static var skipChart:Bool = false;
	public static var log:Bool = true;
	var lastKey:String = null;
	var onProgress:Float->Void = null;
	var noteBuilder:NoteBuilder = null;
	var sectionMustHit:Bool = false;
	var sectionBpm:Float = 100;
	var sectionChangeBpm:Bool = false;
	var sectionAltAnim:Bool = false;

	static inline var CHUNK_SIZE = 4 * 1024 * 1024; // 4MB chunks (matches Strand)

	function new(filePath:String, ?onProgress:Float->Void)
	{
		this.file = sys.io.File.read(filePath, false);
		this.buffer = haxe.io.Bytes.alloc(CHUNK_SIZE);
		this.bufferPos = 0;
		this.bufferSize = 0;
		this.filePos = 0;
		this.onProgress = onProgress;
		#if sys
		this.fileSize = Sys.getFileSize(filePath);
		#end
	}

	static public inline function parse(filePath:String, ?onProgress:Float->Void):Dynamic
	{
		var parser = new SongJsonStream(filePath, onProgress);
		var result = parser.doParse();
		parser.file.close();
		return result;
	}

	public function parseWithBuilder(builder:NoteBuilder):Dynamic
	{
		this.noteBuilder = builder;
		var result = doParse();
		this.noteBuilder = null;
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
		if (onProgress != null && fileSize > 0) {
			onProgress(filePos / fileSize);
		}
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

				// Handle section properties for note building
				if (noteBuilder != null) {
					switch (key) {
						case 'mustHitSection':
							sectionMustHit = parseBool();
							continue;
						case 'bpm':
							sectionBpm = parseFloat();
							continue;
						case 'changeBPM':
							sectionChangeBpm = parseBool();
							continue;
						case 'altAnim':
							sectionAltAnim = parseBool();
							continue;
						case 'sectionNotes':
							// Stream notes directly into NoteBuilder
							if (noteBuilder != null) {
								streamSectionNotes();
								continue;
							}
					}
				}

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

	function parseBool():Bool
	{
		var c = readByte();
		if (c == 't'.code) {
			expect('r');
			expect('u');
			expect('e');
			return true;
		} else if (c == 'f'.code) {
			expect('a');
			expect('l');
			expect('s');
			expect('e');
			return false;
		}
		throw 'Expected boolean at position $filePos';
	}

	function parseFloat():Float
	{
		bufferPos--; // put back the byte we peeked
		return parseNumber();
	}

	function streamSectionNotes():Void
	{
		expect('['.code);
		skipWhitespace();

		while (true)
		{
			var c = readByte();
			if (c == -1) throw 'Unexpected EOF in sectionNotes';

			if (c == ']'.code)
			{
				return;
			}

			if (c == '['.code)
			{
				streamNote();
			}
			else
			{
				// Skip non-array values
				bufferPos--;
				parseRec();
			}

			skipWhitespace();
			var next = readByte();
			if (next == ','.code)
			{
				skipWhitespace();
				continue;
			}
			else if (next == ']'.code)
			{
				return;
			}
			else
			{
				throw 'Expected comma or ] in sectionNotes';
			}
		}
	}

	function streamNote():Void
	{
		// Note format: [time, lane, length, type]
		var time:Float = 0;
		var lane:Float = 0;
		var length:Float = 0;
		var type:String = null;

		skipWhitespace();
		var c = readByte();

		if (c == ']'.code)
		{
			// Empty note array
			return;
		}

		bufferPos--; // put back

		// Parse time
		time = parseNumber();
		skipWhitespace();
		expect(',');
		skipWhitespace();

		// Parse lane
		lane = parseNumber();
		skipWhitespace();
		expect(',');
		skipWhitespace();

		// Parse length
		length = parseNumber();
		skipWhitespace();

		// Check for type (optional)
		c = readByte();
		if (c == ','.code)
		{
			skipWhitespace();
			type = parseString();
		}
		else
		{
			bufferPos--;
		}

		skipWhitespace();
		expect(']'.code);

		// Add to NoteBuilder
		if (noteBuilder != null && !Math.isNaN(time) && lane >= 0) {
			var laneIndex:Int = Std.int(lane);
			var right:Bool = sectionMustHit;
			var finalLane:Int = noteBuilder.laneOf(laneIndex, right);
			noteBuilder.add(time, finalLane, length);
		}
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
				case 48, 49, 50, 51, 52, 53, 54, 55, 56, 57: c - 48; // '0'-'9'
				case 97, 98, 99, 100, 101, 102: c - 97 + 10; // 'a'-'f'
				case 65, 66, 67, 68, 69, 70: c - 65 + 10; // 'A'-'F'
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
				case 48, 49, 50, 51, 52, 53, 54, 55, 56, 57: // '0'-'9'
					buf.addChar(c);
				case 45: // '-'
					if (buf.length == 0) buf.addChar(c);
					else break;
				case 43: // '+'
					if (hasExponent) buf.addChar(c);
					else break;
				case 46: // '.'
					if (!hasDecimal && !hasExponent)
					{
						buf.addChar(c);
						hasDecimal = true;
					}
					else break;
				case 101, 69: // 'e', 'E'
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