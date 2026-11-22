## Orders cosmetic impact settling, Slash damage, and optional Skull death without mutating authoritative life or defeat.
extends Node2D

const DAMAGE_DURATION := 1.5
const DEATH_DURATION := 1.5
const BASH_LIFE_BEAT := 0.45
const BASH_DEPARTURE_DURATION := 0.28
var board: GuerraBoard
var unit: UnitInfo
var hex_id := -1
var delay := 0.0
var elapsed := 0.0
var damage_started := false
var death_started := false
var died := false
var ghost: Sprite2D
var previous_life := Vector2i.ZERO
var life_revealed := false
var ghost_life: RichTextLabel
## The cell keeps this exact Bash layout alive until this feedback leaves the board.
var bash: BashInfo
var bash_participant_nodes: Array[CanvasItem] = []
var bash_departure_alphas: Array[float] = []

## Board life observation captures the last displayed figure before refresh removes a defeated unit; impact delay lets attack art finish first.
## Previous life is a presentation snapshot only, exposed through Board.life_number until the Slash reaches its damage beat.
func setup(owner_board: GuerraBoard, owner_unit: UnitInfo, last_hex: int, impact_delay: float, old_life: Vector2i) -> void:
	board = owner_board
	unit = owner_unit
	hex_id = last_hex
	delay = impact_delay
	previous_life = old_life
	_capture_figure()
	died = unit.t_state == Enum.t_state.DEFEATED
	if ghost != null: ghost.visible = died
	if ghost_life != null: ghost_life.visible = died

## Later life/death notifications can promote an already queued damage sequence to death without replaying its Slash.
func mark_death() -> void:
	died = true
	if ghost != null: ghost.show()
	if ghost_life != null: ghost_life.show()

## setup() retains a Bash participant's live presentation nodes. Outside Bash it snapshots the visible pose and life row.
## A separate life row survives lethal removal so its old value can still change and pulse during Slash before Skull fades it out.
## Copies the exact ordinary/Bash life label's bounds and alignment, keeping the retained row centered over its participant instead of left-aligned.
## The retained label uses the same base font size as the live hex labels.
func _capture_figure() -> void:
	var cell := board.hex_grid.get_child(hex_id) as HexCell
	var encounter := cell.rendered_bash
	if encounter != null and unit.iun in [encounter.attacker_id, encounter.defender_id]:
		bash = encounter
		for figure: CanvasItem in cell.unit_figures.get_children():
			if int(figure.get_meta("unit_id", -1)) == unit.iun: bash_participant_nodes.append(figure)
		for overlay: CanvasItem in cell.bash_overlays:
			if int(overlay.get_meta("unit_id", -1)) == unit.iun: bash_participant_nodes.append(overlay)
		return
	var source_info := cell.get_node("CoordinateLabel") as RichTextLabel
	ghost_life = RichTextLabel.new()
	ghost_life.bbcode_enabled = true
	ghost_life.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ghost_life.scroll_active = false
	ghost_life.size = Vector2(source_info.size.x, 100)
	var info_transform := board.global_transform.affine_inverse() * source_info.get_global_transform()
	ghost_life.position = info_transform.origin
	ghost_life.scale = info_transform.get_scale()
	ghost_life.rotation = info_transform.get_rotation()
	ghost_life.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ghost_life.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	ghost_life.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	ghost_life.add_theme_font_override("normal_font", HexCell.INFO_FONT)
	ghost_life.add_theme_font_size_override("normal_font_size", HexCell.INFO_FONT_SIZE)
	ghost_life.add_theme_color_override("font_outline_color", Color("#111827"))
	ghost_life.add_theme_constant_override("outline_size", 4)
	ghost_life.z_index = 7
	add_child(ghost_life)
	for figure in cell.unit_figures.get_children():
		if not figure is Sprite2D or int(figure.get_meta("unit_id", -1)) != unit.iun: continue
		ghost = Sprite2D.new()
		ghost.texture = figure.texture
		ghost.offset = figure.offset
		ghost.centered = figure.centered
		ghost.flip_h = figure.flip_h
		ghost.flip_v = figure.flip_v
		ghost.transform = board.global_transform.affine_inverse() * figure.global_transform
		ghost.modulate = figure.modulate
		ghost.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		if figure.material != null: ghost.material = figure.material.duplicate()
		ghost.z_index = 6
		add_child(ghost)
		break

## Board.life_number uses this beat for both the reveal and its number pulse.
func life_reveal_delay() -> float:
	return DAMAGE_DURATION if bash != null else 0.25

## Godot waits for impact before Slash, then plays Skull on defeat before fading the figure and its stats.
## The retained non-Bash row uses HexCell's Bash stat formatter so the death cue keeps the same life and modifier layout.
## Keeping the node alive makes HexCell and the presentation gate wait through the complete damage/death sequence.
func _process(delta: float) -> void:
	if Match.get_unit(unit.iun) != unit:
		queue_free()
		return
	elapsed += delta
	if damage_started and elapsed - delay >= life_reveal_delay(): life_revealed = true
	if ghost_life != null:
		var cell := board.hex_grid.get_child(hex_id) as HexCell
		ghost_life.text = cell._bash_stats_text(unit)
	if elapsed < delay: return
	if not damage_started:
		if board._attack_feedback_delay(hex_id) > 0.251: return
		delay = elapsed
		damage_started = true
		_play_clip("slash", DAMAGE_DURATION)
	var death_time := elapsed - delay - DAMAGE_DURATION - (BASH_LIFE_BEAT if bash != null else 0.0)
	if death_time < 0.0: return
	if not died:
		queue_free()
		return
	if not death_started:
		death_started = true
		_play_clip("skull", DEATH_DURATION)
	var fade_time := death_time - DEATH_DURATION
	if fade_time < 0.0: return
	if bash != null:
		_fade_bash_participant(fade_time)
		return
	var opacity := 1.0 - smoothstep(0.0, BASH_DEPARTURE_DURATION, fade_time)
	if ghost != null: ghost.self_modulate.a = opacity
	if ghost_life != null: ghost_life.self_modulate.a = opacity
	if fade_time >= BASH_DEPARTURE_DURATION: queue_free()

## The Bash pose and its rows fade together only after Skull completes. HexCell recenters after the last feedback node exits.
func _fade_bash_participant(time: float) -> void:
	if bash_departure_alphas.is_empty():
		for node in bash_participant_nodes:
			bash_departure_alphas.append(node.self_modulate.a if is_instance_valid(node) else 0.0)
	var opacity := 1.0 - smoothstep(0.0, BASH_DEPARTURE_DURATION, time)
	for index in bash_participant_nodes.size():
		var node := bash_participant_nodes[index]
		if is_instance_valid(node): node.self_modulate.a = bash_departure_alphas[index] * opacity
	if time >= BASH_DEPARTURE_DURATION: queue_free()

## The sequence starts each finite feedback clip exactly once; board_trigger owns its fade-in, playback and fade-out.
func _play_clip(clip: String, duration: float) -> void:
	var marker := preload("res://scripts/board/board_trigger.gd").new()
	marker.setup(board, unit, hex_id, clip, duration)
	add_child(marker)
	marker._process(0.0)
