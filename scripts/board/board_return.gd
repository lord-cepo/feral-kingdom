## Finite cosmetic snapshot of a returned unit; rules have already moved its stable identity to hand.
extends Node2D

## GuerraBoard calls before repaint removes the old figure, preserving its actual visible pose, Bash offset, alpha and shader state.
## A short upward fade finishes before phase continuations or the next captured trigger acknowledgement; it never changes Match.
func setup(board: GuerraBoard, event: EffectEvent) -> void:
	var hex_id := int(event.data.get("last_hex", -1))
	if hex_id < 0 or hex_id >= board.hex_grid.get_child_count():
		queue_free()
		return
	var cell := board.hex_grid.get_child(hex_id) as HexCell
	var original: Sprite2D
	for figure in cell.unit_figures.get_children():
		if figure is Sprite2D and int(figure.get_meta("unit_id", -1)) == event.target.id:
			original = figure
			break
	if original == null:
		queue_free()
		return
	var image := Sprite2D.new()
	image.texture = original.texture
	image.offset = original.offset
	image.centered = original.centered
	image.texture_filter = original.texture_filter
	image.scale = original.global_scale / board.global_scale
	image.rotation = original.global_rotation - board.global_rotation
	image.modulate = original.modulate
	if original.material != null: image.material = original.material.duplicate()
	position = board.to_local(original.global_position)
	z_index = 12
	add_child(image)
	var fade := create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	fade.tween_property(self, "position", position + Vector2(0, -30), 0.32)
	fade.tween_property(image, "modulate:a", 0.0, 0.32)
	fade.chain().tween_callback(queue_free)
