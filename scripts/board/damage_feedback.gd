## Orders cosmetic impact settling, Slash damage, and optional Skull death without mutating authoritative life or defeat.
extends Node2D

const DAMAGE_DURATION := 1.5
const DEATH_DURATION := 1.5
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
var ghost_life_show_max := true

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

## setup() snapshots only the visible pose/material, keeping death presentation independent from the removed logical unit.
## A separate life row survives lethal removal so its old value can still change and pulse during Slash before Skull fades it out.
## Copies the exact ordinary/Bash life label's bounds and alignment, keeping the retained row centered over its participant instead of left-aligned.
func _capture_figure() -> void:
	var cell := board.hex_grid.get_child(hex_id) as HexCell
	var source_info := cell.get_node("CoordinateLabel") as RichTextLabel
	for child in cell.get_children():
		if child is RichTextLabel and child.name.begins_with("BashStats_") and int(child.get_meta("unit_id", -1)) == unit.iun:
			source_info = child
			ghost_life_show_max = false
			break
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
	ghost_life.add_theme_color_override("default_color", Color("#ef7770") if unit.player == 1 else Color("#6da9ee"))
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

## Godot first waits for impact, then completes the new Slash; lethal damage adds a fading Skull and eases the retained figure away.
## Keeping this node alive lets trigger presentation wait for the whole causal sequence, including death, before its blink accepts input.
## Rechecks deferred Cannon/bomb travel before starting damage, then anchors the damage/death timeline to that actual start.
## Life display publishes 250ms into Slash and pulses for 450ms, including a retained life row for lethal damage.
## The retained life row uses the same invisible 60px strut as hex info, preserving its vertical baseline while numbers pulse.
func _process(delta: float) -> void:
	if Match.get_unit(unit.iun) != unit:
		queue_free()
		return
	elapsed += delta
	if damage_started and elapsed - delay >= 0.25: life_revealed = true
	if ghost_life != null:
		ghost_life.text = "%s%s %s" % [HexCell.INFO_ROW_SPACER, board.life_number(unit), GameIcons.bb(&"heart", unit.player, 48)]
		if ghost_life_show_max: ghost_life.text += " " + board.life_number(unit, true)
	if elapsed < delay: return
	if not damage_started:
		if board._attack_feedback_delay(hex_id) > 0.251: return
		delay = elapsed
		damage_started = true
		_play_clip("slash", DAMAGE_DURATION)
	var death_time := elapsed - delay - DAMAGE_DURATION
	if death_time < 0.0: return
	if not died:
		queue_free()
		return
	if not death_started:
		death_started = true
		_play_clip("skull", DEATH_DURATION)
	if ghost != null: ghost.modulate.a = 1.0 - smoothstep(0.0, 0.35, death_time)
	if ghost_life != null: ghost_life.modulate.a = 1.0 - smoothstep(0.0, 0.35, death_time)
	if death_time >= DEATH_DURATION: queue_free()

## The sequence starts each finite feedback clip exactly once; board_trigger owns its fade-in, playback and fade-out.
func _play_clip(clip: String, duration: float) -> void:
	var marker := preload("res://scripts/board/board_trigger.gd").new()
	marker.setup(board, unit, hex_id, clip, duration)
	add_child(marker)
	marker._process(0.0)
