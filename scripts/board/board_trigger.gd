## Cosmetic PixelLab unit feedback: finite bursts or a Stun-bound sleeping loop, without changing rules or delaying choices.
extends AnimatedSprite2D

const STUN_DURATION := 1.5

var board: GuerraBoard
var unit: UnitInfo
var fallback_hex := -1
var lifetime := 0.0
var elapsed := 0.0
var burst_offset := Vector2(-52, -110)
var sleeping := false
var persistent_trigger := false
var dismissed := false
var expires_turn := -1
var click_bounds := Rect2()

## GuerraBoard starts this once for a captured trigger execution; the eight-frame star clip plays twice at 8fps.
## A defeated source uses its event's captured hex; active figures and walkers keep the top-left burst attached to their pose.
## Slash uses the replacement eight-frame clip; Skull uses nine frames, both centered with 1.5s lifetimes and in/out fades.
## Shield/Mshield use separate nine-frame steel/purple clips with matching recipient placement and finite fades.
## Sleeping uses nine looping frames above-right, fading with the live Stun count rather than animation completion.
## Stun uses nine orbiting-star frames at head height for STUN_DURATION, shared with its click replay.
## Trigger loops until dismissed or the end of the following turn, with 0.25s in/0.35s out fades.
## Trigger placement is 20px lower than the original top-left cue; caches stable clip bounds for AnimatedSprite2D hit detection.
func setup(owner_board: GuerraBoard, owner_unit: UnitInfo, hex_id: int,
		clip: String = "trigger", duration: float = 0.0) -> void:
	board = owner_board
	unit = owner_unit
	fallback_hex = hex_id
	lifetime = duration
	sleeping = clip == "sleeping"
	persistent_trigger = clip == "trigger"
	expires_turn = Match.turn_number + 1
	if persistent_trigger: burst_offset = Vector2(-52, -90)
	if clip in ["slash", "shield", "mshield", "skull"]: burst_offset = Vector2(0, -65)
	elif sleeping: burst_offset = Vector2(48, -110)
	elif clip == "stun": burst_offset = preload("res://scripts/board/board_fire.gd").TARGET_OFFSETS[&"stun"]
	z_index = 9
	scale = Vector2.ONE * 2.0
	if clip in ["slash", "shield", "mshield", "skull"]: scale = Vector2.ONE * 3.0
	elif clip == "stun": scale = Vector2.ONE * 2.625
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var frames := SpriteFrames.new()
	frames.set_animation_loop(&"default", sleeping or persistent_trigger)
	var frame_count := 9 if clip in ["shield", "mshield", "sleeping", "stun", "skull"] else 8
	frames.set_animation_speed(&"default", float(frame_count) / lifetime if lifetime > 0.0 else 8.0)
	for index in frame_count:
		var path := "res://assets/effects/%s/frame_%d.png" % [clip, index]
		var texture: Texture2D
		if ResourceLoader.exists(path, "Texture2D"): texture = load(path) as Texture2D
		if texture == null:
			var image := Image.load_from_file(path)
			if image != null and not image.is_empty(): texture = ImageTexture.create_from_image(image)
		if texture != null: frames.add_frame(&"default", texture)
		else: push_error("Cannot load feedback frame: %s" % path)
	if clip == "trigger":
		var pass_frames := frames.get_frame_count(&"default")
		for index in pass_frames:
			frames.add_frame(&"default", frames.get_frame_texture(&"default", index))
	sprite_frames = frames
	for index in frames.get_frame_count(&"default"):
		var frame_size := frames.get_frame_texture(&"default", index).get_size()
		var bounds := Rect2(-frame_size * 0.5, frame_size)
		click_bounds = bounds if index == 0 else click_bounds.merge(bounds)
	if lifetime <= 0.0 and not sleeping and not persistent_trigger: animation_finished.connect(queue_free, CONNECT_ONE_SHOT)
	else: modulate.a = 0.0
	play()

## GuerraBoard._input() passes the event's viewport coordinates; convert through camera/canvas transforms into stable clip bounds.
## AnimatedSprite2D has no Sprite2D.get_rect(); cached bounds also keep the blinking cue clickable across empty animation frames.
func contains_pointer(viewport_position: Vector2) -> bool:
	return click_bounds.has_point(get_global_transform_with_canvas().affine_inverse() * viewport_position)

## Godot follows the source figure each frame (including walking/Bash offsets) and frees stale markers after a match reset.
## Off-board/death triggers remain at their captured tile; the offset places the burst above and left of the unit.
## Timed slash/shield feedback fades in/out over its captured lifetime and then frees, including while the troop walks.
## Sleeping continuously reads Stun, fading in over 0.25s and out over 0.35s at zero/off-board; returning Stun reverses that fade without restarting frames.
## A live displacement copy takes priority over the hidden landing figure, keeping sleeping/bursts attached throughout Push/Pull.
## Persistent triggers retain their loop while dismissed/expired cues fade without accepting further clicks.
func _process(delta: float) -> void:
	elapsed += delta
	if lifetime > 0.0:
		modulate.a = smoothstep(0.0, 0.2, elapsed) * (1.0 - smoothstep(lifetime - 0.35, lifetime, elapsed))
		if elapsed >= lifetime:
			queue_free()
			return
	if unit == null or Match.get_unit(unit.iun) != unit:
		queue_free()
		return
	if sleeping:
		var stun := Match.get_property(TargetRef.property(TargetRef.unit(unit.iun), UnitInfo.STUN_COUNTER))
		var should_sleep: bool = unit.t_state == Enum.t_state.DEPLOYED and stun != null and stun.value > 0
		modulate.a = move_toward(modulate.a, 1.0 if should_sleep else 0.0, delta / (0.25 if should_sleep else 0.35))
		if not should_sleep and modulate.a <= 0.0:
			queue_free()
			return
	if persistent_trigger:
		var showing := not dismissed and Match.turn_number <= expires_turn
		modulate.a = move_toward(modulate.a, 1.0 if showing else 0.0, delta / (0.25 if showing else 0.35))
		if not showing and modulate.a <= 0.0:
			queue_free()
			return
	if board.displacement_presenters.has(unit.iun):
		var displacement: Node2D = board.displacement_presenters[unit.iun]
		if is_instance_valid(displacement) and not displacement.is_queued_for_deletion() and displacement.landing_hidden:
			position = displacement.target_copy.position + burst_offset
			return
	if board.walking.has(unit.iun):
		position = board.walking[unit.iun].actor.position + burst_offset
		return
	var hex_id := unit.ihx if unit.t_state == Enum.t_state.DEPLOYED else fallback_hex
	var tile := Match.get_hex(hex_id)
	if tile == null:
		queue_free()
		return
	position = board.axial_to_screen(tile.coordinate) + Vector2(0, -18) + burst_offset
	var cell := board.hex_grid.get_child(hex_id) as HexCell
	for figure in cell.unit_figures.get_children():
		if int(figure.get_meta("unit_id", -1)) == unit.iun:
			position = board.to_local(figure.global_position) + burst_offset
			break
