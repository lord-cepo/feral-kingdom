## Cosmetic previous-turn playback. Owns no command and never emits a Match event.
extends Node2D

var board: GuerraBoard
var record: Dictionary
var elapsed := 0.0
var actor := Node2D.new()
var trail: Dictionary
var highlight := Sprite2D.new()
var icon: Node2D

## GuerraBoard calls before parenting with historical coordinates; walking replays only paws, leaving the unit in place.
## Every non-walking verb discovers matching animation frames or icon art automatically; missing art falls back to readable words (including Return to hand).
## Push/Pull replay the shared icon/wind pair and highlight the previous target hex without shifting units.
## Yellow replay highlighting uses only the existing transparent pixel-art rim, matching target highlight artwork.
## Deployment replays the existing drop/fade/sit pose at its captured landing without deploying, paying or emitting events again.
func setup(owner_board: GuerraBoard, saved: Dictionary) -> void:
	board = owner_board
	record = saved
	add_child(actor)
	trail = {"actor": actor}
	highlight.texture = preload("res://assets/grey-hex.png")
	highlight.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	highlight.modulate = Color(1.0, 0.76, 0.22, 1.0)
	highlight.z_index = 4
	add_child(highlight)
	if record.action == &"deploy":
		if record.unit.ihx == int(record.target) and record.unit.t_state == Enum.t_state.DEPLOYED:
			var cell := board.hex_grid.get_child(record.target) as HexCell
			cell.play_character_deploy(record.unit.iun)
	elif record.action in [&"push", &"pull"]:
		var effect := preload("res://scripts/board/displacement_effect.gd").new()
		effect.setup(board, record.origin, int(record.get("aim_hex", record.target)), record.target,
			record.action == &"pull", record.unit.iun, int(record.get("target_unit_id", -1)))
		add_child(effect)
	elif record.path.size() < 2:
		icon = Node2D.new()
		icon.z_index = 7
		add_child(icon)
		_build_action_art()
	_process(0.0)

## setup() discovers contiguous assets/effects/<verb>/frame_0.png onward at 5.5fps, including Fire/Bow without special cases.
## Otherwise uses GameIcons, then assets/icons/ui/<verb>.png, then a readable verb label, so new verbs always have playback.
## Texture loading supports imported/exported resources and raw working-project PNGs; all artwork stays cosmetic.
## Bomb Throw uses the same texture and scale as HexCell live travel, rather than the larger UI icon.
## Fire shares live flame alignment; a captured bomb ignition instead uses the bomb slot without the internal flame shift.
## Stun uses its complete nine-frame clip over the shared STUN_DURATION, at the live recipient's head-height offset.
func _build_action_art() -> void:
	var frames := SpriteFrames.new()
	frames.set_animation_speed(&"default", 5.5)
	frames.set_animation_loop(&"default", true)
	var index := 0
	var clip_folder := String(record.action)
	while true:
		var texture := _texture_at("res://assets/effects/%s/frame_%d.png" % [clip_folder, index])
		if texture == null: break
		frames.add_frame(&"default", texture)
		index += 1
	if index == 0:
		var texture := load(HexCell.BOMB_ICON) as Texture2D if record.action == &"bomb_throw" else GameIcons.texture(record.action, record.owner)
		if texture == null: texture = _texture_at("res://assets/icons/ui/%s.png" % record.action)
		if texture != null: frames.add_frame(&"default", texture)
	if record.action == &"stun":
		frames.set_animation_loop(&"default", false)
		frames.set_animation_speed(&"default", float(frames.get_frame_count(&"default")) / preload("res://scripts/board/board_trigger.gd").STUN_DURATION)
	if frames.get_frame_count(&"default") > 0:
		var sprite := AnimatedSprite2D.new()
		sprite.sprite_frames = frames
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		sprite.flip_h = record.action == &"pull"
		var texture := frames.get_frame_texture(&"default", 0)
		sprite.scale = Vector2.ONE * (84.0 / maxf(texture.get_width(), texture.get_height()))
		if record.action == &"bomb_throw": sprite.scale = Vector2.ONE * HexCell.BOMB_SCALE
		if record.action == &"fire" and not record.get("aim_bomb", false): sprite.position = preload("res://scripts/board/board_fire.gd").FIRE_ART_OFFSET
		icon.add_child(sprite)
		sprite.play()
	else:
		var label := Label.new()
		label.text = String(record.action).replace("_", " ").capitalize()
		label.position = Vector2(-60, -20)
		label.size = Vector2(120, 40)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.add_theme_font_size_override("font_size", 25)
		label.add_theme_color_override("font_color", Color("#ffd84a"))
		label.add_theme_constant_override("outline_size", 4)
		icon.add_child(label)

## Art discovery probes optional paths without errors; absent frames end the clip and absent icons use a label.
func _texture_at(path: String) -> Texture2D:
	if ResourceLoader.exists(path, "Texture2D"): return load(path) as Texture2D
	if not FileAccess.file_exists(path): return null
	var image := Image.load_from_file(path)
	return ImageTexture.create_from_image(image) if image != null and not image.is_empty() else null

## Godot advances the captured path at the normal 0.8s per hex; board's paw helper supplies staggered prints and independent fades.
## Origin pixel-art rims pulse yellow, then fade; the cell/frame transforms keep alignment during resize or target scaling.
## Plays once per click, then frees after the final fade; next turn/unit replacement can end playback early.
## No rules execute; marker records are independent of source survival while ordinary unit history validates its identity.
## Shared attack offsets align replay destinations with normal Fire/Bow markers; Bow also retains its travel-facing rotation.
## Push/Pull wind appears at the captured landing, with direction defined by the actor-to-original-target line, matching live presentation.
## Push/Pull lifetime includes both wind passes and their final fade, using the live presenter's shared duration.
func _process(delta: float) -> void:
	if Match.turn_number != int(record.turn) + 1 or (not record.get("marker", false) and (record.unit == null or Match.get_unit(record.unit.iun) != record.unit)):
		queue_free()
		return
	elapsed += delta
	var origin := Match.get_hex(record.origin)
	if origin == null:
		queue_free()
		return
	var highlight_hex := int(record.get("aim_hex", record.origin)) if record.action in [&"push", &"pull"] else int(record.origin)
	var cell := board.hex_grid.get_child(highlight_hex) as HexCell
	var frame := cell.get_node("HexFrame") as Sprite2D
	highlight.transform = board.global_transform.affine_inverse() * cell.global_transform * frame.transform
	var duration := 1.2
	if record.action == &"stun": duration = preload("res://scripts/board/board_trigger.gd").STUN_DURATION - 0.3
	if record.action in [&"push", &"pull"]:
		duration = preload("res://scripts/board/displacement_effect.gd").DURATION - 0.3
	if record.path.size() >= 2:
		var path: Array = record.path
		duration = float(path.size() - 1) * 0.8
		var progress := clampf(elapsed / 0.8, 0.0, float(path.size() - 1))
		var index := mini(int(progress), path.size() - 2)
		var start := Match.get_hex(int(path[index]))
		var finish := Match.get_hex(int(path[index + 1]))
		if start == null or finish == null:
			queue_free()
			return
		actor.position = board.axial_to_screen(start.coordinate).lerp(board.axial_to_screen(finish.coordinate), progress - index) + Vector2(0, -18)
		board._advance_paw_trail(trail)
	elif icon != null:
		var target := Match.get_hex(record.target)
		if target != null:
			var start := board.axial_to_screen(origin.coordinate)
			var offset: Vector2 = preload("res://scripts/board/board_fire.gd").TARGET_OFFSETS.get(record.action, Vector2.ZERO)
			if record.get("aim_bomb", false): offset = HexCell.BOMB_OFFSET
			var finish := board.axial_to_screen(target.coordinate) + offset
			icon.position = start.lerp(finish, smoothstep(0.0, 1.0, minf(elapsed / 0.65, 1.0)))
			if record.action == &"bow": icon.rotation = (finish - start).angle()
			icon.modulate.a = minf(elapsed / 0.2, 0.8) * (1.0 - clampf((elapsed - duration) / 0.3, 0.0, 1.0))
	highlight.modulate.a = (0.75 + 0.25 * sin(elapsed * 6.0)) * (1.0 - clampf((elapsed - duration) / 0.3, 0.0, 1.0))
	if elapsed > duration + 0.3: queue_free()
