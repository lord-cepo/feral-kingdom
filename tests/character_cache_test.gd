## Explicitly launched regression scene for shared sprite preload and baked alignment; never runs during editor import.
extends Node

const SOURCE_ROOT := "res://assets/characters/playground/"
var checks := 0
var failures := 0
var source_frames_compared := 0

## Records an asset/cache contract failure for the scene's final exit status.
func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

## The opt-in scene verifies shipped sheets and the runtime cache, then reports how many source frames were available.
func _ready() -> void:
	check(BoardCharacter.preload_art(), "All mapped character packs preload")
	for key in BoardCharacter.MAPPED_CARDS:
		_check_pack(key)
	check(BoardCharacter._appearance_key(null).is_empty(), "Unmapped/null units have no character appearance")
	var legacy := UnitInfo.new()
	legacy.uuid = "portrait-only-legacy-p1"
	legacy.name = "Legacy card"
	check(not BoardCharacter.supports(legacy) and BoardCharacter.card_art_path(legacy).is_empty(), "Legacy cards cannot load old portrait fallbacks")
	print("Character cache: %d checks, %d failures (%d original PNGs compared)" % [checks, failures, source_frames_compared])
	get_tree().quit(1 if failures else 0)

## Checks that repeated runtime access reuses the sheet and that the shipped portrait uses its south-facing view.
## Validates all packed manifest frames, including entries that the current animation set does not use.
func _check_pack(key: String) -> void:
	var pack := BoardCharacter._art_for(key)
	check(not pack.is_empty(), "Mapped pack exists: " + key)
	if pack.is_empty(): return
	var repeated := BoardCharacter._art_for(key)
	check(pack.sheet == repeated.sheet and pack.idle == repeated.idle, "Repeated access reuses the sheet and frame: " + key)
	var portrait := load(BoardCharacter.SHEET_ROOT + key + ".portrait.tres") as AtlasTexture
	var south: AtlasTexture = pack.views["rotations/south.png"]
	check(portrait != null and portrait.atlas == pack.sheet and portrait.region == south.region and portrait.filter_clip,
		"Portrait shares the clipped south-facing region: " + key)
	var sheet := Image.load_from_file(BoardCharacter.SHEET_ROOT + key + ".png")
	check(sheet != null and not sheet.is_empty(), "Shipped sheet decodes: " + key)
	if sheet == null or sheet.is_empty(): return
	var manifest: Dictionary = BoardCharacter._manifest[key]
	check(sheet.get_size() == Vector2i(manifest.sheet_size[0], manifest.sheet_size[1]), "Sheet dimensions match the manifest: " + key)
	sheet.convert(Image.FORMAT_RGBA8)
	var source_folder := SOURCE_ROOT + key + "/"
	var has_source_folder := DirAccess.dir_exists_absolute(source_folder)
	for relative: String in manifest.frames:
		var source_path := source_folder + relative if has_source_folder else ""
		_check_frame(key + "/" + relative, manifest.frames[relative], sheet, pack, pack.views.get(relative), source_path)

## Compares manifest and runtime alignment with alpha bounds measured from the shipped crop.
## Original PNGs are optional. Present originals must decode and match the crop's pixels and canvas size.
func _check_frame(label: String, record: Dictionary, sheet: Image, pack: Dictionary, frame: AtlasTexture, source_path: String) -> void:
	var region := Rect2i(record.region[0], record.region[1], record.region[2], record.region[3])
	var inside := region.has_area() and Rect2i(Vector2i.ZERO, sheet.get_size()).encloses(region)
	check(inside, "Frame region fits within the shipped sheet: " + label)
	if not inside: return
	var crop := sheet.get_region(region)
	var bounds := crop.get_used_rect()
	var expected_foot := bounds.end.y - region.size.y * 0.5
	var manifest_bounds := Rect2i(record.bounds[0], record.bounds[1], record.bounds[2], record.bounds[3])
	check(manifest_bounds == bounds, "Manifest alpha bounds match the shipped frame: " + label)
	check(is_equal_approx(float(record.foot), expected_foot), "Manifest foot matches the shipped frame: " + label)
	if frame != null:
		var id := frame.get_instance_id()
		check(frame.atlas == pack.sheet and frame.filter_clip and frame.region == Rect2(region)
			and frame.get_size() == Vector2(region.size), "Cached view shares the clipped region at its native size: " + label)
		check(pack.bounds.get(id) == Rect2(bounds) and is_equal_approx(float(pack.feet.get(id, INF)), expected_foot),
			"Cached view keeps the shipped frame's bounds and foot: " + label)
	if source_path.is_empty() or not FileAccess.file_exists(source_path): return
	var source := Image.load_from_file(source_path)
	check(source != null and not source.is_empty(), "Original PNG decodes: " + label)
	if source == null or source.is_empty(): return
	source.convert(Image.FORMAT_RGBA8)
	source_frames_compared += 1
	check(source.get_size() == crop.get_size() and source.get_data() == crop.get_data(),
		"Shipped frame matches original pixels and canvas size: " + label)
