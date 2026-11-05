## Selected-unit action buttons; reads presentation data from LocalMatchController and never executes rules directly.
extends Control
signal closed

var controller: LocalMatchController
var unit_id := -1
const FRAME_RATE := 20.0
const OPEN_TIME := 7.0 / FRAME_RATE
const BUTTON_SIZE := Vector2(180, 54)
var elapsed := 0.0
var closing := false
var visual_time := 0.0
var frames: Array[Texture2D] = []
var papers: Array[TextureRect] = []
var captions: Array[Control] = []
var buttons: Array[Button] = []
var indices: Array[int] = []
var action_materials: Array[ShaderMaterial] = []

## Controller._refresh_hud() creates this once per selected identity; rows retain the controller's movement-first shortcut order.
## Smaller parchment buttons play seven frames at 20fps; shortcut numbers sit inside PixelLab keyboard keycaps.
## Disabled rows share one greyscale material; action copy sits 3px left and 5px down, and key numbers offset (-3,-14).
func setup(owner_controller: LocalMatchController, unit: UnitInfo) -> void:
	controller = owner_controller
	unit_id = unit.iun
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for index in 7: frames.append(load("res://assets/ui/parchment/frame_%d.png" % index))
	indices = controller._ordered_effect_indices(unit)
	size = BUTTON_SIZE
	for slot in indices.size():
		var button := Button.new()
		var material := ShaderMaterial.new()
		material.shader = preload("res://assets/shaders/action_button.gdshader")
		button.material = material
		action_materials.append(material)
		button.position = Vector2(slot * 188, 0)
		button.size = BUTTON_SIZE
		button.pivot_offset = BUTTON_SIZE * 0.5
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		for state in ["normal", "hover", "pressed", "disabled", "focus"]:
			button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
		button.pressed.connect(controller._begin_unit_action.bind(unit_id, indices[slot]))
		add_child(button)
		buttons.append(button)
		var paper := TextureRect.new()
		paper.texture = frames[0]
		paper.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		paper.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		paper.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(paper)
		papers.append(paper)
		var caption := HBoxContainer.new()
		caption.position = Vector2(18, 9)
		caption.size = Vector2(144, 36)
		caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(caption)
		captions.append(caption)
		var shortcut := Label.new()
		shortcut.text = str(slot + 1)
		shortcut.add_theme_font_size_override("font_size", 21)
		shortcut.add_theme_color_override("font_color", Color("#382419"))
		shortcut.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var keycap := TextureRect.new()
		var key_art := AtlasTexture.new()
		key_art.atlas = preload("res://assets/ui/keyboard-key.png")
		key_art.region = Rect2(8, 8, 16, 16)
		keycap.texture = key_art
		keycap.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		keycap.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		keycap.custom_minimum_size = Vector2(30, 30)
		keycap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		keycap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		caption.add_child(keycap)
		keycap.add_child(shortcut)
		shortcut.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		shortcut.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		shortcut.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		shortcut.position = Vector2(-3, -14)
		var action := RichTextLabel.new()
		action.bbcode_enabled = true
		action.text = "[center]%s[/center]" % controller._parchment_action_text(unit.effects[indices[slot]], unit)
		action.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		action.add_theme_font_size_override("normal_font_size", 21)
		action.add_theme_color_override("default_color", Color("#382419"))
		action.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		action.scroll_active = false
		action.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var action_margin := MarginContainer.new()
		action_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		action_margin.add_theme_constant_override("margin_top", 5)
		action_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
		caption.add_child(action_margin)
		action_margin.add_child(action)
		var spacer := Control.new()
		spacer.custom_minimum_size.x = 6
		spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		caption.add_child(spacer)
		caption.modulate.a = 0.0
		_inherit_button_material(button)

## setup() applies the row material to every descendant so greyscale includes PixelLab icons and font glyphs.
func _inherit_button_material(node: Node) -> void:
	for child in node.get_children():
		if child is CanvasItem: child.use_parent_material = true
		_inherit_button_material(child)

## Controller refresh or identity/selection changes request a roll-up; repeated requests do not restart it.
## Disable interaction immediately while retaining this presentation until the reverse clip finishes.
func begin_close() -> void:
	closing = true
	for button in buttons:
		button.disabled = true
		button.mouse_filter = Control.MOUSE_FILTER_IGNORE

## Godot advances or reverses the same opening timeline at 20fps; deselection closes from its current frame.
## Bottom-centered rows wrap on narrow screens; rule availability is queried only while the selected unit remains valid.
## No legal target disables/greyscales a row; the runner's selected definition drives an eased enlargement, gentle pulse without changing parchment color.
## Closing preserves each row's last color state instead of treating dismissal as action unavailability.
func _process(delta: float) -> void:
	var unit := Match.get_unit(unit_id)
	if not closing and (unit == null or unit.t_state != Enum.t_state.DEPLOYED or controller.selected_unit_id != unit_id or not unit.active or unit.player != Match.active_player or Match.winner != 0):
		begin_close()
	elapsed = maxf(0.0, elapsed - delta) if closing else minf(OPEN_TIME, elapsed + delta)
	visual_time += delta
	var active := Match.rules_runner.active
	var frame := clampi(int(elapsed * FRAME_RATE), 0, 6)
	for index in buttons.size():
		var available := not closing and controller._action_available(unit, indices[index])
		if not closing: action_materials[index].set_shader_parameter("unavailable", not available)
		papers[index].texture = frames[frame]
		captions[index].modulate.a = 0.0 if closing else smoothstep(5.0 / FRAME_RATE, OPEN_TIME, elapsed)
		buttons[index].disabled = closing or elapsed < OPEN_TIME
		if not closing and elapsed >= OPEN_TIME:
			buttons[index].disabled = not available
		var selected: bool = not closing and active != null and active.source != null and active.source.kind == TargetRef.Kind.UNIT and active.source.id == unit_id and active.definition == unit.effects[indices[index]]
		var target_scale := 1.07 + 0.015 * sin(visual_time * 5.0) if selected else 1.0
		buttons[index].scale = buttons[index].scale.lerp(Vector2.ONE * target_scale, minf(1.0, delta * 14.0))
		buttons[index].z_index = 1 if selected else 0
		papers[index].modulate = Color.WHITE
	var view := get_viewport_rect().size
	var columns := maxi(1, mini(buttons.size(), int((view.x - 32.0) / 188.0)))
	var rows := ceili(float(buttons.size()) / columns)
	size = Vector2(columns * 188.0 - 8.0, rows * 60.0 - 6.0)
	position = Vector2(maxf(8, (view.x - size.x) * 0.5), maxf(8, view.y - size.y - 18))
	for index in buttons.size():
		buttons[index].position = Vector2((index % columns) * 188, (index / columns) * 60)
	if closing and elapsed <= 0.0:
		closed.emit()
		queue_free()
