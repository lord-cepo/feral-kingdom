## Shared pixel cursor palette for both client entry scenes; cursor shapes never change interaction legality.
extends RefCounted

## ArmyMenu._ready and Game._ready install identical shapes even when either scene is launched directly.
## Native LineEdit/text dragging and Control drag/drop select their own shapes; hotspots stay inside each 32x40 texture.
static func install() -> void:
	var hand := preload("res://assets/ui/hand-cursor.svg")
	for shape in [Input.CURSOR_ARROW, Input.CURSOR_POINTING_HAND, Input.CURSOR_CROSS]:
		Input.set_custom_mouse_cursor(hand, shape, Vector2(12, 2))
	Input.set_custom_mouse_cursor(preload("res://assets/ui/text-cursor.svg"), Input.CURSOR_IBEAM, Vector2(16, 20))
	Input.set_custom_mouse_cursor(preload("res://assets/ui/grab-cursor.svg"), Input.CURSOR_MOVE, Vector2(16, 18))
	Input.set_custom_mouse_cursor(preload("res://assets/ui/drag-cursor.svg"), Input.CURSOR_DRAG, Vector2(16, 18))
	Input.set_custom_mouse_cursor(preload("res://assets/ui/drop-cursor.svg"), Input.CURSOR_CAN_DROP, Vector2(12, 2))
	Input.set_custom_mouse_cursor(preload("res://assets/ui/forbidden-cursor.svg"), Input.CURSOR_FORBIDDEN, Vector2(16, 20))
