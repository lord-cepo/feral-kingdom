## Bottom-corner roster toggle; its stable button hitbox hosts a smoothly reflecting PixelLab arrow.
extends Button

var artwork := TextureRect.new()
var player_id := 1
var reflection_tween: Tween
var hover_tween: Tween

## LocalMatchController builds one button per player and connects pressed to its independent roster toggle.
## Left starts pointing right; right starts pointing left. Only the artwork transforms, so the click target remains stable.
func setup(owner_id: int) -> void:
	player_id = owner_id
	size = Vector2(56, 50)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tooltip_text = "Show cards"
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		add_theme_stylebox_override(state, StyleBoxEmpty.new())
	var atlas := AtlasTexture.new()
	atlas.atlas = preload("res://assets/ui/arrow-sign.png")
	atlas.region = Rect2(18, 16, 28, 25)
	artwork.texture = atlas
	artwork.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	artwork.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	artwork.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	artwork.mouse_filter = Control.MOUSE_FILTER_IGNORE
	artwork.size = size
	artwork.pivot_offset = size * 0.5
	artwork.scale.x = 1.0 if player_id == 1 else -1.0
	add_child(artwork)
	mouse_entered.connect(_animate_hover.bind(true))
	mouse_exited.connect(_animate_hover.bind(false))

## Controller toggles ease a centered horizontal reflection over 280ms; rapid clicks reverse from the current visible width.
func set_open(open: bool) -> void:
	tooltip_text = "Hide cards" if open else "Show cards"
	if reflection_tween != null: reflection_tween.kill()
	var direction := 1.0 if player_id == 1 else -1.0
	reflection_tween = create_tween()
	reflection_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	reflection_tween.tween_property(artwork, "scale:x", -direction if open else direction, 0.28)

## Pointer enter/exit nudges the art six pixels toward the board and back without moving its stable hitbox or interrupting reflection.
func _animate_hover(hovering: bool) -> void:
	if hover_tween != null: hover_tween.kill()
	hover_tween = create_tween()
	hover_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	var direction := 1.0 if player_id == 1 else -1.0
	hover_tween.tween_property(artwork, "position:x", direction * 6.0 if hovering else 0.0, 0.18)
