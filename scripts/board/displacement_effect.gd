## Shared finite Push/Pull icon-and-wind presentation for live actions and historical replays; never shifts a unit.
extends Node2D

const PASS_DURATION := 1.2
const WIND_PASSES := 2
const WIND_SCALE := 2.7
const DURATION := PASS_DURATION * WIND_PASSES
static var clips: Dictionary = {}
var board: GuerraBoard
var source_hex: int
var previous_hex: int
var target_hex: int
var source_id: int
var target_id: int
var elapsed := 0.0
var moving_target: WeakRef
var action_icon := AnimatedSprite2D.new()
var wind := AnimatedSprite2D.new()

## Live displacement and replay callers supply captured actor/old-target/new-target hexes plus optional figure identities.
## Actor icons play once; wind plays twice, following an optional live sliding copy until hidden, then anchoring at the landing.
func setup(owner_board: GuerraBoard, actor_hex: int, old_hex: int, final_hex: int,
		pulling: bool, actor_id: int = -1, recipient_id: int = -1, sliding_figure: Node2D = null) -> void:
	board = owner_board
	source_hex = actor_hex
	previous_hex = old_hex
	target_hex = final_hex
	source_id = actor_id
	target_id = recipient_id
	if sliding_figure != null: moving_target = weakref(sliding_figure)
	z_index = 8
	for sprite in [action_icon, wind]:
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		add_child(sprite)
	action_icon.sprite_frames = _clip("pull-icons" if pulling else "push-icons", 1)
	action_icon.scale = Vector2.ONE * 2.625
	wind.sprite_frames = _clip("push-pull", WIND_PASSES)
	wind.scale = Vector2.ONE * WIND_SCALE
	wind.flip_h = pulling
	action_icon.play()
	wind.play()
	action_icon.modulate.a = 0.0
	wind.modulate.a = 0.0

## setup() shares imported/raw textures and complete finite frame sequences across live/replay instances.
## Repeated wind frames repeat only the visual clip, never the command or the target translation.
func _clip(folder: String, passes: int) -> SpriteFrames:
	var key := "%s:%d" % [folder, passes]
	if clips.has(key): return clips[key]
	var frames := SpriteFrames.new()
	frames.set_animation_loop(&"default", false)
	frames.set_animation_speed(&"default", 9.0 / PASS_DURATION)
	for index in 9:
		var path := "res://assets/effects/%s/frame_%d.png" % [folder, index]
		var texture: Texture2D
		if ResourceLoader.exists(path, "Texture2D"): texture = load(path) as Texture2D
		if texture == null:
			var image := Image.load_from_file(path)
			if image != null and not image.is_empty(): texture = ImageTexture.create_from_image(image)
		if texture != null: frames.add_frame(&"default", texture)
		else: push_error("Cannot load displacement effect: %s" % path)
	var count := frames.get_frame_count(&"default")
	for pass_index in range(1, passes):
		for index in count: frames.add_frame(&"default", frames.get_frame_texture(&"default", index))
	clips[key] = frames
	return frames

## Godot follows the live copy while visible; replays retain captured hexes/figure sides. Each clip fades and the pair ends at 2.4s.
## Orientation comes from actor to previous target; Pull's separate actor icon already has the correct pull motion.
func _process(delta: float) -> void:
	elapsed += delta
	var source := Match.get_hex(source_hex)
	var previous := Match.get_hex(previous_hex)
	if source == null or previous == null or Match.get_hex(target_hex) == null:
		queue_free()
		return
	var direction := (board.axial_to_screen(previous.coordinate) - board.axial_to_screen(source.coordinate)).normalized()
	action_icon.position = _anchor(source_hex, source_id)
	wind.position = _anchor(target_hex, target_id)
	var sliding := moving_target.get_ref() as Node2D if moving_target != null else null
	if is_instance_valid(sliding) and sliding.visible:
		wind.position = board.to_local(sliding.global_position) + Vector2(0, -65)
	action_icon.rotation = direction.angle()
	wind.rotation = direction.angle()
	action_icon.modulate.a = 0.8 * smoothstep(0.0, 0.15, elapsed) * (1.0 - smoothstep(PASS_DURATION - 0.25, PASS_DURATION, elapsed))
	wind.modulate.a = 0.8 * smoothstep(0.0, 0.15, elapsed) * (1.0 - smoothstep(DURATION - 0.25, DURATION, elapsed))
	if elapsed >= DURATION: queue_free()

## Body-height placement respects Bash sides while the named figure remains on its captured hex; otherwise the saved hex stays authoritative.
func _anchor(hex_id: int, identifier: int) -> Vector2:
	var cell := board.hex_grid.get_child(hex_id) as HexCell
	for figure in cell.unit_figures.get_children():
		if int(figure.get_meta("unit_id", -1)) == identifier:
			return board.to_local(figure.global_position) + Vector2(0, -65)
	return board.axial_to_screen(Match.get_hex(hex_id).coordinate) + Vector2(0, -65)
