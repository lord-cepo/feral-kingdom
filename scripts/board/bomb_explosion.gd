## One resolved bomb victim's cosmetic explosion; the board waits for this finite clip before Slash or trigger acknowledgement.
extends AnimatedSprite2D

const DURATION := 1.0
var board: GuerraBoard
var hex_id := -1
var delay := 0.0
var elapsed := 0.0

## Board resolved bomb_explosion events capture the blast hex and remaining radial travel; no bomb body is retained beneath disappearing fragments.
func setup(owner_board: GuerraBoard, target_hex: int, travel_delay: float) -> void:
	board = owner_board
	hex_id = target_hex
	delay = travel_delay
	z_index = 8
	scale = Vector2.ONE * HexCell.BOMB_SCALE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var frames := SpriteFrames.new()
	frames.set_animation_loop(&"default", false)
	frames.set_animation_speed(&"default", 9.0 / DURATION)
	for index in 9:
		frames.add_frame(&"default", load("res://assets/effects/bomb-explosion/frame_%d.png" % index))
	sprite_frames = frames
	modulate.a = 0.0

## Godot aligns the clip with the normal bomb slot across camera/layout changes, waits for arrival, plays once and eases its opacity at both ends.
func _process(delta: float) -> void:
	elapsed += delta
	var tile := Match.get_hex(hex_id)
	if tile == null:
		queue_free()
		return
	position = board.axial_to_screen(tile.coordinate) + HexCell.BOMB_OFFSET
	if elapsed < delay: return
	if not is_playing() and elapsed - delay < DURATION: play()
	var progress := elapsed - delay
	modulate.a = smoothstep(0.0, 0.1, progress) * (1.0 - smoothstep(DURATION - 0.2, DURATION, progress))
	if progress >= DURATION: queue_free()
