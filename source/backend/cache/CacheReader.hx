package backend.cache;

import haxe.io.Bytes;
import backend.Native;
import backend.cache.CacheEntry.BlockInfo;

class CacheReader
{
	var fileHandle:Dynamic;
	var buf:Bytes = Bytes.alloc(1 << 16);

	public function new(path:String)
	{
		fileHandle = sys.io.File.read(path, false);
		if (fileHandle == null) throw 'Could not open "$path"';
	}

	public function readBlock(info:BlockInfo):Bytes
	{
		if (buf.length < info.comp) buf = Bytes.alloc(info.comp);
		fileHandle.readFull(buf, 0, info.comp);
		return NoteCodec.decompress(buf, info.comp, info.raw);
	}

	public function close():Void
	{
		if (fileHandle != null) {
			fileHandle.close();
			fileHandle = null;
		}
	}
}