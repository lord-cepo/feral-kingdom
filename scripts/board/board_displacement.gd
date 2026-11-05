## Cosmetic Push/Pull: a sliding recipient copy and finite directional wind at its final hex. Never changes Match.
extends Node2D

const EFFECT = preload("res://scripts/board/displacement_effect.gd")
var board: GuerraBoard
var unit: UnitInfo
var source_hex: int
var origin_hex: int
var destination_hex: int
var pulling := false
var elapsed := 0.0
var target_copy := Sprite2D.new()
var destination_cell: HexCell
var landing_hidden := false
var departure_offset := Vector2.ZERO
## GuerraBoard calls after repainting the committed displacement; captures historical hexes and the target's final figure pose.
## Slides the recipient once; passes its copy to the shared effect so wind follows the live slide, then stays at the landing.
## Initializes the shared arrival-info alpha to zero so destination labels do not appear before the sliding unit approaches.
func setup(owner_board: GuerraBoard, target_unit: UnitInfo, actor_hex: int, from_hex: int,
		to_hex: int, is_pull: bool, actor_id: int) -> void:
	board = owner_board
	unit = target_unit
	source_hex = actor_hex
	origin_hex = from_hex
	destination_hex = to_hex
	pulling = is_pull
	destination_cell = board.hex_grid.get_child(destination_hex) as HexCell
	var origin_cell := board.hex_grid.get_child(origin_hex) as HexCell
	departure_offset = origin_cell.take_bash_departure_offset(unit.iun)
	target_copy.z_index = 6
	target_copy.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(target_copy)
	for figure in destination_cell.unit_figures.get_children():
		if figure is Sprite2D and int(figure.get_meta("unit_id", -1)) == unit.iun:
			target_copy.texture = figure.texture
			target_copy.offset = figure.offset
			target_copy.centered = figure.centered
			target_copy.flip_h = figure.flip_h
			target_copy.flip_v = figure.flip_v
			target_copy.modulate = figure.modulate
			if figure.material != null: target_copy.material = figure.material.duplicate()
			break
	if target_copy.texture != null:
		destination_cell.set_displacement_hidden(unit.iun, true)
		landing_hidden = true
		destination_cell.set_arrival(unit.iun, 0.0)
	var effect := EFFECT.new()
	effect.setup(board, source_hex, origin_hex, destination_hex, pulling, actor_id, unit.iun, target_copy)
	add_child(effect)

## Godot slides once over one second, restores the figure, then finishes the finite effects.
## The last 0.4 seconds blend destination/Bash participant info through HexCell.set_arrival(), matching walking's final half-step.
func _process(delta: float) -> void:
	if unit == null or Match.get_unit(unit.iun) != unit:
		finish()
		return
	if unit.t_state != Enum.t_state.DEPLOYED or unit.ihx != destination_hex:
		finish()
		return
	elapsed += delta
	if landing_hidden:
		destination_cell.set_arrival(unit.iun, clampf((elapsed - 0.6) / 0.4, 0.0, 1.0))
	var origin := Match.get_hex(origin_hex)
	var destination := Match.get_hex(destination_hex)
	if origin == null or destination == null:
		finish()
		return
	var start := board.axial_to_screen(origin.coordinate)
	for figure in destination_cell.unit_figures.get_children():
		if figure is Sprite2D and int(figure.get_meta("unit_id", -1)) == unit.iun:
			target_copy.transform = board.global_transform.affine_inverse() * figure.global_transform
			var departure_position := start + Vector2(0, -18) + departure_offset
			target_copy.position = departure_position.lerp(target_copy.position, smoothstep(0.0, 1.0, minf(elapsed, 1.0)))
			break
	if elapsed >= 1.0:
		_restore_target()
		target_copy.hide()
	if elapsed >= EFFECT.DURATION: finish()

## Completion and replacement restore the stationary target before freeing; existing match state/position is never modified.
func finish() -> void:
	_restore_target()
	queue_free()

## finish() and _exit_tree() share idempotent visibility cleanup, including scene teardown or interrupted presentations.
## Restores info only if this unit still owns the arrival channel, preserving any newer movement presentation.
func _restore_target() -> void:
	if landing_hidden and is_instance_valid(destination_cell):
		destination_cell.set_displacement_hidden(unit.iun, false)
		if destination_cell.arriving_unit_id == unit.iun: destination_cell.set_arrival(-1, 1.0)
	landing_hidden = false

## Godot cleanup restores any target hidden by this overlay, even if the board is removed mid-slide.
func _exit_tree() -> void:
	_restore_target()
