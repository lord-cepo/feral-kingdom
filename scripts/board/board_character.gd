## Character idle/selection, directional movement and action art used by HexCell and GuerraBoard's cosmetic overlays.
class_name BoardCharacter
extends Sprite2D

const PLAYGROUND_ROOT := "res://assets/characters/playground/"
const SHEET_ROOT := "res://assets/characters/sheets/"
const MAPPED_CARDS := ["squirrel-king", "pine-processionary", "thunder-toad", "walnut-crab", "reed-archer", "mole-artificer", "bramble-empress",
	"rat-dark-mage", "wild-rat", "rat-musketeer", "rat-thief", "rat-warrior", "rat-pikeman", "rat-swordsman",
	"red-squirrel-explorer", "red-squirrel-doctor", "wild-red-squirrel", "mole-miner", "wild-mole-rat",
	"mouse-sorcerer", "mouse-warrior", "wild-mouse", "wild-guinea-pig", "wild-beaver",
	"wild-marmot", "wild-jerboa", "wild-dormouse", "wild-chinchilla", "wild-lemming",
	"wild-porcupine", "wild-hedgehog", "wild-flying-squirrel", "wild-mara", "wild-tamia", "wild-grey-squirrel",
	"grey-squirrel-archer", "grey-squirrel-naturalist", "grey-squirrel-crossbowman", "grey-squirrel-pikeman",
	"grey-squirrel-warrior", "grey-squirrel-guardian", "grey-squirrel-musketeer", "grey-squirrel-wizard",
	"beaver-warrior", "beaver-guardian", "beaver-architect", "jerboa-banner-bearer", "jerboa-warrior",
	"jerboa-cannoneer", "jerboa-assassin", "jerboa-pyromancer", "jerboa-soldier", "jerboa-courier",
	"marmot-halberdier", "marmot-paladin", "chinchilla-soldier", "chinchilla-sentinel", "tamia-knight",
	"tamia-warrior", "tamia-archer", "tamia-crossbowman", "tamia-red-mage", "tamia-blue-mage",
	"porcupine-barbarian", "marmot-berserker", "dormouse-rogue", "flying-squirrel-ranger", "tamia-hunter",
	"jerboa-scout", "dormouse-witch", "rat-warlock", "red-squirrel-druid", "porcupine-shaman",
	"mouse-summoner", "chinchilla-alchemist", "guinea-pig-cleric", "marmot-monk", "lemming-healer",
	"tamia-bard", "jerboa-jester", "rat-pirate", "beaver-blacksmith", "guinea-pig-merchant",
	"grey-squirrel-king", "jerboa-king", "marmot-queen"]
const CHARACTER_SHADER := preload("res://assets/shaders/board_character.gdshader")
## Immutable presentation assets are retained once per appearance, shared by both owners, Bash figures and travelling overlays.
static var _art_cache: Dictionary = {}
static var _manifest: Dictionary = {}
const DIRECTIONS := ["south", "south-west", "west", "north-west", "north", "north-east", "east", "south-east"]
const DEPLOY_DURATION := 0.45
const WALK_START_DELAY := 0.2
const FACING_FADE_DURATION := 0.1
const TURN_POSE_DURATION := 0.12
const IDLE_OPACITY := 0.4
## Normal and Bash unit/info hover transitions share this duration.
const HOVER_FADE_DURATION := 0.18
## Sprite-local 16px becomes a 48-world-pixel drop through the existing 2x scale and 1.5x shader enlargement.
const DEPLOY_LIFT := 16.0
var unit_id := -1
var facing_frames: Array[Texture2D] = []
var idle_frame: Texture2D
var walk_frames: Array[Texture2D] = []
var walk_cycles: Dictionary = {}
var action_frames: Array[Texture2D] = []
var action_pose: Texture2D
var action_elapsed := -1.0
var stand_frames: Array[Texture2D] = []
var stand_elapsed := -1.0
var sit_elapsed := -1.0
var current_sector := 0
var turn_sectors: Array[int] = []
var turn_elapsed := 0.0
var turn_for_action := false
var deploy_elapsed := -1.0
var deploy_offset := 0.0
var inactive_blend := 0.0
var ground_level := 0.0
var foot_levels: Dictionary = {}
var hovered := false
var following_pointer := false
var walking := false
var elapsed := 0.0
var opacity_tween: Tween
var facing_tween: Tween
var facing_blend := 1.0
## HexCell supplies its actual picking polygon; travelling overlays have no home shape.
var home_shape: CollisionShape2D

## Runtime rosters and UI admit only mapped PixelLab characters with a generated sheet portrait; legacy card art is never a fallback.
static func supports(unit: UnitInfo) -> bool:
	var key := _appearance_key(unit)
	return not key.is_empty() and ResourceLoader.exists(SHEET_ROOT + key + ".portrait.tres")

## HexCell/controller use the mapped AtlasTexture portrait only; unsupported cards cannot load previous-game assets/cards images.
static func card_art_path(unit: UnitInfo) -> String:
	return portrait_path(unit)

## Resolves explicit card prefixes before their player suffix; Pine Processionary contains an internal '-p' that must not be split.
## supports(), portrait_path() and setup() share this mapping so both players and snapshot instances use the same appearance.
static func _appearance_key(unit: UnitInfo) -> String:
	if unit == null: return ""
	for key in MAPPED_CARDS:
		if unit.uuid == key or unit.uuid.begins_with(key + "-p"): return key
	return ""

## Hover/export callers receive a small AtlasTexture resource backed by the same character sheet; unsupported cards have no portrait path.
static func portrait_path(unit: UnitInfo) -> String:
	return SHEET_ROOT + _appearance_key(unit) + ".portrait.tres" if supports(unit) else ""

## Startup prepares one GPU texture per available PixelLab character; thousands of frame views are lightweight shared AtlasTextures.
## LocalMatchController calls once before accepting input; subsequent matches reuse the sheets and baked metadata.
static func preload_art() -> bool:
	for key in MAPPED_CARDS:
		if not ResourceLoader.exists(SHEET_ROOT + key + ".portrait.tres"): continue
		if _art_for(key).is_empty(): return false
	return true

## Reconstructs native-sized frame views from one lossless atlas and baked bounds/feet; both board and trays share this immutable pack.
## build_character_sheets.py supplies metadata. No individual PNG load, image decode or GPU readback occurs during pose changes.
static func _art_for(key: String) -> Dictionary:
	if _art_cache.has(key): return _art_cache[key]
	if _manifest.is_empty():
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(SHEET_ROOT + "manifest.json"))
		if not data is Dictionary or data.get("format_version", 0) != 1:
			push_error("Character sheet metadata is missing or invalid; run tools/build_character_sheets.py.")
			return {}
		_manifest = data.get("characters", {})
	if not _manifest.has(key):
		push_error("Missing character sheet for %s; rebuild character sheets." % key)
		return {}
	var definition: Dictionary = _manifest[key].definition
	var metadata: Dictionary = _manifest[key].frames
	var sheet := load(SHEET_ROOT + key + ".png") as Texture2D
	if sheet == null: return {}
	var feet: Dictionary = {}
	var bounds: Dictionary = {}
	var views: Dictionary = {}
	var facings: Array[Texture2D] = []
	var seated: Array[Texture2D] = []
	var cycles: Dictionary = {}
	var all_frames: Array[Texture2D] = []
	for direction in DIRECTIONS:
		facings.append(_cached_frame(sheet, "rotations/" + direction + ".png", metadata, feet, bounds, views))
		var sitting_key: String = "seated/" + direction + ".png"
		seated.append(_cached_frame(sheet, sitting_key if metadata.has(sitting_key) else "idle.png", metadata, feet, bounds, views))
		cycles[direction] = _cached_cycle(sheet, "walk/" + direction + "/", int(definition.walk_counts[direction]), metadata, feet, bounds, views)
		all_frames.append_array(cycles[direction])
	var idle := _cached_frame(sheet, "idle.png", metadata, feet, bounds, views)
	var stand := _cached_cycle(sheet, "stand/", int(definition.stand_count), metadata, feet, bounds, views)
	var action := _cached_cycle(sheet, "action/", int(definition.action_count), metadata, feet, bounds, views)
	all_frames.append_array(facings)
	all_frames.append_array(stand)
	all_frames.append_array(action)
	all_frames.append(idle)
	if all_frames.has(null) or stand.is_empty() or action.is_empty(): return {}
	var pack := {"sheet": sheet, "facings": facings, "seated": seated, "walk": cycles, "idle": idle, "stand": stand, "action": action, "feet": feet, "bounds": bounds, "views": views}
	_art_cache[key] = pack
	return pack

## Creates one native-sized view of the common sheet per logical frame, binding original alpha bounds/feet without image reads.
static func _cached_frame(sheet: Texture2D, relative: String, metadata: Dictionary, feet: Dictionary, bounds: Dictionary, views: Dictionary) -> Texture2D:
	if views.has(relative): return views[relative]
	if not metadata.has(relative):
		push_error("Missing character sheet frame: " + relative)
		return null
	var record: Dictionary = metadata[relative]
	var region: Array = record.region
	var frame := AtlasTexture.new()
	frame.atlas = sheet
	frame.region = Rect2(region[0], region[1], region[2], region[3])
	frame.filter_clip = true
	feet[frame.get_instance_id()] = float(record.foot)
	var box: Array = record.bounds
	bounds[frame.get_instance_id()] = Rect2(box[0], box[1], box[2], box[3])
	views[relative] = frame
	return frame

## Recreates authored numbered clip order from atlas metadata; playback remains independent of physical packing/deduplication.
static func _cached_cycle(sheet: Texture2D, folder: String, count: int, metadata: Dictionary, feet: Dictionary, bounds: Dictionary, views: Dictionary) -> Array[Texture2D]:
	var frames: Array[Texture2D] = []
	for index in count: frames.append(_cached_frame(sheet, folder + "frame_%03d.png" % index, metadata, feet, bounds, views))
	return frames

## Board/portrait shaders sample the sheet directly; this normalized rectangle recovers a frame's original local UV coordinates.
static func frame_uv_region(frame: Texture2D) -> Vector4:
	if frame is AtlasTexture:
		var size: Vector2 = frame.atlas.get_size()
		return Vector4(frame.region.position.x / size.x, frame.region.position.y / size.y, frame.region.size.x / size.x, frame.region.size.y / size.y)
	return Vector4(0, 0, 1, 1)

## Crossfade sampler uniforms need the underlying sheet RID, paired with frame_uv_region rather than a cropped sampler assumption.
static func frame_sheet(frame: Texture2D) -> Texture2D:
	return frame.atlas if frame is AtlasTexture else frame

## Binds each mapped card to preloaded idle, selected facings, walk and action arrays without loading or decoding textures again.
## HexCell calls before parenting a stationary figure; Board calls for a travelling overlay.
## Each figure owns its grayscale material; all frames are enlarged 1.5x with their bottom edge anchored.
## Transparent pixel edges and hover alpha are preserved.
## manifest.json supplies each appearance's eight directional walk counts and stand/action lengths.
## All six use seated/standing art and a foot-grounded nine-frame rise; Mole King takes Fireball from its alternate stand1 state.
## Idle inactive snapshots start grey; travelling overlays start colored and defer desaturation until their arrival/sit completes.
## Travelling overlays hold a directional standing pose for WALK_START_DELAY before their walk frames begin.
## Each figure's shader blends standing facings in one pass; animated clips retain direct frame playback.
## Mouse Engineer uses its seated rise, eight walking directions and nine-frame blueprint action through the same manifest contract.
## Stationary figures start at 40% opacity and hover restores full opacity through set_hover().
## Rat appearances share this manifest contract; unavailable direction/action/rise clips have one-frame stationary fallbacks instead of invented animation.
func setup(identifier: int, moving: bool = false) -> void:
	unit_id = identifier
	walking = moving
	if moving: elapsed = -WALK_START_DELAY
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var key := _appearance_key(Match.get_unit(identifier))
	var pack := _art_for(key)
	if pack.is_empty():
		hide()
		set_process(false)
		return
	facing_frames = pack.facings
	walk_cycles = pack.walk
	walk_frames = walk_cycles["south"]
	idle_frame = pack.idle
	stand_frames = pack.stand
	action_frames = pack.action
	foot_levels = pack.feet
	if key == "reed-archer": action_pose = action_frames.back()
	ground_level = _frame_foot_level(idle_frame)
	_show_frame(facing_frames[0] if moving else idle_frame)
	scale = Vector2.ONE * 2.0
	z_index = 3
	modulate.a = 1.0 if moving else IDLE_OPACITY
	set_meta("unit_id", identifier)
	set_meta("hover_eligible", false)
	var character_material := ShaderMaterial.new()
	character_material.shader = CHARACTER_SHADER
	material = character_material
	_show_frame(texture)
	inactive_blend = 0.0 if moving or Match.get_unit(identifier).active else 1.0
	character_material.set_shader_parameter("inactive_amount", inactive_blend)

## Reads a shared baked foot position in constant time; setup and animation playback never inspect image pixels or read GPU textures back.
## The existing per-pose and first-frame-per-clip alignment policy remains unchanged for static/rise versus walking/action animation.
func _frame_foot_level(frame: Texture2D) -> float:
	return float(foot_levels[frame.get_instance_id()])

## Displays a pose and translates its pixels vertically to the idle foot baseline before shader enlargement.
## Stand-up/static poses ground each frame separately; walking/actions use their own first frame as the foot anchor.
## Expanded PixelLab animation canvases therefore retain authored motion without jumping from the smaller rotation canvas.
## All animation callers use this; deployment adds a temporary vertical lift without moving the figure's board anchor.
## Sets the atlas frame rectangle/size for shader-local UVs; changing direct animation cancels a facing crossfade.
func _show_frame(frame: Texture2D, ground_frame: bool = true) -> void:
	if texture != frame and facing_blend < 1.0:
		if facing_tween != null: facing_tween.kill()
		_set_facing_blend(1.0)
	texture = frame
	if material != null:
		(material as ShaderMaterial).set_shader_parameter("current_region", frame_uv_region(frame))
		(material as ShaderMaterial).set_shader_parameter("current_size", frame.get_size())
	var foot_frame := frame if ground_frame else facing_frames[0]
	if not ground_frame:
		if walking and not walk_frames.is_empty(): foot_frame = walk_frames[0]
		elif not action_frames.is_empty(): foot_frame = action_frames[0]
	offset = Vector2(0, ground_level - _frame_foot_level(foot_frame) + deploy_offset)

## Pointer-facing and return-turn callers crossfade existing standing poses for 0.1s with their independent foot offsets aligned.
## Finish an ongoing blend before accepting the latest direction, avoiding abrupt retargets during fast pointer movement.
## Old/new frame regions share a sheet sampler but retain native canvas/foot alignment during the blend.
func _show_facing(sector: int) -> void:
	var next := facing_frames[sector]
	if texture == next: return
	if facing_blend < 1.0: return
	if not facing_frames.has(texture):
		_show_frame(next)
		return
	var previous := texture
	var previous_offset := offset
	_show_frame(next)
	var character_material := material as ShaderMaterial
	character_material.set_shader_parameter("previous_pose", frame_sheet(previous))
	character_material.set_shader_parameter("previous_region", frame_uv_region(previous))
	character_material.set_shader_parameter("previous_size", Vector2(previous.get_width(), previous.get_height()))
	character_material.set_shader_parameter("pose_offset_delta", offset - previous_offset)
	_set_facing_blend(0.0)
	facing_tween = create_tween()
	facing_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	facing_tween.tween_method(_set_facing_blend, 0.0, 1.0, FACING_FADE_DURATION)

## The facing tween updates the shader independently of hover opacity and greyscale; direct clips call with one to cancel a blend.
## One-pass alpha blending preserves the character's existing translucency instead of stacking two opaque silhouettes.
func _set_facing_blend(value: float) -> void:
	facing_blend = value
	if material != null: (material as ShaderMaterial).set_shader_parameter("facing_mix", value)

## Selects the nearest of eight screen-space facings; pointer tracking and walking share the same sector ordering.
func _direction_sector(direction: Vector2) -> int:
	return posmod(roundi((direction.angle() - PI / 2.0) / (TAU / 8.0)), 8)

## Selects a directional walking cycle per path segment; Board._advance_walk calls this before moving its overlay.
## All six mapped appearances have eight directional cycles; frame counts come from the manifest.
func set_walk_direction(direction: Vector2) -> void:
	if direction.is_zero_approx() or walk_cycles.is_empty(): return
	current_sector = _direction_sector(direction)
	walk_frames = walk_cycles[DIRECTIONS[current_sector]]

## HexCell starts a shortest-path turn to south, then the mapped action and reverse stand-up sit-down.
## Each appearance uses its supplied clip; Archer briefly holds its final draw pose before sitting.
## HexCell forwards Board's action notification after refresh; retained figures survive later state/selection updates.
## A committed action interrupts a cosmetic stand-up without delaying the command or its rule followups.
func play_action() -> void:
	if action_frames.is_empty() or walking: return
	_turn_to_south(true)

## HexCell receives the arriving overlay's last travel sector from Board._finish_walk().
## The retained stationary sprite takes over at the same foot anchor, turns south, then sits without delaying rules or info arrival.
func finish_walk(sector: int) -> void:
	current_sector = sector
	_turn_to_south(false)

## HexCell forwards a committed Deploy event after Board refresh creates the figure, never on snapshot repaint.
## The south standing pose drops from 48 world pixels above its normal anchor while fading in, then reverses stand-up to sit.
## Holds full color until sitting completes even if deployment already made the unit logically inactive.
## Cancels directional crossfades and uses the final stand-up frame so landing hands off to the identical first sit frame.
func play_deploy() -> void:
	if walking: return
	stand_elapsed = -1.0
	sit_elapsed = -1.0
	action_elapsed = -1.0
	turn_sectors.clear()
	current_sector = 0
	inactive_blend = 0.0
	(material as ShaderMaterial).set_shader_parameter("inactive_amount", inactive_blend)
	deploy_elapsed = 0.0
	deploy_offset = -DEPLOY_LIFT
	if facing_tween != null: facing_tween.kill()
	_set_facing_blend(1.0)
	if opacity_tween != null: opacity_tween.kill()
	modulate.a = 0.0
	_show_frame(stand_frames.back())

## Actions, walk arrivals and completed-rise deselection step through the shortest eight-facing arc to south before their next phase.
## Each directional pose lasts 0.12 seconds, including its 0.1-second crossfade; an exact north tie turns through west. Already-south actors proceed immediately.
## Full color is applied immediately, preventing a grey flash when a travelling overlay hands off to an inactive stationary figure.
func _turn_to_south(for_action: bool) -> void:
	inactive_blend = 0.0
	(material as ShaderMaterial).set_shader_parameter("inactive_amount", inactive_blend)
	if deploy_elapsed >= 0.0:
		deploy_elapsed = -1.0
		deploy_offset = 0.0
		modulate.a = 1.0
	stand_elapsed = -1.0
	sit_elapsed = -1.0
	action_elapsed = -1.0
	turn_sectors.clear()
	turn_elapsed = 0.0
	turn_for_action = for_action
	if current_sector == 0:
		if facing_blend < 1.0:
			turn_sectors.append(0)
			return
		_finish_turn()
		return
	turn_sectors.append(current_sector)
	var sector := current_sector
	var step := -1 if sector <= 4 else 1
	while sector != 0:
		sector = posmod(sector + step, DIRECTIONS.size())
		turn_sectors.append(sector)
	_show_facing(current_sector)

## _process() calls this when the return turn finishes, or _turn_to_south() calls directly when already south.
## Action sequences start their clip; completed walks start the reversed rise immediately.
func _finish_turn() -> void:
	turn_sectors.clear()
	current_sector = 0
	if turn_for_action:
		action_elapsed = 0.0
		_show_frame(action_frames[0], false)
	else: _start_sitting()

## A completed turn/action starts the full reversed rise; mid-rise deselection may supply its current frame to reverse without jumping.
## The reverse finishes on seated idle; selection changes may start a fresh stand-up after the sequence ends.
func _start_sitting(start_frame: int = -1) -> void:
	action_elapsed = -1.0
	stand_elapsed = -1.0
	var first := stand_frames.size() - 1 if start_frame < 0 else clampi(start_frame, 0, stand_frames.size() - 1)
	sit_elapsed = float(stand_frames.size() - 1 - first) / 10.0
	current_sector = 0
	_show_frame(stand_frames[first])

## Holds walking's first 0.2s on a directional standing pose, then advances its frames at 8fps; selection faces the pointer.
## Deployment drops/fades over 0.45s before sitting; return turns precede actions/sitting at 10fps, with Archer's final pose held for 0.25s.
## Godot calls this in board coordinates; the home hex's picking polygon keeps the south idle frame inside its boundary.
## Hover affects opacity only, and no Match state or input ownership changes.
## Logical inactivity blocks selection immediately, but the visible grey transition waits for all command phases, including sitting.
## After completion, saturation eases over 0.35s; reactivation smoothly restores color. Idle inactive units never track the pointer.
## Selection stand-up runs once at 10 fps before pointer facing, grounding every frame so leg extension lifts the head/body.
## Deployment reapplies its standing frame's grounded offset every tick, even when the texture is unchanged, then reverses that same clip.
func _process(delta: float) -> void:
	elapsed += delta
	var unit := Match.get_unit(unit_id)
	var character_material := material as ShaderMaterial
	var animating := _command_animating()
	var inactive := unit != null and not unit.active
	if inactive and not animating:
		following_pointer = false
		stand_elapsed = -1.0
		_show_frame(idle_frame)
	inactive_blend = move_toward(inactive_blend, 1.0 if inactive and not animating else 0.0, delta / 0.35)
	character_material.set_shader_parameter("inactive_amount", inactive_blend)
	if deploy_elapsed >= 0.0:
		deploy_elapsed += delta
		var progress := smoothstep(0.0, 1.0, minf(deploy_elapsed / DEPLOY_DURATION, 1.0))
		deploy_offset = -DEPLOY_LIFT * (1.0 - progress)
		modulate.a = progress
		_show_frame(stand_frames.back())
		if deploy_elapsed >= DEPLOY_DURATION:
			deploy_elapsed = -1.0
			deploy_offset = 0.0
			_start_sitting()
	elif walking:
		if elapsed < 0.0: _show_facing(current_sector)
		else: _show_frame(walk_frames[int(elapsed * 8.0) % walk_frames.size()], false)
	elif not turn_sectors.is_empty():
		turn_elapsed += delta
		var index := int(turn_elapsed / TURN_POSE_DURATION)
		if index >= turn_sectors.size(): _finish_turn()
		else:
			current_sector = turn_sectors[index]
			_show_facing(current_sector)

	elif action_elapsed >= 0.0:
		action_elapsed += delta
		var frame_index := int(action_elapsed * 10.0)
		if frame_index < action_frames.size(): _show_frame(action_frames[frame_index], false)
		elif action_pose != null and action_elapsed < action_frames.size() / 10.0 + 0.25: _show_frame(action_pose, false)
		else: _start_sitting()
	elif sit_elapsed >= 0.0:
		sit_elapsed += delta
		var index := stand_frames.size() - 1 - int(sit_elapsed * 10.0)
		if index >= 0: _show_frame(stand_frames[index])
		else:
			sit_elapsed = -1.0
			_show_frame(idle_frame)
			_fade_to_hover_opacity()
	elif stand_elapsed >= 0.0:
		stand_elapsed += delta
		var frame_index := int(stand_elapsed * 10.0)
		if frame_index < stand_frames.size(): _show_frame(stand_frames[frame_index])
		else:
			stand_elapsed = -1.0
			current_sector = 0
			_show_facing(0)
	elif following_pointer:
		if _pointer_inside_home_hex():
			current_sector = 0
			_show_facing(0)
			return
		var direction := get_global_mouse_position() - global_position
		if direction.length_squared() > 64.0:
			current_sector = _direction_sector(direction)
			_show_facing(current_sector)

## _process() defers greyscale while a committed deployment, walk, turn, action or sit-down is still visible.
## Selection-only stand-up is excluded so an externally inactivated idle unit cannot keep reacting to a stale selection.
func _command_animating() -> bool:
	return walking or deploy_elapsed >= 0.0 or action_elapsed >= 0.0 or sit_elapsed >= 0.0 or not turn_sectors.is_empty()

## GuerraBoard queries this before starting self-Stun sleeping feedback, after the complete action/turn/sit sequence.
## A selected standing pose or a travelling overlay is not seated; ordinary inactive idle art is seated.
func is_seated_for_feedback() -> bool:
	return not _command_animating() and stand_elapsed < 0.0 and not following_pointer and texture == idle_frame

## Checks the real collision polygon in its local coordinates, including camera and target-pose transforms.
## _process uses this rather than sprite bounds or hover state, so the whole hex is the idle zone even in Bash.
func _pointer_inside_home_hex() -> bool:
	if not is_instance_valid(home_shape): return false
	var polygon := home_shape.shape as ConvexPolygonShape2D
	return polygon != null and Geometry2D.is_point_in_polygon(home_shape.get_local_mouse_position(), polygon.points)

## Selection starts stand-up; deselection turns south and sits, or reverses a partially completed rise from its current frame.
## HexCell forwards selection idempotently during ordinary/Bash refreshes, never restarting an existing rise or delaying rules/input.
## Inactive units reject new selection poses even while the preceding command still displays in color.
## Deployment and committed turn/action/sit sequences already provide their own sit-down and survive selection refreshes.
## Reselecting during a cosmetic sit reverses smoothly from its current frame; a deselection-only turn can return to pointer facing.
func set_follow_pointer(value: bool) -> void:
	if value:
		var unit := Match.get_unit(unit_id)
		if unit == null or not unit.active: return
	if walking or following_pointer == value: return
	following_pointer = value
	if value and deploy_elapsed < 0.0 and action_elapsed < 0.0:
		if sit_elapsed >= 0.0:
			var index := clampi(stand_frames.size() - 1 - int(sit_elapsed * 10.0), 0, stand_frames.size() - 1)
			sit_elapsed = -1.0
			stand_elapsed = float(index) / 10.0
			_show_frame(stand_frames[index])
			return
		if not turn_sectors.is_empty() and not turn_for_action:
			turn_sectors.clear()
			_show_facing(current_sector)
			return
	if deploy_elapsed >= 0.0 or action_elapsed >= 0.0 or sit_elapsed >= 0.0 or not turn_sectors.is_empty(): return
	if value:
		stand_elapsed = 0.0
		_show_frame(stand_frames[0])
	elif stand_elapsed >= 0.0:
		_start_sitting(mini(int(stand_elapsed * 10.0), stand_frames.size() - 1))
	else: _turn_to_south(false)

## Records hover without interrupting deployment's fade; other phases fade opacity without replacing their pose.
## HexCell hover/refresh calls this idempotently; leaving a selected character does not stop pointer tracking.
func set_hover(value: bool) -> void:
	if walking or value == hovered: return
	hovered = value
	elapsed = 0.0
	if deploy_elapsed >= 0.0: return
	if not following_pointer and action_elapsed < 0.0 and sit_elapsed < 0.0 and turn_sectors.is_empty(): _show_frame(idle_frame)
	_fade_to_hover_opacity()

## set_hover() and completed sit-downs restore the latest hover opacity, including hover changes during deployment.
## Kills an older opacity tween so cosmetic fades never compete with a new deployment or each other.
## Unhovered figures settle at 40% opacity; hovered figures remain fully opaque.
## HexCell uses the same HOVER_FADE_DURATION for normal info and Bash-side info transitions.
func _fade_to_hover_opacity() -> void:
	if opacity_tween != null: opacity_tween.kill()
	opacity_tween = create_tween()
	opacity_tween.tween_property(self, "modulate:a", 1.0 if hovered else IDLE_OPACITY, HOVER_FADE_DURATION)
