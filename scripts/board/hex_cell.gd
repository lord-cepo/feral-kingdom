class_name HexCell
extends Area2D

signal hovered(coordinate: Vector2i)
signal unhovered(coordinate: Vector2i)
signal bash_unit_hovered(coordinate: Vector2i, unit_id: int)
signal pressed(coordinate: Vector2i)
signal bash_unit_pressed(coordinate: Vector2i, unit_id: int)

## Side-by-side characters are the default; the optional scene setting enables the experimental half-clipped comparison.
@export var bash_slider_enabled := false

const FRAME_DBLUE := preload("res://assets/dark-blue-hex.png")
const FRAME_DRED := preload("res://assets/dark-red-hex.png")
const FRAME_LBLUE := preload("res://assets/light-blue-hex.png")
const FRAME_LRED := preload("res://assets/light-red-hex.png")
const FRAME_GREY := preload("res://assets/grey-hex.png")
const INACTIVE_ART_SHADER := preload("res://assets/shaders/inactive_board_art.gdshader")
const INFO_FONT := preload("res://assets/fonts/hex_info_font.tres")
const BOMB_SCALE := 2.625
const BOMB_ICON := "res://assets/icons/bomb-unlit.png"
## Normal Bomb placement/travel and historical replays share the same target-relative endpoint.
const BOMB_OFFSET: Vector2 = preload("res://scripts/board/board_fire.gd").TARGET_OFFSETS[&"bomb_throw"]
const INFO_FONT_SIZE := 31
const INFO_ROW_SPACER := "[img=1x60]res://assets/icons/info-row-spacer.png[/img]"
@onready var frame := $HexFrame
@onready var unit_figures: Node2D = $UnitFigures
var hex_info: HexInfo
var board_position := Vector2.ZERO
var targetable := false
var displayed_life_rows: Dictionary = {}
var target_gold_frame: Sprite2D
var resolution_gold_frame: Sprite2D
var resolution_gold_tween: Tween
var target_color_tween: Tween
var target_color_amount := 0.0
var target_color_goal := 0.0
var pending_control_texture: Texture2D
var control_color_initialized := false
var control_color_queued_frame := 0
var control_color_overlay: Sprite2D
var control_color_tween: Tween
var control_color_blend := 1.0
var is_hovered := false
var hover_tweens: Array[Tween] = []
var bash_overlays: Array[Control] = []
var bash_click_boxes: Array[PanelContainer] = []
var bash_hover_side := -1
var bash_focus_tween: Tween
var rendered_bash: BashInfo
var arriving_unit_id := -1
var arrival_alpha := 1.0
var info_hover_tween: Tween
## Latest ordinary info by occupant identity, retained through a move's earlier Bash notifications.
var last_unit_info: Dictionary = {}
var focused_unit_id := -1
var bomb_sprite: AnimatedSprite2D
var bomb_is_lit := false
var bomb_blast_overlays := 0
var bomb_throw_elapsed := -1.0
var bomb_throw_origin: HexCell
var thrown_bomb: BombInfo
var displacement_hidden_units: Array[int] = []
var bash_departure_offsets: Dictionary = {}
var bash_exit_offsets: Dictionary = {}
var bash_exit_progress := 1.0
var bash_exit_tween: Tween

## Connects pointer handling and paints the current tile after the scene enters the tree.
## Godot calls this after setup() has received its HexInfo.
func _ready() -> void:
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	refresh()

## Binds this reusable board cell to one Match tile before it enters the scene tree.
## GuerraBoard._add_cell() calls this and then positions the cell; hex info starts 20px higher with space for 48px icons.
## Every row includes the same transparent 60px layout spacer; -16 line/-14 paragraph separation tightens the shared pitch.
## The right-side bomb sprite caches its ignition frames.
func setup(info: HexInfo) -> void:
	hex_info = info
	name = "HexCell_%d_%d" % [info.coordinate.x, info.coordinate.y]
	$CoordinateLabel.size = Vector2(240, 260)
	$CoordinateLabel.position = Vector2(-120, -102)
	$CoordinateLabel.z_index = 3
	$CoordinateLabel.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	$CoordinateLabel.add_theme_constant_override("line_separation", -16)
	$CoordinateLabel.add_theme_constant_override("paragraph_separation", -14)
	$CoordinateLabel.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	$CoordinateLabel.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	$HexFrame.z_index = 2
	$CoordinateLabel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$CoordinateLabel.add_theme_font_override("normal_font", INFO_FONT)
	$CoordinateLabel.add_theme_font_size_override("normal_font_size", INFO_FONT_SIZE)
	$CoordinateLabel.add_theme_color_override("font_color", Color("#fff4d8"))
	$CoordinateLabel.add_theme_color_override("font_shadow_color", Color(0.12, 0.08, 0.04, 0.92))
	$CoordinateLabel.add_theme_constant_override("shadow_offset_x", 1)
	$CoordinateLabel.add_theme_constant_override("shadow_offset_y", 1)
	$CoordinateLabel.add_theme_constant_override("outline_size", 4)
	$CoordinateLabel.add_theme_color_override("font_outline_color", Color("#111827"))
	_setup_bomb_sprite()

## setup() creates an 84px right-side bomb sprite (1.5x its previous size), without a board value label; damage/P stays in hover counters.
## The nine-frame ignition loops continuously while a pending explosion exists, independently of combat timing.
## A static unlit body beneath the animation prevents transparent source frames from making the placed object blink out.
func _setup_bomb_sprite() -> void:
	bomb_sprite = AnimatedSprite2D.new()
	bomb_sprite.position = BOMB_OFFSET
	bomb_sprite.scale = Vector2.ONE * BOMB_SCALE
	bomb_sprite.z_index = 5
	bomb_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var frames := SpriteFrames.new()
	frames.rename_animation(&"default", &"unlit")
	frames.add_frame(&"unlit", load(BOMB_ICON))
	frames.add_animation(&"ignite")
	frames.set_animation_loop(&"ignite", true)
	frames.set_animation_speed(&"ignite", 9.0)
	for index in 9:
		frames.add_frame(&"ignite", load("res://assets/icons/bomb-ignite/frame_%d.png" % index))
	bomb_sprite.sprite_frames = frames
	var body := Sprite2D.new()
	body.name = "PersistentBombBody"
	body.texture = load(BOMB_ICON)
	body.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	body.z_index = -1
	bomb_sprite.add_child(body)
	add_child(bomb_sprite)
	bomb_sprite.visible = false

## Stores the camera-independent tile center and reapplies its current targetable offset.
## GuerraBoard calls this after creating a cell and whenever it recenters the map.
func set_board_position(value: Vector2) -> void:
	board_position = value
	_apply_target_transform()

## Refreshes the pixel lower rim, right-side bomb marker, life/modifier/action rows, portraits, hover sway, and target scale.
## GuerraBoard calls this after Match/selection changes; an unchanged Bash retains its animated nodes and focus.
## Current control selects red for Player 1 and blue for Player 2; starting/front use dark rims, intermediate light, neutral white.
## Hearts in life rows use owner-specific PixelLab images; actions share GameIcons.
## The scene keeps the original canvas alignment, raised 44 world pixels to clear character feet; idle rims use 40% opacity and selectable rims use steady gold; control rules are unchanged.
## UnitFigures sits 26 world pixels higher with the rim; walking overlays share this offset.
## Retains ordinary characters and forwards the selected identity for cursor-facing; arrival visuals stay cosmetic.
## Life rows use Board.life_number so damage appears during Slash rather than at authoritative mutation time.
## Activity is shown through figure color rather than a Stun counter row in compact hex info.
## Any live-Bash-to-ordinary transition captures old side offsets and recenters surviving figures/info independently of the action causing it.
## Regional rim colors queue separately from rules and settle only after finite Board presentations; target highlights remain immediate.
func refresh(highlighted: bool = false, selected_unit_id: int = -1) -> void:
	if hex_info == null: return
	focused_unit_id = selected_unit_id
	targetable = highlighted
	_apply_target_transform()
	var dark_region := hex_info.region in [Enum.region.STARTING, Enum.region.FRONT]
	var next_texture: Texture2D = FRAME_GREY
	match hex_info.control:
		Enum.control.P1: next_texture = FRAME_DRED if dark_region else FRAME_LRED
		Enum.control.P2: next_texture = FRAME_DBLUE if dark_region else FRAME_LBLUE
	if not control_color_initialized:
		frame.texture = next_texture
		control_color_initialized = true
	elif pending_control_texture != next_texture:
		pending_control_texture = next_texture
		control_color_queued_frame = Engine.get_process_frames()
	_refresh_target_color()
	_refresh_bomb_indicator()
	var units := _current_units()
	var bash := _live_bash(units)
	if rendered_bash != null and bash == null:
		_begin_bash_exit(units)
	elif bash != null and bash != rendered_bash:
		if bash_exit_tween != null: bash_exit_tween.kill()
		bash_exit_offsets.clear()
		bash_exit_progress = 1.0
	if bash != null and bash == rendered_bash:
		_update_bash_info()
		set_arrival(arriving_unit_id, arrival_alpha)
		return
	_stop_hover_tweens()
	for child in unit_figures.get_children():
		if child is BoardCharacter and bash == null and units.any(func(unit: UnitInfo) -> bool: return unit.iun == child.unit_id): continue
		unit_figures.remove_child(child)
		child.queue_free()
	_clear_bash_overlays()
	bash_hover_side = -1
	displayed_life_rows.clear()
	var life_lines: PackedStringArray = []
	var modifier_lines: PackedStringArray = []
	var effect_lines: PackedStringArray = []
	if bash != null:
		_render_bash(bash)
		set_arrival(arriving_unit_id, arrival_alpha)
		return
	bash_hover_side = -1
	var remaining_effect_rows := 3
	for index in units.size():
		var unit := units[index]
		var owner_color := "#ef4444" if unit.player == 1 else "#3b82f6"
		var life_line := _life_row(unit, owner_color)
		displayed_life_rows[unit.iun] = life_line
		life_lines.append(life_line)
		var physical_text := ("+" if unit.physical_modifier >= 0 else "") + str(unit.physical_modifier)
		var modifier_line := "[font_size=%d][color=%s]%s[/color]" % [INFO_FONT_SIZE, owner_color, physical_text]
		if unit.magical_modifier != 0:
			var magical_text := ("+" if unit.magical_modifier > 0 else "") + str(unit.magical_modifier)
			modifier_line += "[color=#c084fc]%s[/color]" % magical_text
		modifier_lines.append(modifier_line + "[/font_size]")
		var summary := _compact_effect_summary(unit, remaining_effect_rows)
		if not summary.is_empty():
			effect_lines.append("[font_size=%d][color=#fff4d8]%s[/color][/font_size]" % [INFO_FONT_SIZE, summary])
			remaining_effect_rows -= summary.count("\n") + 1
		_add_unit_figure(unit, index, units.size(), unit.iun == selected_unit_id)
	var contents := life_lines
	contents.append_array(modifier_lines)
	contents.append_array(effect_lines)
	$CoordinateLabel.text = _fixed_info_rows("\n".join(contents))
	for unit in units: last_unit_info[unit.iun] = $CoordinateLabel.text
	_apply_bash_exit_progress(bash_exit_progress)
	set_arrival(arriving_unit_id, arrival_alpha)
	if is_hovered: _start_hover_oscillation()

## Ordinary refresh(), Bash stats and Bash details use the same invisible row strut, as tall as the largest icon.
## Text-only, heart, Stun and Fire lines therefore share line metrics; walking ghosts retain the formatted BBCode unchanged.
func _fixed_info_rows(text: String) -> String:
	if text.is_empty(): return ""
	var rows := text.split("\n")
	for index in rows.size():
		rows[index] = INFO_ROW_SPACER + rows[index]
	return "\n".join(rows)

## Hides a travelling unit's stationary duplicate and blends destination info as its overlay approaches.
## Board's movement presenter calls every frame and refresh() reapplies the state after rebuilding portraits.
## Bash arrival uses self_modulate so the slider's independent focus/opacity tween is preserved rather than overwritten.
## Displacement overlays keep their stationary recipient hidden across repaint while its sliding copy is shown.
func set_arrival(identifier: int, alpha: float) -> void:
	arriving_unit_id = identifier
	arrival_alpha = alpha
	for figure in unit_figures.get_children():
		var figure_id := int(figure.get_meta("unit_id", -1))
		figure.visible = (identifier < 0 or figure_id != identifier) and figure_id not in displacement_hidden_units
	$CoordinateLabel.modulate.a = alpha * bash_exit_progress * (0.35 if is_hovered and _has_character() else 1.0)
	for overlay in bash_overlays:
		if identifier < 0: overlay.self_modulate.a = 1.0
		elif int(overlay.get_meta("unit_id", -1)) == identifier: overlay.self_modulate.a = alpha

## board_displacement.gd hides/restores the stationary target without interfering with walking's independent arrival visibility.
## refresh() reapplies this state through set_arrival(), including retained Bash figures and ordinary characters.
func set_displacement_hidden(identifier: int, hiding: bool) -> void:
	if hiding and identifier not in displacement_hidden_units: displacement_hidden_units.append(identifier)
	elif not hiding: displacement_hidden_units.erase(identifier)
	set_arrival(arriving_unit_id, arrival_alpha)

## Board._advance_walk queries the incoming attacker's final local offset on every frame.
## Red arrives on the left and blue on the right. Only a live side-by-side Bash adds an offset; ordinary destinations and the optional slider stay centered.
func bash_arrival_offset(identifier: int) -> Vector2:
	if bash_slider_enabled or rendered_bash == null or rendered_bash.resolved: return Vector2.ZERO
	if rendered_bash.attacker_id != identifier: return Vector2.ZERO
	var unit := Match.get_unit(identifier)
	if unit == null: return Vector2.ZERO
	return Vector2(-65.0 if unit.player == 1 else 65.0, 0.0)

## Board's walk presenter moves the defender from its original center to its Bash side during the final step.
## Repeated refreshes preserve this position; _finish_walk supplies 1 to settle interrupted arrivals as well.
func set_bash_approach(identifier: int, progress: float) -> void:
	if bash_arrival_offset(identifier) == Vector2.ZERO: return
	for figure in unit_figures.get_children():
		if figure is BoardCharacter and figure.unit_id == rendered_bash.defender_id:
			figure.position.x = -bash_arrival_offset(identifier).x * smoothstep(0.0, 1.0, progress)

## refresh() notices a Bash ending for any reason, capturing old side poses before the ordinary layout replaces them.
## Surviving figures recenter and ordinary info fades in over 0.8s; movement presenters consume the departed side offset separately.
func _begin_bash_exit(units: Array[UnitInfo]) -> void:
	if bash_exit_tween != null: bash_exit_tween.kill()
	bash_exit_offsets.clear()
	bash_departure_offsets.clear()
	for figure in unit_figures.get_children():
		var identifier := int(figure.get_meta("unit_id", -1))
		var unit := Match.get_unit(identifier)
		if unit == null: continue
		var offset := Vector2(figure.position.x, 0) if not bash_slider_enabled else Vector2.ZERO
		if units.has(unit): bash_exit_offsets[identifier] = offset
		else: bash_departure_offsets[identifier] = {"unit": unit, "offset": offset, "destination": unit.ihx}
	bash_exit_progress = 0.0 if not units.is_empty() else 1.0
	if units.is_empty(): return
	bash_exit_tween = create_tween()
	bash_exit_tween.tween_method(_apply_bash_exit_progress, 0.0, 1.0, 0.8)

## Walking and forced-displacement presenters query their old Bash cell once for the departing figure's historical side.
## Instance validation prevents a stale match/reset record affecting a replacement unit with the same ID.
func take_bash_departure_offset(identifier: int) -> Vector2:
	var saved: Dictionary = bash_departure_offsets.get(identifier, {})
	bash_departure_offsets.erase(identifier)
	if saved.is_empty():
		for figure in unit_figures.get_children():
			if int(figure.get_meta("unit_id", -1)) == identifier:
				var base: Vector2 = figure.get_meta("ordinary_base_position", figure.position)
				return figure.position - base
		return Vector2.ZERO
	if saved.unit != Match.get_unit(identifier) or saved.unit.ihx != saved.destination: return Vector2.ZERO
	return saved.offset

## The Bash-exit tween and refresh() apply the same progress, preserving motion across unrelated repaints.
## Only units still on this ordinary tile shift; a new Bash owns its own layout and stops this transition.
func _apply_bash_exit_progress(progress: float) -> void:
	bash_exit_progress = progress
	if rendered_bash != null: return
	for figure in unit_figures.get_children():
		var identifier := int(figure.get_meta("unit_id", -1))
		if not bash_exit_offsets.has(identifier): continue
		var base: Vector2 = figure.get_meta("ordinary_base_position", figure.position)
		figure.position = base + Vector2(bash_exit_offsets[identifier]) * (1.0 - smoothstep(0.0, 1.0, progress))
	$CoordinateLabel.modulate.a = arrival_alpha * progress * (0.35 if is_hovered and _has_character() else 1.0)

## Reports whether this cell contains the prototype character; hover fading applies only to that presentation.
func _has_character() -> bool:
	for figure in unit_figures.get_children():
		if figure is BoardCharacter: return true
	return false

## Starts the character's turn-south/action/sit sequence without affecting selection, costs or timing.
## Board._on_action_presentation calls after repaint; an interrupted travelling overlay may supply its current facing.
func play_character_action(identifier: int, travel_sector: int = -1) -> void:
	for figure in unit_figures.get_children():
		if figure is BoardCharacter and figure.unit_id == identifier:
			if travel_sector >= 0: figure.current_sector = travel_sector
			figure.play_action()

## Board._on_action_presentation() calls after committed Deploy; previous-turn action replay can request the same cosmetic sequence.
## Deployment uses the grounded south standing pose, a downward fade-in and reversed stand-up sit-down; refreshes do not replay it.
func play_character_deploy(identifier: int) -> void:
	for figure in unit_figures.get_children():
		if figure is BoardCharacter and figure.unit_id == identifier: figure.play_deploy()

## Board._finish_walk() calls on genuine arrival before revealing the stationary figure.
## Transfers the last travel facing to the retained/new Bash character so it turns south and reverses stand-up to sit.
func finish_character_walk(identifier: int, sector: int) -> void:
	for figure in unit_figures.get_children():
		if figure is BoardCharacter and figure.unit_id == identifier: figure.finish_walk(sector)

## Blends ordinary hex info while keeping it readable; character hover callbacks call this without hiding the label.
## Uses the same shared 0.18s duration as Bash info and character opacity, with no extra reset pause.
func _fade_character_info(hovering: bool) -> void:
	if not _has_character(): return
	if info_hover_tween != null: info_hover_tween.kill()
	info_hover_tween = create_tween()
	info_hover_tween.tween_property($CoordinateLabel, "modulate:a", arrival_alpha * (0.35 if hovering else 1.0), BoardCharacter.HOVER_FADE_DURATION)

## Updates the independent right-side marker before refresh() can return for a retained Bash.
## Inert bombs come from Match; a pending blast's captured center identifies a lit bomb,
## not its neighboring damage tiles. Unlit uses the static object; lit bombs loop ignition until resolved or removed.
## Repaints preserve the current animation frame rather than restarting the loop.
## The sprite disappears when neither record remains; animation never delays the rules runner.
## An active Bomb Throw retains its travel/fade across repaint; removed or ignited bombs cancel that cosmetic travel.
## Radial ignition overlays temporarily replace this marker, including across synchronous rule repaints.
func _refresh_bomb_indicator() -> void:
	var bomb := Match.bomb_at(hex_info.hex_id)
	var lit := false
	var visible_bomb := bomb != null
	for attack: CannonAttack in Match.pending_cannon_attacks:
		if not attack.explosion or attack.resolved or attack.bomb_hex != hex_info.hex_id: continue
		lit = true
		visible_bomb = true
		break
	if bomb_sprite == null: return
	bomb_sprite.visible = visible_bomb and bomb_blast_overlays == 0
	if lit and not bomb_is_lit:
		bomb_sprite.play(&"ignite")
	elif not lit:
		bomb_sprite.play(&"unlit")
	bomb_is_lit = lit
	if bomb_throw_elapsed >= 0.0 and (bomb != thrown_bomb or lit):
		bomb_throw_elapsed = -1.0
		bomb_throw_origin = null
		thrown_bomb = null
		bomb_sprite.position = BOMB_OFFSET
		bomb_sprite.modulate.a = 1.0

## Board._on_action_presentation calls after repaint for committed Bomb Throw, including merges.
## Moves the existing marker, avoiding a duplicate at the destination; the authoritative bomb is already placed.
func play_bomb_throw(origin_cell: HexCell) -> void:
	thrown_bomb = Match.bomb_at(hex_info.hex_id)
	if thrown_bomb == null or bomb_is_lit: return
	bomb_throw_origin = origin_cell
	bomb_throw_elapsed = 0.0
	_process(0.0)

## Godot advances Bomb Throw with Fire's 0.65s eased travel; values/P stay in hover counters.
## The bomb fades toward 80% opacity only outside its origin hex; the settled marker persists normally.
## Resolving/defusing/igniting during travel is handled by _refresh_bomb_indicator without delaying rules.
## The destination uses BOMB_OFFSET, shared with historical Bomb Throw replay.
## Updates retained life text before the throw-only early return so Slash-held values and per-number pulses advance on stationary cells too.
## Queued regional colors wait a frame for synchronous action presenters to register, then wait for the shared finite-animation barrier.
func _process(delta: float) -> void:
	_update_control_color()
	_refresh_life_numbers()
	if bomb_throw_elapsed < 0.0 or not is_instance_valid(bomb_throw_origin): return
	bomb_throw_elapsed += delta
	var start := to_local(bomb_throw_origin.global_position)
	var progress := clampf(bomb_throw_elapsed / 0.65, 0.0, 1.0)
	bomb_sprite.position = start.lerp(BOMB_OFFSET, smoothstep(0.0, 1.0, progress))
	var offset := bomb_sprite.position - start
	var outside := absf(offset.y) > 86.66667 or absf(offset.x) + 0.75 * absf(offset.y) > 130.0
	bomb_sprite.modulate.a = 0.8 * minf(progress * 1.8, 1.0 if outside else 0.95)
	if bomb_throw_elapsed >= 0.65:
		bomb_throw_elapsed = -1.0
		bomb_throw_origin = null
		thrown_bomb = null

## Returns newline-separated action rows within the space left after status rows.
## refresh() calls it below life and modifier rows; Stun state no longer consumes a compact action row.
## Reads presentation-only board trigger cues to color the Trigger label yellow while an undismissed cue is active.
func _compact_effect_summary(unit: UnitInfo, max_rows: int = 3) -> String:
	var labels: PackedStringArray = []
	for effect in unit.effects:
		if effect == null or effect.implicit or not effect.consequence is Effect.ConsequencePhrase: continue
		var phrase := effect.consequence as Effect.ConsequencePhrase
		var label := _compact_effect_label(phrase, unit)
		if not labels.has(label): labels.append(label)
	if not unit.trigger_effects.is_empty():
		var owner_board := get_parent().get_parent() as GuerraBoard if get_parent() != null else null
		var highlighted := owner_board != null and not owner_board.highlighted_triggers(unit).is_empty()
		labels.append("[color=#ffd84a]Trigger[/color]" if highlighted else "Trigger")
	if max_rows <= 0: return ""
	if labels.size() > max_rows:
		return "%s\n+%d" % ["\n".join(labels.slice(0, max_rows - 1)), labels.size() - max_rows + 1]
	return "\n".join(labels)

## Formats an authored action with its key magnitude and range for the small board label.
## _compact_effect_summary() calls for each printed action; chosen amounts retain X, and inline hearts use that unit's owner.
func _compact_effect_label(phrase: Effect.ConsequencePhrase, unit: UnitInfo) -> String:
	var verb := phrase.verb
	var name := String(verb.name).replace("_", " ").capitalize()
	var ctx := RuleContext.new(TargetRef.unit(unit.iun))
	ctx.subject = ctx.source
	var params := verb.bound_to(ctx).user_params
	var action_range := EffectText.selector_range(phrase.target) + unit.ability_bonus(verb).y
	var markers := _action_sticker_markers(phrase)
	if verb.name == &"grant_action_values":
		return ("[lb]A[rb] " if phrase.action_free else "") + EffectText._action_grant(params[0], params[1])
	if not verb.user_params.is_empty() and verb.user_params[0] is RuleNumber:
		return "%s%s%s" % [verb.user_params[0].symbol, markers, _action_icon(verb.name, unit.player)]
	if verb.name in [&"bow", &"fire", &"cannon", &"bomb_throw", &"gore", &"mend", &"stun"]:
		var values: Array[int] = [int(params[0]) if not params.is_empty() else 0, action_range]
		if verb.name != &"fire" and params.size() >= 2: values[1] = int(params[1])
		values = unit.effective_action_values(verb.name, values)
		return "%s%s%s%s" % [EffectText.action_value(values[0], int(verb.user_params[0])), markers, _action_icon(verb.name, unit.player), EffectText.action_value(values[1], int(verb.user_params[1]) if verb.name != &"fire" else EffectText.selector_range(phrase.target))]
	if verb.name in [&"push", &"pull", &"push_bomb", &"pull_bomb"] and params.size() >= 2:
		var printed_values: Array[int] = [int(params[0]), int(params[1])]
		var values: Array[int] = unit.effective_action_values(verb.name, printed_values)
		return "%d%s%s%d" % [values[0], markers, _action_icon(verb.name, unit.player), values[1]]
	if verb.name in [&"shield", &"mshield"] and not params.is_empty():
		return "%d%s%s" % [int(params[0]), markers, _action_icon(verb.name, unit.player)]
	if verb.name in [&"move", &"fly"] and not params.is_empty():
		return "%s%s%s" % [markers, _action_icon(verb.name, unit.player), EffectText.action_value(int(params[0]), int(verb.user_params[0]))]
	if verb.name == &"upgrade_bow" and params.size() >= 2:
		return "%+d%s%+d" % [int(params[0]), _action_icon(&"bow", unit.player), int(params[1])]
	return "%s%s%d" % [markers, _action_icon(verb.name, unit.player), action_range] if action_range >= 0 else "%s%s" % [_action_icon(verb.name, unit.player), name]

## Converts attached Guerra action stickers into the same compact letter prefixes used in its board labels.
## _compact_effect_label() calls this before formatting an action's amount, icon, and reach.
func _action_sticker_markers(phrase: Effect.ConsequencePhrase) -> String:
	var markers := ""
	if phrase.has_sticker(ActionSticker.Kind.INSTANT): markers += "F"
	if phrase.has_sticker(ActionSticker.Kind.PIERCE): markers += "P"
	if phrase.has_sticker(ActionSticker.Kind.TIRELESS): markers += "T"
	if phrase.has_sticker(ActionSticker.Kind.ACTION_FREE): markers += "A"
	return markers

## Returns enlarged 48px PixelLab inline icons for authored actions, retaining other existing glyphs.
## _compact_effect_label() calls this for authored board actions.
func _action_icon(action: StringName, owner: int = 1) -> String:
	var icon := GameIcons.bb(action, owner, 48)
	if not icon.is_empty(): return icon
	return GameIcons.fallback_glyph(action)

## Board target picking uses the same red-left/blue-right halves as Bash hover and figure rendering.
## Returns the exact current Bash participant, including inactive units, or -1 when this is not a live two-unit Bash.
## Callers must validate that identity against their own legal candidates; never substitute the other side.
func bash_unit_at_position(local_point: Vector2) -> int:
	var bash := _live_bash(_current_units())
	if bash == null: return -1
	var owner := 1 if local_point.x < 0.0 else 2
	for identifier in [bash.attacker_id, bash.defender_id]:
		var unit := Match.get_unit(identifier)
		if unit != null and unit.player == owner: return identifier
	return -1

## Finds an unresolved Bash whose exact two deployed participants still occupy this hex.
## refresh() calls this before ordinary unit rendering so dodged/stale Bash records never split figures.
func _live_bash(units: Array[UnitInfo]) -> BashInfo:
	for bash in Match.bashes:
		if bash == null or bash.resolved or bash.target_hex != hex_info.hex_id: continue
		var attacker := Match.get_unit(bash.attacker_id)
		var defender := Match.get_unit(bash.defender_id)
		if attacker == null or defender == null: continue
		if attacker.t_state != Enum.t_state.DEPLOYED or defender.t_state != Enum.t_state.DEPLOYED: continue
		if attacker.ihx != hex_info.hex_id or defender.ihx != hex_info.hex_id: continue
		if units.has(attacker) and units.has(defender): return bash
	return null

## Draws red Player 1-left/blue Player 2-right characters side by side, with optional shader-clipped centered halves.
## refresh() calls this for new encounters; build the typed participant array directly, then retain only the completed display.
## Board's walking presenter adjusts the incoming attacker and defender positions during approach; rules remain unchanged.
## Each participant owns a separate stable click box; its explicit identity is shared by hover, replay and rule selection.
func _render_bash(bash: BashInfo) -> void:
	var attacker := Match.get_unit(bash.attacker_id)
	var defender := Match.get_unit(bash.defender_id)
	if attacker == null or defender == null: return
	var side_units: Array[UnitInfo] = [attacker, defender]
	if attacker.player != 1: side_units.reverse()
	for side in 2:
		var unit := side_units[side]
		if unit == null: continue
		_add_bash_click_box(unit, side)
		if BoardCharacter.supports(unit):
			_add_unit_figure(unit, side, 2, false)
			if bash_slider_enabled:
				var character := unit_figures.get_node("UnitFigure_%d" % unit.iun) as BoardCharacter
				character.position.x = 0.0
				(character.material as ShaderMaterial).set_shader_parameter("bash_side", -1 if side == 0 else 1)
			_add_bash_stats(unit, side)
			_add_bash_details(unit, side)
			if not bash_slider_enabled:
				get_node("BashDetails_%s" % ("Left" if side == 0 else "Right")).modulate.a = 1.0
			continue
		var figure := Sprite2D.new()
		figure.name = "BashFigure_%s" % ("Left" if side == 0 else "Right")
		figure.centered = true
		var art_path := BoardCharacter.card_art_path(unit)
		figure.texture = load(art_path) if not art_path.is_empty() else null
		if figure.texture != null:
			figure.scale = Vector2(260.0 / figure.texture.get_width(), 260.0 * 2.0 / 3.0 / figure.texture.get_height())
		figure.z_index = 1
		var art_material := ShaderMaterial.new()
		art_material.shader = INACTIVE_ART_SHADER
		art_material.set_shader_parameter("inactive", not unit.active)
		art_material.set_shader_parameter("bash_mode", true)
		art_material.set_shader_parameter("target_aspect", 1.5)
		art_material.set_shader_parameter("hover_angle_degrees", 0.0)
		art_material.set_shader_parameter("bash_side", -1 if side == 0 else 1)
		art_material.set_shader_parameter("bash_reveal", 0.0)
		art_material.set_shader_parameter("bash_opacity", 1.0)
		figure.material = art_material
		figure.set_meta("unit_id", unit.iun)
		figure.set_meta("hover_eligible", unit.active and unit.player == Match.active_player)
		unit_figures.add_child(figure)
		_add_bash_stats(unit, side)
		_add_bash_details(unit, side)
	rendered_bash = bash
	$CoordinateLabel.text = ""
	if is_hovered:
		var local_mouse := get_local_mouse_position()
		_set_bash_hover_side(0 if local_mouse.x < 0.0 else 1)
		_start_hover_oscillation()

## _render_bash() creates invisible disjoint red-left/blue-right hitboxes, retained across refreshes without visible outlines.
## GUI input claims only that participant's identity, preventing another occupant's replay from stealing a defender click.
func _add_bash_click_box(unit: UnitInfo, side: int) -> void:
	var box := PanelContainer.new()
	box.name = "BashClickBox_%d" % unit.iun
	box.position = Vector2(-124 if side == 0 else 2, -140)
	box.size = Vector2(122, 220)
	box.z_index = 4
	box.mouse_filter = Control.MOUSE_FILTER_STOP
	box.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var style := StyleBoxFlat.new()
	style.bg_color = Color.TRANSPARENT
	style.border_color = Color.TRANSPARENT
	style.set_border_width_all(1)
	style.set_corner_radius_all(5)
	box.add_theme_stylebox_override("panel", style)
	box.self_modulate.a = 0.15
	box.set_meta("unit_id", unit.iun)
	box.mouse_entered.connect(func() -> void:
		if not is_hovered: _on_mouse_entered()
		_set_bash_hover_side(side)
		_tween_bash_box(box, 0.7))
	box.mouse_exited.connect(func() -> void:
		_tween_bash_box(box, 0.15)
		_leave_bash_boxes.call_deferred())
	box.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			box.accept_event()
			if _live_bash(_current_units()) != null: bash_unit_pressed.emit(hex_info.coordinate, unit.iun))
	add_child(box)
	bash_click_boxes.append(box)

## Box hover callbacks ease from the visible border alpha, replacing an unfinished tween without snapping.
func _tween_bash_box(box: PanelContainer, alpha: float) -> void:
	var previous: Variant = box.get_meta("hover_tween", null)
	if previous is Tween and previous.is_valid(): previous.kill()
	var tween := box.create_tween()
	box.set_meta("hover_tween", tween)
	tween.tween_property(box, "self_modulate:a", alpha, BoardCharacter.HOVER_FADE_DURATION)

## Deferred box exit ignores transitions into the adjacent participant box, preserving the normal Bash focus timing.
func _leave_bash_boxes() -> void:
	for box in bash_click_boxes:
		if is_instance_valid(box) and Rect2(Vector2.ZERO, box.size).has_point(box.get_local_mouse_position()): return
	if is_hovered: _on_mouse_exited()

## Refreshes the retained Bash portraits and live labels without restarting clipping, fades, or side-change timers.
## refresh() calls this for the same encounter after rule or selection changes; only activity changes restart sway.
## Labels retain red-left/blue-right ownership. Selected character participants follow the cursor even while Bash keeps its existing portrait nodes.
## Character activity stays under BoardCharacter's delayed greyscale blend; only legacy portraits use the boolean inactive uniform.
func _update_bash_info() -> void:
	var restart_sway := false
	for figure: Sprite2D in unit_figures.get_children():
		var unit := Match.get_unit(int(figure.get_meta("unit_id")))
		if figure is BoardCharacter: figure.set_follow_pointer(unit.iun == focused_unit_id)
		var material := figure.material as ShaderMaterial
		if material != null and not figure is BoardCharacter: material.set_shader_parameter("inactive", not unit.active)
		var eligible := unit.active and unit.player == Match.active_player
		if eligible != bool(figure.get_meta("hover_eligible")): restart_sway = true
		figure.set_meta("hover_eligible", eligible)
		var suffix := "Left" if unit.player == 1 else "Right"
		(get_node("BashStats_" + suffix) as RichTextLabel).text = _bash_stats_text(unit)
		(get_node("BashDetails_" + suffix) as RichTextLabel).text = _bash_card_details(unit)
	if restart_sway:
		_settle_hover_oscillation()
		if is_hovered: _start_hover_oscillation()
	if is_hovered:
		_set_bash_hover_side(0 if get_local_mouse_position().x < 0.0 else 1)

## Adds one participant's actual-life and centered physical/magic pair at the first two hex rows.
## _render_bash() calls it in player-side order; focus motion slides it horizontally without changing its Y position.
## Unit metadata lets the movement presenter fade only the arriving participant's labels.
## Rows sit 20px higher with nearest-filtered icons and shared -16 line/-14 paragraph separation.
## Each 120px column shares its horizontal center with that participant's action-info lines.
func _add_bash_stats(unit: UnitInfo, side: int) -> void:
	var stat := RichTextLabel.new()
	stat.name = "BashStats_%s" % ("Left" if side == 0 else "Right")
	stat.set_meta("unit_id", unit.iun)
	stat.bbcode_enabled = true
	stat.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	stat.add_theme_constant_override("line_separation", -16)
	stat.add_theme_constant_override("paragraph_separation", -14)
	stat.fit_content = false
	stat.scroll_active = false
	stat.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stat.size = Vector2(120, 100)
	stat.position = Vector2(-120 if side == 0 else 0, -98)
	stat.z_index = 4
	stat.add_theme_font_override("normal_font", INFO_FONT)
	stat.add_theme_font_size_override("normal_font_size", INFO_FONT_SIZE)
	stat.add_theme_color_override("default_color", Color("#fff4d8"))
	stat.add_theme_color_override("font_outline_color", Color("#111827"))
	stat.add_theme_constant_override("outline_size", 5)
	stat.text = _bash_stats_text(unit)
	add_child(stat)
	bash_overlays.append(stat)

## Board supplies Slash-timed values and one-second heart pulses after either life value increases; ordinary rows retain owner colors.
func _life_row(unit: UnitInfo, color: String) -> String:
	var owner_board := get_parent().get_parent() as GuerraBoard
	return "[color=%s]%s %s %s[/color]" % [color, owner_board.life_number(unit), owner_board.life_heart(unit), owner_board.life_number(unit, true)]

## Godot's cell process updates only life text, preserving portrait/selection/hover animations and avoiding a full repaint for each pulse frame.
func _refresh_life_numbers() -> void:
	if hex_info == null: return
	for id in displayed_life_rows:
		var unit := Match.get_unit(id)
		if unit == null: continue
		var next := _life_row(unit, "#ef4444" if unit.player == 1 else "#3b82f6")
		if next != displayed_life_rows[id]:
			$CoordinateLabel.text = $CoordinateLabel.text.replace(displayed_life_rows[id], next)
			displayed_life_rows[id] = next
	for overlay in bash_overlays:
		if overlay is RichTextLabel and overlay.name.begins_with("BashStats_"):
			var unit := Match.get_unit(int(overlay.get_meta("unit_id", -1)))
			if unit != null: overlay.text = _bash_stats_text(unit)

## Formats signed physical and optional purple magic as one centered row below actual life, as in Guerra JS.
## _add_bash_stats() and _update_bash_info() share owner-colored hearts and the same fixed row metrics as ordinary hex info.
## Current life precedes the heart, matching ordinary rows; Board.life_number holds and pulses it on the Slash beat.
## Board.life_heart shares the same one-second gain pulse for either participant's actual or maximum life increase.
func _bash_stats_text(unit: UnitInfo) -> String:
	var owner_color := "#ef7770" if unit.player == 1 else "#6da9ee"
	var modifier := "[color=%s]%+d[/color]" % [owner_color, unit.physical_modifier]
	if unit.magical_modifier != 0:
		modifier += "[color=#c084fc]%+d[/color]" % unit.magical_modifier
	var owner_board := get_parent().get_parent() as GuerraBoard
	var rows := "[color=%s]%s %s[/color]\n%s" % [owner_color, owner_board.life_number(unit), owner_board.life_heart(unit), modifier]
	return "[center]%s[/center]" % _fixed_info_rows(rows)

## Adds the usual three compact hex-info rows for one Bash side, hidden until its portrait is hovered.
## _render_bash() creates it for each participant and _animate_bash_focus() fades in only the focused card's rows.
## Slider characters share full-width focused details; the comparison side-by-side mode retains narrow per-unit details at rest.
## Rows sit 20px higher with nearest-filtered icons and shared -16 line/-14 paragraph separation.
func _add_bash_details(unit: UnitInfo, side: int) -> void:
	var details := RichTextLabel.new()
	details.name = "BashDetails_%s" % ("Left" if side == 0 else "Right")
	details.set_meta("unit_id", unit.iun)
	details.bbcode_enabled = true
	details.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	details.add_theme_constant_override("line_separation", -16)
	details.add_theme_constant_override("paragraph_separation", -14)
	details.fit_content = false
	details.scroll_active = false
	details.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	details.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	details.mouse_filter = Control.MOUSE_FILTER_IGNORE
	details.size = Vector2(240, 140)
	details.position = Vector2(-120, -36)
	if BoardCharacter.supports(unit) and not bash_slider_enabled:
		details.size.x = 120
		details.position.x = -120 if side == 0 else 0
	details.z_index = 4
	details.add_theme_font_override("normal_font", INFO_FONT)
	details.add_theme_font_size_override("normal_font_size", INFO_FONT_SIZE)
	details.add_theme_color_override("default_color", Color("#fff4d8"))
	details.add_theme_color_override("font_shadow_color", Color(0.12, 0.08, 0.04, 0.92))
	details.add_theme_constant_override("shadow_offset_x", 1)
	details.add_theme_constant_override("shadow_offset_y", 1)
	details.add_theme_constant_override("outline_size", 4)
	details.add_theme_color_override("font_outline_color", Color("#111827"))
	details.text = _bash_card_details(unit)
	details.modulate.a = 0.0
	add_child(details)
	bash_overlays.append(details)

## Formats up to three status/action rows beneath the separate Bash life/modifier label, without blank-row padding.
## _add_bash_details() and _update_bash_info() use this text; the dedicated label fixes its vertical placement.
## Stun counter rows are omitted here; the same transparent strut keeps action spacing identical to ordinary hex info.
func _bash_card_details(unit: UnitInfo) -> String:
	var rows := PackedStringArray()
	var remaining_rows := 3
	var actions := _compact_effect_summary(unit, remaining_rows)
	if not actions.is_empty(): rows.append_array(actions.split("\n"))
	if rows.size() > 3: rows = rows.slice(0, 3)
	return "[font_size=%d][color=#fff4d8]%s[/color][/font_size]" % [INFO_FONT_SIZE, _fixed_info_rows("\n".join(rows))]

## Animates one hovered Bash side into Guerra's full-card reveal and restores the compact split on exit.
## Red owns the left pointer half and blue the right; each change crossfades directly over the normal 0.18s hover duration.
## No intermediate reset or timer delays side switches; an interrupted fade resumes from current opacity.
func _set_bash_hover_side(side: int) -> void:
	if side == bash_hover_side: return
	bash_hover_side = side
	if side >= 0 and rendered_bash != null:
		for unit in _current_units():
			if unit.player == (1 if side == 0 else 2):
				bash_unit_hovered.emit(hex_info.coordinate, unit.iun)
				break
	_animate_bash_focus(side)

## _set_bash_hover_side() drives reveal/opacity/stats/details using BoardCharacter.HOVER_FADE_DURATION (0.18s), matching normal hover.
## Hover follows red-left/blue-right ownership. Slider characters share the portrait behavior while retaining their own opacity/crossfade/greyscale; comparison mode keeps side-by-side labels.
## Stats keep the same 120px column centers as action info; slider focus centers the whole stat column.
func _animate_bash_focus(side: int) -> void:
	if rendered_bash == null: return
	if bash_focus_tween != null and bash_focus_tween.is_running(): bash_focus_tween.kill()
	bash_focus_tween = create_tween().set_parallel(true)
	bash_focus_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	for figure: Sprite2D in unit_figures.get_children():
		if figure is BoardCharacter:
			var unit := Match.get_unit(figure.unit_id)
			figure.set_hover(side == (0 if unit.player == 1 else 1))
			if not bash_slider_enabled: continue
		var material := figure.material as ShaderMaterial
		if material == null: continue
		var figure_side := 0 if int(material.get_shader_parameter("bash_side")) < 0 else 1
		var reveal := 0.0 if side < 0 else (1.0 if figure_side == side else -1.0)
		var opacity := 1.0 if side < 0 or figure_side == side else 0.0
		bash_focus_tween.tween_method(_set_bash_shader_value.bind(material, &"bash_reveal"),
			float(material.get_shader_parameter("bash_reveal")), reveal, BoardCharacter.HOVER_FADE_DURATION)
		bash_focus_tween.tween_method(_set_bash_shader_value.bind(material, &"bash_opacity"),
			float(material.get_shader_parameter("bash_opacity")), opacity, BoardCharacter.HOVER_FADE_DURATION)
	for overlay in bash_overlays:
		var is_stats := overlay.name.begins_with("BashStats_")
		var overlay_side := 0 if overlay.name.ends_with("Left") else 1
		var character_side := BoardCharacter.supports(Match.get_unit(int(overlay.get_meta("unit_id", -1))))
		if is_stats:
			var target_alpha := 1.0 if side < 0 or side == overlay_side else 0.0
			var target_x := -60.0 if side == overlay_side else (-120.0 if overlay_side == 0 else 0.0)
			if character_side and not bash_slider_enabled:
				target_alpha = 0.35 if side == overlay_side else 1.0
				target_x = -120.0 if overlay_side == 0 else 0.0
			overlay.visible = true
			bash_focus_tween.tween_property(overlay, "position:x", target_x, BoardCharacter.HOVER_FADE_DURATION)
			bash_focus_tween.tween_property(overlay, "modulate:a", target_alpha, BoardCharacter.HOVER_FADE_DURATION)
		else:
			var alpha := 1.0 if side == overlay_side else 0.0
			if character_side:
				alpha = (0.35 if side == overlay_side else 1.0) if not bash_slider_enabled else (0.35 if side == overlay_side else 0.0)
			bash_focus_tween.tween_property(overlay, "modulate:a", alpha, BoardCharacter.HOVER_FADE_DURATION)

## Sets an animated Bash clipping or opacity parameter on its participant's shader material.
## _set_bash_hover_side() binds the material and parameter for each parallel transition.
func _set_bash_shader_value(value: float, material: ShaderMaterial, parameter: StringName) -> void:
	material.set_shader_parameter(parameter, value)

## Removes side-stat and hidden detail controls before HexCell rebuilds its current occupants.
## refresh() calls this only when the rendered encounter changes or ends, stopping its active focus fade.
## Participant click boxes stop receiving input immediately and fade their borders out before deletion.
func _clear_bash_overlays() -> void:
	for box in bash_click_boxes:
		if is_instance_valid(box):
			box.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_tween_bash_box(box, 0.0)
			var tween: Tween = box.get_meta("hover_tween")
			tween.tween_callback(box.queue_free)
	bash_click_boxes.clear()
	rendered_bash = null
	if bash_focus_tween != null and bash_focus_tween.is_running(): bash_focus_tween.kill()
	bash_focus_tween = null
	for overlay in bash_overlays:
		if is_instance_valid(overlay):
			remove_child(overlay)
			overlay.queue_free()
	bash_overlays.clear()

## Fills the 3:2 rectangle with aspect-covered art, clips it with the hex mask, and applies inactivity tint.
## refresh() calls this for each deployed occupant; the selected character follows the cursor only outside this cell's picking polygon.
## Normal character rendering resets Bash clipping so an encounter ending cannot leave a retained sprite half hidden.
## Stores the layout's unshifted base pose so a generic Bash-exit tween can survive subsequent repaints.
func _add_unit_figure(unit: UnitInfo, index: int, count: int, selected: bool) -> void:
	if BoardCharacter.supports(unit):
		var character := unit_figures.get_node_or_null("UnitFigure_%d" % unit.iun) as BoardCharacter
		if character == null:
			character = BoardCharacter.new()
			character.name = "UnitFigure_%d" % unit.iun
			character.setup(unit.iun)
			unit_figures.add_child(character)
		character.position = Vector2((float(index) - float(count - 1) * 0.5) * 130.0, 8.0)
		character.set_meta("ordinary_base_position", character.position)
		var character_material := character.material as ShaderMaterial
		character_material.set_shader_parameter("bash_side", 0)
		character_material.set_shader_parameter("bash_reveal", 0.0)
		character_material.set_shader_parameter("bash_opacity", 1.0)
		character.home_shape = $CollisionShape2D
		character.set_follow_pointer(unit.iun == focused_unit_id)
		character.set_hover(is_hovered and count == 1)
		return
	var art_path := BoardCharacter.card_art_path(unit)
	if art_path.is_empty(): return
	var figure := Sprite2D.new()
	figure.name = "UnitFigure_%d" % unit.iun
	figure.set_meta("unit_id", unit.iun)
	figure.centered = true
	figure.texture = load(art_path)
	figure.set_meta("hover_eligible", unit.active and unit.player == Match.active_player)
	var panel_width := 260.0 / maxf(count, 1)
	var panel_height := 260.0 * 2.0 / 3.0
	figure.scale = Vector2(panel_width / figure.texture.get_width(), panel_height / figure.texture.get_height())
	figure.position = Vector2((float(index) - float(count - 1) * 0.5) * panel_width, 0.0)
	figure.set_meta("ordinary_base_position", figure.position)
	figure.z_index = 1
	if selected: figure.modulate = Color(1.08, 1.08, 1.08, 1.0)
	var art_material := ShaderMaterial.new()
	art_material.shader = INACTIVE_ART_SHADER
	art_material.set_shader_parameter("inactive", not unit.active)
	art_material.set_shader_parameter("target_aspect", panel_width / panel_height)
	art_material.set_shader_parameter("hover_angle_degrees", 0.0)
	figure.material = art_material
	unit_figures.add_child(figure)

## Board resolved-attack events pulse the same gold pixel-art rim without altering target selection or regional control.
## Optional delay aligns instant attacks with their travelling artwork; overlapping hits restart from the visible opacity and refresh retains the overlay.
func play_resolution_highlight(delay: float = 0.0) -> void:
	if resolution_gold_frame == null:
		resolution_gold_frame = Sprite2D.new()
		resolution_gold_frame.name = "ResolvedAttackGoldFrame"
		resolution_gold_frame.texture = FRAME_GREY
		resolution_gold_frame.transform = frame.transform
		resolution_gold_frame.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		resolution_gold_frame.modulate = Color(1.0, 0.76, 0.22, 0.0)
		resolution_gold_frame.z_index = 4
		add_child(resolution_gold_frame)
	if resolution_gold_tween != null: resolution_gold_tween.kill()
	resolution_gold_tween = create_tween()
	resolution_gold_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if delay > 0.0: resolution_gold_tween.tween_interval(delay)
	resolution_gold_tween.tween_property(resolution_gold_frame, "modulate:a", 0.95, 0.18)
	resolution_gold_tween.tween_property(resolution_gold_frame, "modulate:a", 0.55, 0.22)
	resolution_gold_tween.tween_property(resolution_gold_frame, "modulate:a", 0.9, 0.22)
	resolution_gold_tween.tween_property(resolution_gold_frame, "modulate:a", 0.0, 0.3)

## refresh() crossfades the regional rim into a 70%-opacity gold overlay over 0.25 seconds.
## Lazily copies the frame's alignment once; repaints retain progress, while rapid selection changes reverse from the current blend.
## Both directions preserve the current regional texture underneath; only rim sprites change, independently of rules and info.
func _refresh_target_color() -> void:
	if target_gold_frame == null:
		target_gold_frame = Sprite2D.new()
		target_gold_frame.name = "TargetGoldFrame"
		target_gold_frame.texture = FRAME_GREY
		target_gold_frame.transform = frame.transform
		target_gold_frame.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		add_child(target_gold_frame)
		move_child(target_gold_frame, frame.get_index() + 1)
	_apply_target_color(target_color_amount)
	var goal := 1.0 if targetable else 0.0
	if goal == target_color_goal: return
	target_color_goal = goal
	if target_color_tween != null: target_color_tween.kill()
	target_color_tween = create_tween()
	target_color_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	target_color_tween.tween_method(_apply_target_color, target_color_amount, goal, 0.25)

## _refresh_target_color and its node-bound tween apply complementary rim opacities, also preserving the independent regional crossfade.
## Stores the blend so repaints and interrupted transitions resume from the visible state.
func _apply_target_color(amount: float) -> void:
	target_color_amount = amount
	frame.modulate = Color(1.0, 1.0, 1.0, 0.4 * (1.0 - amount) * control_color_blend)
	if is_instance_valid(control_color_overlay): control_color_overlay.modulate.a = 0.4 * (1.0 - amount) * (1.0 - control_color_blend)
	target_gold_frame.modulate = Color(1.0, 0.76, 0.22, 0.7 * amount)

## Cell processing releases only the latest regional texture after movement, action, Slash and Skull finish; persistent loops do not block.
## Initial map colors are immediate; later authoritative control changes remain queued without delaying or modifying rules.
func _update_control_color() -> void:
	if pending_control_texture == null or Engine.get_process_frames() <= control_color_queued_frame: return
	if pending_control_texture == frame.texture:
		pending_control_texture = null
		return
	var owner_board := get_parent().get_parent() as GuerraBoard
	if owner_board != null and owner_board._phase_presentation_busy(): return
	if control_color_tween != null and control_color_tween.is_running(): return
	control_color_overlay = Sprite2D.new()
	control_color_overlay.texture = frame.texture
	control_color_overlay.transform = frame.transform
	control_color_overlay.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(control_color_overlay)
	move_child(control_color_overlay, frame.get_index() + 1)
	frame.texture = pending_control_texture
	pending_control_texture = null
	control_color_blend = 0.0
	_apply_control_color_blend(0.0)
	control_color_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	control_color_tween.tween_method(_apply_control_color_blend, 0.0, 1.0, 0.25)
	control_color_tween.tween_callback(func() -> void:
		control_color_overlay.queue_free())

## Regional crossfade tween shares target-rim opacity calculations so selection changes never overwrite either transition.
func _apply_control_color_blend(amount: float) -> void:
	control_color_blend = amount
	_apply_target_color(target_color_amount)

## Applies Guerra's compact target pose without recoloring the region frame.
## refresh() and set_board_position() call this when candidates or the board layout change.
func _apply_target_transform() -> void:
	position = board_position + (Vector2(0, 3) if targetable else Vector2.ZERO)
	scale = Vector2.ONE * (0.95 if targetable else 1.0)

## Starts card sway and focuses the pointer's Bash half when entering this collision shape.
## Area2D.mouse_entered notifies Board first, then starts character opacity and readable info fading where available.
func _on_mouse_entered() -> void:
	is_hovered = true
	hovered.emit(hex_info.coordinate)
	_start_hover_oscillation()
	_fade_character_info(true)
	var bash := _live_bash(_current_units())
	if bash != null:
		var local_mouse := get_local_mouse_position()
		_set_bash_hover_side(0 if local_mouse.x < 0.0 else 1)

## Settles card sway and restores the compact Bash split after the pointer leaves this hex.
## Area2D.mouse_exited restores translucent characters and readable info; selected characters keep facing the pointer.
## Participant GUI boxes extend above the hex polygon, so crossing into them does not count as leaving the Bash.
func _on_mouse_exited() -> void:
	for box in bash_click_boxes:
		if is_instance_valid(box) and Rect2(Vector2.ZERO, box.size).has_point(box.get_local_mouse_position()): return
	is_hovered = false
	_settle_hover_oscillation()
	_fade_character_info(false)
	_set_bash_hover_side(-1)
	unhovered.emit(hex_info.coordinate)

## Repeats a 1.15-second, more visible vertical-axis sway from −15° to +15° on eligible portraits.
## Bash hover follows red-left/blue-right ownership. _on_mouse_entered() and refresh() call this; characters change hover opacity instead of using the portrait sway shader.
func _start_hover_oscillation() -> void:
	_stop_hover_tweens()
	for figure: Sprite2D in unit_figures.get_children():
		if figure is BoardCharacter:
			figure.set_hover(rendered_bash == null or bash_hover_side == (0 if Match.get_unit(figure.unit_id).player == 1 else 1))
			continue
		if not figure.get_meta("hover_eligible", false): continue
		var material := figure.material as ShaderMaterial
		if material == null: continue
		var tween := create_tween().set_loops()
		_tween_hover_segment(tween, material, 0.0, -15.0, 0.2875)
		_tween_hover_segment(tween, material, -15.0, 15.0, 0.575)
		_tween_hover_segment(tween, material, 15.0, 0.0, 0.2875)
		hover_tweens.append(tween)

## Adds one CSS ease-in-out rotation segment to the active Guerra-style hover loop.
## _start_hover_oscillation() queues the three 0°/−15°/+15°/0° keyframe spans.
func _tween_hover_segment(tween: Tween, material: ShaderMaterial, from_angle: float,
		to_angle: float, duration: float) -> void:
	tween.tween_method(_set_hover_segment_angle.bind(from_angle, to_angle, material), 0.0, 1.0, duration)

## Stops the CSS-equivalent hover animation and restores the neutral untransformed image.
## _on_mouse_exited() calls this; characters fade to idle opacity and portrait CSS animation resets its angle.
func _settle_hover_oscillation() -> void:
	_stop_hover_tweens()
	for figure: Sprite2D in unit_figures.get_children():
		if figure is BoardCharacter:
			figure.set_hover(false)
			continue
		var material := figure.material as ShaderMaterial
		if material == null: continue
		_set_hover_angle(0.0, material)

## Converts linear Tween progress through CSS cubic-bezier(.42, 0, .58, 1) before setting rotation.
## Each segment created by _tween_hover_segment() invokes this once per rendered Tween update.
func _set_hover_segment_angle(progress: float, from_angle: float, to_angle: float,
		material: ShaderMaterial) -> void:
	var eased_progress := _css_ease_in_out(progress)
	_set_hover_angle(lerpf(from_angle, to_angle, eased_progress), material)

## Evaluates the CSS ease-in-out cubic Bézier curve used by Guerra's keyframe animation.
## _set_hover_segment_angle() calls this with linear Tween progress from 0 to 1.
func _css_ease_in_out(progress: float) -> float:
	var lower := 0.0
	var upper := 1.0
	for _iteration in 14:
		var parameter := (lower + upper) * 0.5
		var inverse := 1.0 - parameter
		var curve_x := 3.0 * inverse * inverse * parameter * 0.42 \
			+ 3.0 * inverse * parameter * parameter * 0.58 + parameter * parameter * parameter
		if curve_x < progress: lower = parameter
		else: upper = parameter
	var curve_parameter := (lower + upper) * 0.5
	var curve_inverse := 1.0 - curve_parameter
	return 3.0 * curve_inverse * curve_parameter * curve_parameter \
		+ curve_parameter * curve_parameter * curve_parameter

## Writes one Y-axis tilt angle into the art shader during a Tween.
## _start_hover_oscillation() and _settle_hover_oscillation() call this method.
func _set_hover_angle(angle: float, material: ShaderMaterial) -> void:
	material.set_shader_parameter("hover_angle_degrees", angle)

## Stops old loops/settling tweens before the corresponding portrait is rebuilt or reanimated.
## refresh(), _start_hover_oscillation(), and _settle_hover_oscillation() call this helper.
func _stop_hover_tweens() -> void:
	for tween in hover_tweens:
		if tween.is_running(): tween.kill()
	hover_tweens.clear()

## Updates the focused side while the pointer moves inside a live Bash; ordinary clicks still select the hex.
## Godot routes mouse motion/buttons through Area2D._input_event() for this cell's collision polygon.
func _input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventMouseMotion and is_hovered:
		var bash := _live_bash(_current_units())
		if bash != null:
			var local_mouse := get_local_mouse_position()
			_set_bash_hover_side(0 if local_mouse.x < 0.0 else 1)
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		pressed.emit(hex_info.coordinate)

## Resolves current occupants for Bash validation in hover callbacks without caching Match state.
## _on_mouse_entered(), _input_event(), and _live_bash() use the same identity-backed tile query.
func _current_units() -> Array[UnitInfo]:
	var units: Array[UnitInfo] = []
	if hex_info == null: return units
	for reference in Match.occupants(hex_info.hex_id):
		var unit := Match.get_unit(reference.id)
		if unit != null: units.append(unit)
	return units
