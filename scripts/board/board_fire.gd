## Shared cosmetic Fire/Bow/Cannon marker owned by GuerraBoard; never delays or mutates match rules.
extends Node2D

const TARGET_OFFSET := Vector2(-84, -16)
## Live markers and replays share the flame's internal body alignment, separate from its target-hex slot.
const FIRE_ART_OFFSET := Vector2(0, -13)
## Normal attack markers and historical replays share these target-relative positions.
const TARGET_OFFSETS := {&"fire": TARGET_OFFSET, &"bow": Vector2(-84, -68), &"cannon": Vector2(-84, 36), &"bomb_throw": Vector2(84, -16), &"stun": Vector2(0, -110)}
const TRAVEL_SECONDS := 0.65
const FLAME_OPACITY := 0.8
## Toggle for the current visual comparison; false restores the single travelling arrow artwork.
const USE_PIXELLAB_BOW := true
var board: GuerraBoard
var origin_hex: int
var target_hex: int
var attack: RefCounted
var bow_visual := false
var action_kind: StringName = &"fire"
var target_offset := TARGET_OFFSET
var elapsed := 0.0
var aims_at_bomb := false
var retirement := -1.0
var flame := AnimatedSprite2D.new()

## GuerraBoard calls before add_child; captures endpoints for icon-only markers at 80% opacity; values/P stay in target hover counters.
## A queued attack retains its marker until resolved/removed; instant and bomb-igniting Fire hold briefly after arrival.
## Frame loading also supports newly downloaded PNGs before the editor's import scan has run.
## No board number is created; piercing details remain in hover counters.
## Bow reuses travel timing with PixelLab's seven-frame bow loop, rotated toward its captured target.
## USE_PIXELLAB_BOW retains the earlier single-arrow presentation as a comparison option.
## Fire and Bow loops play at 5.5fps (half speed); travel retains its timing.
## Target placement and Fire body alignment are shared with action_replay.gd through TARGET_OFFSETS/FIRE_ART_OFFSET.
## Cannon uses its nine-frame clip and pending Cannon record, excluding Bomb explosions from Cannon markers.
## Fire captures an inert bomb at declaration and aims at its right-side marker rather than the ordinary left-side slot.
func setup(presenter: GuerraBoard, origin: int, target: int, _amount: int, _owner: int,
		queued_attack: RefCounted = null, stationary: bool = false, _piercing: bool = false,
		is_bow: bool = false, kind: StringName = &"") -> void:
	board = presenter
	origin_hex = origin
	target_hex = target
	attack = queued_attack
	bow_visual = is_bow
	action_kind = kind if kind != &"" else (&"bow" if bow_visual else &"fire")
	target_offset = TARGET_OFFSETS.get(action_kind, TARGET_OFFSET)
	aims_at_bomb = action_kind == &"fire" and Match.bomb_at(target_hex) != null
	if aims_at_bomb: target_offset = TARGET_OFFSETS[&"bomb_throw"]
	elapsed = TRAVEL_SECONDS if stationary else 0.0
	position = board.axial_to_screen(Match.get_hex(target_hex if stationary else origin_hex).coordinate)
	if stationary: position += target_offset
	z_index = 7
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var frames := SpriteFrames.new()
	frames.set_animation_loop(&"default", true)
	frames.set_animation_speed(&"default", 5.5)
	if bow_visual and not USE_PIXELLAB_BOW:
		frames.add_frame(&"default", preload("res://assets/arrow.png"))
	else:
		var frame_count := 9 if action_kind == &"cannon" else (7 if bow_visual else 11)
		for index in frame_count:
			var texture := _load_frame(index)
			if texture != null: frames.add_frame(&"default", texture)
	flame.sprite_frames = frames
	flame.scale = Vector2.ONE * 2.625
	flame.position = FIRE_ART_OFFSET
	if aims_at_bomb: flame.position = Vector2.ZERO
	if bow_visual:
		flame.scale = Vector2.ONE * (2.625 if USE_PIXELLAB_BOW else 84.0 / 256.0)
		flame.position = Vector2.ZERO
	elif action_kind == &"cannon": flame.position = Vector2.ZERO
	add_child(flame)
	flame.play()
	flame.modulate.a = FLAME_OPACITY if stationary else 0.0

## setup() uses imported textures in exported games and raw PNGs in a working project awaiting import.
## Returns no frame and reports the exact path on failure instead of silently adding an invisible texture.
## Chooses the Bow, Fire or Cannon folder from this marker's captured presentation kind.
func _load_frame(index: int) -> Texture2D:
	var path := "res://assets/effects/%s/frame_%d.png" % [action_kind, index]
	if ResourceLoader.exists(path, "Texture2D"):
		var imported := load(path) as Texture2D
		if imported != null: return imported
	var image := Image.load_from_file(path)
	if image == null or image.is_empty():
		push_error("Cannot load attack animation frame: %s" % path)
		return null
	return ImageTexture.create_from_image(image)

## Godot advances travel and fades independently of the rules runner; board mapping keeps resize alignment live.
## Opacity stays below its 80% ceiling inside the origin's convex hex, reaching that ceiling only after crossing its boundary.
## Icon-only resolved markers hold 0.6s then fade over 0.25s, including instant Fire/Bow.
func _process(delta: float) -> void:
	var origin := Match.get_hex(origin_hex)
	var target := Match.get_hex(target_hex)
	if origin == null or target == null:
		queue_free()
		return
	elapsed += delta
	var start := board.axial_to_screen(origin.coordinate)
	var finish := board.axial_to_screen(target.coordinate) + target_offset
	if bow_visual: flame.rotation = (finish - start).angle()
	var progress := clampf(elapsed / TRAVEL_SECONDS, 0.0, 1.0)
	position = start.lerp(finish, smoothstep(0.0, 1.0, progress))
	var offset := position - start
	# Same flat-top convex shape as HexCell's CollisionShape2D.
	var outside := absf(offset.y) > 86.66667 or absf(offset.x) + 0.75 * absf(offset.y) > 130.0
	flame.modulate.a = FLAME_OPACITY * minf(progress * 1.8, 1.0 if outside else 0.95)
	if progress < 1.0: return
	var pending: Array = Match.pending_bow_attacks if bow_visual else Match.pending_attacks
	if action_kind == &"cannon": pending = Match.pending_cannon_attacks
	if attack != null and not bool(attack.get("resolved")) and pending.has(attack): return
	if retirement < 0.0: retirement = elapsed + 0.6
	modulate.a = 1.0 - clampf((elapsed - retirement) / 0.25, 0.0, 1.0)
	if modulate.a <= 0.0: queue_free()
