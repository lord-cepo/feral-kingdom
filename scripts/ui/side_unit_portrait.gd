## Square, button-free side-tray unit portrait; front-facing seated/standing poses and click-driven posture animation are cosmetic only.
extends Control

signal pressed(unit_id: int)

const BLEND_TIME := 0.075
static var art_cache: Dictionary = {}
var unit: UnitInfo
var art: Dictionary
var hovered := false
var removing := false
var hand_standing := false
var rise_position := 0.0
var current: Texture2D
var previous: Texture2D
var blend := 1.0
var greyscale_amount := 0.0
var hero_badge: TextureRect
var deployment_bar: TextureRect

## LocalMatchController._make_card() creates a retained portrait per PixelLab identity; unsupported units hide rather than loading legacy art.
## Seated/standing/rise views and baked bounds reuse the board's single character atlas and grounded display scale.
## The controller drives posture from pending deployment selection, keeping it synchronized with highlighted hexes rather than pointer focus.
## A single premultiplied-alpha material blends poses with stable canvas-center/foot anchors; the square hit area has no visible box.
## Hero portraits add a mouse-transparent PixelLab crown beside the sprite; resizing keeps it inside the portrait corner.
## Initial greyscale reflects defeat and the owner's first-deployment restriction immediately, avoiding a colored flash on opening the roster.
## A separate left stripe displays printed deployment regions using Guerra JS's dark/light owner colors and grey front region.
func setup(owner_unit: UnitInfo, fallback_path: String) -> void:
	unit = owner_unit
	set_meta("unit_id", unit.iun)
	set_meta("unit_instance", unit)
	custom_minimum_size = Vector2(64, 64)
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	clip_contents = true
	var portrait_material := ShaderMaterial.new()
	portrait_material.shader = preload("res://assets/shaders/side_unit_portrait.gdshader")
	material = portrait_material
	greyscale_amount = 1.0 if _is_grey() else 0.0
	portrait_material.set_shader_parameter("greyscale", greyscale_amount)
	art = _load_art(unit, fallback_path)
	if art.standing.is_empty():
		hide()
		set_process(false)
		return
	current = _pose()
	_build_deployment_bar()
	if unit.type == Enum.type.HERO:
		hero_badge = TextureRect.new()
		hero_badge.texture = preload("res://assets/icons/ui/crown.png")
		hero_badge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		hero_badge.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		hero_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hero_badge.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		add_child(hero_badge)
		resized.connect(_layout_hero_badge)
		_layout_hero_badge()
	mouse_entered.connect(func() -> void: set_hovered(true))
	mouse_exited.connect(func() -> void: set_hovered(false))
	gui_input.connect(_on_gui_input)

## setup() builds a mouse-transparent deployment stripe beside the unit: Starting dark, Intermediate light, Front grey; multiple regions stack top to bottom.
## Colors describe printed regions regardless of temporary deployment availability; this never changes target legality.
## The stripe stays fully opaque through both ends, with no edge-fade material.
func _build_deployment_bar() -> void:
	var colors: PackedColorArray = []
	for region in [Enum.region.STARTING, Enum.region.INTERMEDIATE, Enum.region.FRONT]:
		if region not in unit.deploy_regions and Enum.region.ANY not in unit.deploy_regions: continue
		match region:
			Enum.region.STARTING: colors.append(Color("#b91c1c") if unit.player == 1 else Color("#1d4ed8"))
			Enum.region.INTERMEDIATE: colors.append(Color("#f87171") if unit.player == 1 else Color("#60a5fa"))
			Enum.region.FRONT: colors.append(Color("#cbd5e1"))
	if colors.is_empty(): return
	var gradient := Gradient.new()
	gradient.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	var offsets := PackedFloat32Array()
	for index in colors.size(): offsets.append(float(index) / float(colors.size()))
	gradient.offsets = offsets
	gradient.colors = colors
	var stripe := GradientTexture2D.new()
	stripe.gradient = gradient
	stripe.width = 8
	stripe.height = 128
	stripe.fill_from = Vector2.ZERO
	stripe.fill_to = Vector2(0, 1)
	deployment_bar = TextureRect.new()
	deployment_bar.texture = stripe
	deployment_bar.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	deployment_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(deployment_bar)
	resized.connect(_layout_deployment_bar)
	_layout_deployment_bar()

## setup() and resized keep the deployment stripe along the portrait's left edge without moving the sprite, crown or click area.
func _layout_deployment_bar() -> void:
	if deployment_bar == null: return
	deployment_bar.position = Vector2(1, roundf(size.y * 0.1))
	deployment_bar.size = Vector2(6, roundf(size.y * 0.8))

## setup() and the portrait's resized signal keep the hero crown near the sprite's upper right without changing its click area or posture.
func _layout_hero_badge() -> void:
	if hero_badge == null: return
	var side := clampf(size.x * 0.3, 16.0, 24.0)
	hero_badge.size = Vector2.ONE * side
	hero_badge.position = Vector2(size.x - side - 1.0, 3.0).round()

## setup() shares BoardCharacter's sheet views/baked bounds across both owners; legacy fallback paths never load previous-game portraits.
## Original alpha bounds and display span are read from metadata, eliminating per-portrait GPU image readback at startup.
func _load_art(owner_unit: UnitInfo, _fallback_path: String) -> Dictionary:
	var key := BoardCharacter._appearance_key(owner_unit)
	if art_cache.has(key): return art_cache[key]
	var result := {"seated": [], "standing": [], "bounds": {}, "span": 1.0, "rise": []}
	var pack := BoardCharacter._art_for(key) if not key.is_empty() else {}
	if pack.is_empty(): return result
	result.seated = pack.seated
	result.standing = pack.facings
	result.rise = pack.stand
	result.bounds = pack.bounds
	for frame in result.seated + result.standing + result.rise:
		var bounds: Rect2 = result.bounds[frame.get_instance_id()]
		result.span = maxf(float(result.span), maxf(bounds.size.x, bounds.size.y))
	art_cache[key] = result
	return result

## Process selects rise frames during deployment-selection transitions, holding the front standing pose while deployment hexes remain highlighted.
func _pose() -> Texture2D:
	if unit.t_state == Enum.t_state.UNDEPLOYED:
		if rise_position > 0.0 and (not hand_standing or rise_position < float(art.rise.size())) and not art.rise.is_empty():
			return art.rise[clampi(int(rise_position), 0, art.rise.size() - 1)]
		if hand_standing: return art.standing[0]
	return art["standing" if unit.t_state == Enum.t_state.DEPLOYED else "seated"][0]

## Controller hover arbitration tracks inspection only; leaving the portrait does not cancel deployment posture.
func set_hovered(value: bool) -> void:
	hovered = value and not removing

## HUD refresh calls this with the pending deployment identity; deselection reverses from the current rise frame into sitting.
func set_hand_selected(selected: bool) -> void:
	hand_standing = selected and not removing and unit.t_state == Enum.t_state.UNDEPLOYED and unit.player == Match.active_player

## HUD synchronization removes defeated/replaced portraits with a short fade; old controls stop accepting clicks immediately.
func fade_out() -> void:
	if removing: return
	removing = true
	hovered = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.18)
	tween.tween_callback(queue_free)

## Hand clicks forward identity to the controller; its legal deployment selection determines posture and highlighted hexes together.
func _on_gui_input(event: InputEvent) -> void:
	if removing: return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		accept_event()
		if unit.player == Match.active_player and unit.t_state == Enum.t_state.UNDEPLOYED:
			grab_focus()
		pressed.emit(unit.iun)

## setup() and _process() share the roster rule: defeated units and non-heroes blocked by their owner's hero-first deployment are grey.
## Turn ownership, action balance and temporary tile availability do not grey otherwise playable hand units.
func _is_grey() -> bool:
	if unit.t_state == Enum.t_state.DEFEATED: return true
	var player: Player = Match.players.get(unit.player)
	return unit.t_state == Enum.t_state.UNDEPLOYED and unit.type != Enum.type.HERO and player != null and not player.has_deployed

## Godot plays front-facing stand/sit at 10fps, reversing from the current frame when deployment selection clears.
## Defeat and hero-first deployment restrictions fade greyscale over 180ms; deploying the hero restores remaining hand units' colors.
## Short eased pose blends preserve opacity without affecting rule state or phase waits.
## Greyscale interpolation stays in portrait state: an unset ShaderMaterial override returns null despite the shader's numeric default.
func _process(delta: float) -> void:
	if unit.player != Match.active_player or unit.t_state != Enum.t_state.UNDEPLOYED: hand_standing = false
	rise_position = move_toward(rise_position, float(art.rise.size()) if hand_standing else 0.0, delta * 10.0)
	var next := _pose()
	if next != current:
		previous = current
		current = next
		blend = 0.0
	blend = minf(1.0, blend + delta / BLEND_TIME)
	var portrait_material := material as ShaderMaterial
	greyscale_amount = move_toward(greyscale_amount, 1.0 if _is_grey() else 0.0, delta / 0.18)
	portrait_material.set_shader_parameter("greyscale", greyscale_amount)
	queue_redraw()

## Godot draws the unit once with no square background/border, preserving its authored horizontal pivot instead of recentering each silhouette.
## Atlas-aware shader regions mix the old facing in one draw; native canvas/foot anchors avoid shimmer and opacity pulsing.
func _draw() -> void:
	if current == null: return
	var bounds: Rect2 = art.bounds[current.get_instance_id()]
	var ratio := minf(size.x, size.y) * 0.8 / float(art.span)
	var extent := current.get_size() * ratio
	var destination := Rect2(Vector2((size.x - extent.x) * 0.5, size.y * 0.9 - bounds.end.y * ratio).round(), extent)
	var portrait_material := material as ShaderMaterial
	portrait_material.set_shader_parameter("current_size", current.get_size())
	portrait_material.set_shader_parameter("current_region", BoardCharacter.frame_uv_region(current))
	portrait_material.set_shader_parameter("current_foot", bounds.end.y)
	portrait_material.set_shader_parameter("facing_mix", smoothstep(0.0, 1.0, blend))
	if previous != null and blend < 1.0:
		var old_bounds: Rect2 = art.bounds[previous.get_instance_id()]
		portrait_material.set_shader_parameter("previous_pose", BoardCharacter.frame_sheet(previous))
		portrait_material.set_shader_parameter("previous_region", BoardCharacter.frame_uv_region(previous))
		portrait_material.set_shader_parameter("previous_size", previous.get_size())
		portrait_material.set_shader_parameter("previous_foot", old_bounds.end.y)
	draw_texture_rect(current, destination, false)
