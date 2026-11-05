## Explicitly launched regression scene for shared sprite preload and baked alignment; never runs during editor import.
extends Node

var failures := 0

## Records an asset/cache contract failure for the scene's final exit status.
func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

## Verifies all character AtlasTexture views share one sheet, retain source dimensions/pixels/bounds/feet, and reuse cached resources.
## Source PNG reads are confined to this explicitly launched regression; ignored source folders never become runtime imports.
func _ready() -> void:
	check(BoardCharacter.preload_art(), "All mapped character packs preload")
	for key in BoardCharacter.MAPPED_CARDS:
		var pack := BoardCharacter._art_for(key)
		check(not pack.is_empty(), "Mapped pack exists: " + key)
		if pack.is_empty(): continue
		var repeated := BoardCharacter._art_for(key)
		check(pack.idle == repeated.idle, "Repeated preload retains the same texture: " + key)
		var sheet_image := Image.load_from_file(BoardCharacter.SHEET_ROOT + key + ".png")
		var records: Dictionary = BoardCharacter._manifest[key].frames
		for relative in pack.views:
			var frame: AtlasTexture = pack.views[relative]
			check(frame.atlas == pack.sheet and frame.filter_clip, "Frame shares its character sheet with clipped sampling")
			var record: Dictionary = records[relative]
			check(frame.get_size() == Vector2(record.region[2], record.region[3]), "Native canvas dimensions survive atlas packing")
			var source := Image.load_from_file(BoardCharacter.PLAYGROUND_ROOT + key + "/" + relative)
			source.convert(Image.FORMAT_RGBA8)
			var crop := sheet_image.get_region(Rect2i(frame.region))
			crop.convert(Image.FORMAT_RGBA8)
			check(source.get_data() == crop.get_data(), "Packed region is pixel-identical to source: " + key + "/" + relative)
			check(pack.bounds[frame.get_instance_id()] == Rect2(source.get_used_rect()), "Baked alpha bounds match source")
		var frames: Array[Texture2D] = []
		frames.append(pack.idle)
		frames.append_array(pack.facings)
		frames.append_array(pack.seated)
		frames.append_array(pack.stand)
		frames.append_array(pack.action)
		for direction in BoardCharacter.DIRECTIONS: frames.append_array(pack.walk[direction])
		for frame in frames:
			var bounds: Rect2 = pack.bounds[frame.get_instance_id()]
			var expected := bounds.end.y - frame.get_height() * 0.5
			check(pack.feet.has(frame.get_instance_id()), "Each retained frame has baked alignment")
			check(is_equal_approx(float(pack.feet.get(frame.get_instance_id(), INF)), expected), "Baked alignment matches source alpha bounds: " + frame.resource_path)
	check(BoardCharacter._appearance_key(null).is_empty(), "Unmapped/null units have no character appearance")
	var legacy := UnitInfo.new()
	legacy.uuid = "portrait-only-legacy-p1"
	legacy.name = "Legacy card"
	check(not BoardCharacter.supports(legacy) and BoardCharacter.card_art_path(legacy).is_empty(), "Legacy cards cannot load old portrait fallbacks")
	get_tree().quit(1 if failures else 0)
