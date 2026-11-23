package backend;

import haxe.ds.Vector;
import haxe.Json;
import backend.SongJson;
import backend.cache.BinCache;
import backend.cache.CacheEntry;
import backend.chart.NoteBuilder;
import backend.play.NoteStore;
import lime.utils.Assets;

import objects.Note;

typedef SwagSong =
{
	var song:String;
	var notes:Array<SwagSection>;
	var events:Array<Dynamic>;
	var bpm:Float;
	var needsVoices:Bool;
	var speed:Float;
	var offset:Float;

	var player1:String;
	var player2:String;
	var gfVersion:String;
	var stage:String;
	var format:String;

	@:optional var isOldVersion:Bool;

	@:optional var gameOverChar:String;
	@:optional var gameOverSound:String;
	@:optional var gameOverLoop:String;
	@:optional var gameOverEnd:String;

	@:optional var disableNoteRGB:Bool;
	@:optional var screwYou:String;

	@:optional var arrowSkin:String;
	@:optional var splashSkin:String;
}

typedef SwagSection =
{
	var sectionNotes:Array<Dynamic>;
	var sectionBeats:Float;
	var mustHitSection:Bool;
	@:optional var altAnim:Bool;
	@:optional var gfSection:Bool;
	@:optional var bpm:Float;
	@:optional var changeBPM:Bool;
}

class Song
{
	public var song:String;
	public var notes:Array<SwagSection>;
	public var events:Array<Dynamic>;
	public var bpm:Float;
	public var needsVoices:Bool = true;
	public var arrowSkin:String;
	public var splashSkin:String;
	public var gameOverChar:String;
	public var gameOverSound:String;
	public var gameOverLoop:String;
	public var gameOverEnd:String;
	public var disableNoteRGB:Bool = false;
	public var speed:Float = 1;
	public var stage:String;
	public var player1:String = 'bf';
	public var player2:String = 'dad';
	public var gfVersion:String = 'gf';
	public var format:String = 'psych_v1';

	public static function convert(songJson:Dynamic) // Convert old charts to psych_v1 format
	{
		if(songJson.gfVersion == null)
		{
			songJson.gfVersion = songJson.player3;
			if(Reflect.hasField(songJson, 'player3')) Reflect.deleteField(songJson, 'player3');
		}

		if(songJson.events == null)
		{
			songJson.events = [];
			for (secNum in 0...songJson.notes.length)
			{
				var sec:SwagSection = songJson.notes[secNum];

				var i:Int = 0;
				var notes:Array<Dynamic> = sec.sectionNotes;
				var len:Int = notes.length;
				while(i < len)
				{
					var note:Array<Dynamic> = notes[i];
					if(note[1] < 0)
					{
						songJson.events.push([note[0], [[note[2], note[3], note[4]]]]);
						notes.remove(note);
						len = notes.length;
					}
					else i++;
				}
			}
		}

		var sectionsData:Array<SwagSection> = songJson.notes;
		if(sectionsData == null) return;

		for (section in sectionsData)
		{
			var beats:Null<Float> = cast section.sectionBeats;
			if (beats == null || Math.isNaN(beats))
			{
				section.sectionBeats = 4;
				if(Reflect.hasField(section, 'lengthInSteps')) Reflect.deleteField(section, 'lengthInSteps');
			}

			for (note in section.sectionNotes)
			{
				var gottaHitNote:Bool = (note[1] < 4) ? section.mustHitSection : !section.mustHitSection;
				note[1] = (note[1] % 4) + (gottaHitNote ? 0 : 4);

				if(note[3] != null && !Std.isOfType(note[3], String))
					note[3] = Note.defaultNoteTypes[note[3]]; //compatibility with Week 7 and 0.1-0.3 psych charts
			}
		}
	}

	public static var chartPath:String;
	public static var loadedSongName:String;
	public static var noteStore:NoteStore = null;

	public static function loadFromJson(jsonInput:String, forPlay:Bool, ?folder:String):SwagSong
	{
		SongJson.skipChart = forPlay;
		if(folder == null) folder = jsonInput;
		PlayState.SONG = getChart(jsonInput, folder, forPlay);
		loadedSongName = folder;
		chartPath = _lastPath.replace('/', '\\');
		StageData.loadDirectory(PlayState.SONG);
		return PlayState.SONG;
	}

	static var _lastPath:String;
	public static function getChart(jsonInput:String, ?folder:String, ?forPlay:Bool = false):SwagSong
	{
		if(folder == null) folder = jsonInput;
		var rawData:String = null;

		var formattedFolder:String = Paths.formatToSongPath(folder);
		var formattedSong:String = Paths.formatToSongPath(jsonInput);
		_lastPath = Paths.json('$formattedFolder/$formattedSong');

		// Try binary cache first for play mode
		if (forPlay)
		{
			try {
				final cache:BinCache = new BinCache(BinCache.getCachePath());
				final fileStamp:String = _getFileStamp(_lastPath);
				final cacheKey:String = '$formattedFolder/$formattedSong';
				final entry:CacheEntry = cache.find(cacheKey, fileStamp);

				if (entry != null)
				{
					// Use binary cache - create NoteStore for streaming
					noteStore = new NoteStore(cache, entry, 10); // 10ms merge window
					// Return minimal song data for compatibility
					final song:SwagSong = {
						song: formattedSong,
						notes: [],
						events: [],
						bpm: entry.meta != null ? entry.meta.bpm : 100,
						needsVoices: true,
						speed: entry.meta != null ? entry.meta.speed : 1,
						offset: 0,
						player1: 'bf',
						player2: 'dad',
						gfVersion: 'gf',
						stage: 'stage',
						format: 'psych_v1'
					};
					return song;
				}
			} catch (e:Dynamic) {
				trace('Cache load failed: $e');
			}
		}

		#if MODS_ALLOWED
		if(FileSystem.exists(_lastPath))
		{
			// For large files in play mode, use streaming parser
			if (SongJson.skipChart)
			{
				var fileSize = FileSystem.stat(_lastPath).size;
				if (fileSize > 100 * 1024 * 1024) // 100MB threshold
				{
					SongJsonStream.skipChart = true;
					var songJson:SwagSong = cast SongJsonStream.parse(_lastPath);
					return songJson;
				}
			}
			rawData = File.getContent(_lastPath);
		}
		else
		#end
			rawData = Assets.getText(_lastPath);

		final song:SwagSong = rawData != null ? parseJSON(rawData, jsonInput) : null;

		// Build cache if in play mode and we have a valid song
		if (forPlay && song != null)
		{
			try {
				buildCache(song, formattedFolder, formattedSong, _lastPath);
			} catch (e:Dynamic) {
				trace('Cache build failed: $e');
			}
		}

		return song;
	}

	static function _getFileStamp(path:String):String
	{
		#if MODS_ALLOWED
		if (FileSystem.exists(path))
		{
			final stat = FileSystem.stat(path);
			return Std.string(stat.size) + '@' + Std.string(stat.mtime.getTime());
		}
		#end
		return 'unknown';
	}

	static function buildCache(song:SwagSong, folder:String, name:String, path:String):Void
	{
		final cache:BinCache = new BinCache(BinCache.getCachePath());
		final fileStamp:String = _getFileStamp(path);
		final cacheKey:String = '$folder/$name';

		// Build NoteBuilder from song
		final builder:NoteBuilder = new NoteBuilder(4); // Default 4 keys
		for (section in song.notes)
		{
			final mustHit:Bool = section.mustHitSection;
			for (note in section.sectionNotes)
			{
				final time:Float = note[0];
				final lane:Float = note[1];
				final length:Float = note[2];
				final laneIndex:Int = Std.int(lane);
				final right:Bool = laneIndex >= 4;
				final finalLane:Int = builder.laneOf(laneIndex % 4, right);
				builder.add(time, finalLane, length);
			}
		}
		builder.finish();

		// Build metadata
		final meta:ChartMeta = new ChartMeta();
		meta.song = song.song;
		meta.bpm = song.bpm;
		meta.speed = song.speed;
		meta.keys = 4;
		meta.format = song.format;
		meta.measure(builder);

		// Store in cache
		cache.store(cacheKey, fileStamp, meta, builder, 4); // 4 threads
	}

	public static function parseJSON(rawData:String, ?nameForError:String = null, ?convertTo:String = 'psych_v1'):SwagSong
	{
		var isOldVer:Vector<Bool> = new Vector(2);
		var songJson:SwagSong = cast SongJson.parse(rawData);

		if(Reflect.hasField(songJson, 'song'))
		{
			isOldVer[0] = true;
			var subSong:SwagSong = Reflect.field(songJson, 'song');
			if(subSong != null && Type.typeof(subSong) == TObject)
				songJson = subSong;
		} else isOldVer[0] = false;

		if(convertTo != null && convertTo.length > 0)
		{
			var fmt:String = songJson.format;
			if(fmt == null)
			{
				fmt = songJson.format = 'unknown';
				isOldVer[1] = true;
				if (isOldVer[0] && isOldVer[1]) songJson.isOldVersion = true;
			}

			switch(convertTo)
			{
				case 'psych_v1':
					if(!fmt.startsWith('psych_v1')) //Convert to Psych 1.0 format
					{
						#if debug trace('converting chart $nameForError with format $fmt to psych_v1 format...'); #end
						songJson.format = 'psych_v1_convert';
						convert(songJson);
					}
			}
		}
		return songJson;
	}
}