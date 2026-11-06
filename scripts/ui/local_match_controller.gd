## Connects the first local-match controls to authoritative Match and Board operations.
class_name LocalMatchController
extends Node

const SnapshotStore = preload("res://scripts/runtime/match_snapshot.gd")
const RuleText = preload("res://scripts/ui/effect_text.gd")

## Test format uses one action per turn so every completed deployment/action advances play.
@export_range(1, 8) var action_allowance := 1
@export_range(1, 10) var deployment_allowance := 3

var board: GuerraBoard
var overlay: CanvasLayer
var pending_deployment := -1
var selected_unit_id := -1
var preferred_action_slot := 1
var pending_action_switch_index := -1
var pending_unit_switch_id := -1
var status_message := ""
var network_status: Label
var parchment_menu: Control
var status_header: Control
var phase_sign: Control
var save_snapshot_button: Button
var reset_match_button: Button
var reset_requested := false
var hover_panel: PanelContainer
var side_frame_style: StyleBoxTexture
var hover_frame_style: StyleBoxTexture
var hover_visibility_tween: Tween
var hover_wants_visible := false
var hover_info_enabled := true
var hover_ctrl_held := false
var hover_dragging := false
var hover_drag_offset := Vector2.ZERO
var hover_custom_position := false
var hover_preferred_position := Vector2.ZERO
var rule_guide_panel: PanelContainer
var rule_guide_label: Label
var rule_guide_key := ""
var rule_guide_tween: Tween
var phase_trigger_hovered := false
var phase_hover_execution: EffectExecution
var hover_over_target := false
var hover_cutout_material: ShaderMaterial
var counter_pointer_inside := false
var hover_content: VBoxContainer
var hovered_hex_id := -1
var hovered_unit_id := -1
var player_trays: Dictionary = {}
var card_lists: Dictionary = {}
var player_info_panels: Dictionary = {}
var side_drawers: Dictionary = {}
## Match events may arrive several times in one action; one deferred paint uses their final state without changing rule timing.
var _hud_refresh_queued := false

## Starts the sample match, restores a saved snapshot if present, and builds its HUD.
## Game._ready() calls this after map generation; tile and Bash-side signals keep inspection tied to the pointer.
## Prepares one shared atlas per PixelLab character before match input; tray portraits reuse baked bounds without GPU readback.
## Online handoff uses the room's saved decks/deployment pool and NetworkSession checkpoint; offline startup keeps its local snapshot.
func start_match(match_board: GuerraBoard, ui_layer: CanvasLayer) -> void:
	if not BoardCharacter.preload_art():
		push_error("Could not prepare character sprites. Rebuild the character alignment asset.")
		return
	board = match_board
	overlay = ui_layer
	board.hex_selected.connect(_on_hex_selected)
	board.unit_selected.connect(_select_unit)
	board.hex_hovered.connect(_on_hex_hovered)
	board.hex_unhovered.connect(_on_hex_unhovered)
	board.hex_unit_hovered.connect(_on_hex_unit_hovered)
	board.trigger_cues_changed.connect(_queue_hud_refresh)
	board.selection_abandoned.connect(_on_selection_abandoned)
	Match.rules_runner.command_finished.connect(_on_effect_completed)
	Match.rules_runner.execution_started.connect(_on_execution_started)
	Match.rules_runner.idle.connect(_queue_hud_refresh)
	Match.state_changed.connect(_queue_hud_refresh)
	Match.action_event.connect(_on_action_event)
	_build_hud()
	get_viewport().size_changed.connect(_layout_hud)
	if Match.map.is_empty():
		var region_map := RegionMap.new()
		region_map._generate_hex_grid()
		region_map.free()
	var chosen_army: Array[UnitInfo] = NetworkSession.make_army(NetworkSession.armies) if NetworkSession.online else CardCatalogue.starter_army()
	var deploy_limit := int(NetworkSession.room.get("settings", {}).get("deployments", deployment_allowance)) if NetworkSession.online else deployment_allowance
	if not Match.start_local_match(chosen_army, action_allowance, deploy_limit):
		push_error("Could not start the local match. Check the two starter heroes and format allowances.")
		return
	if NetworkSession.online:
		for seat in NetworkSession.room.get("players", []):
			if seat is Dictionary and int(seat.get("player", 0)) in [1, 2]: Match.players[int(seat.player)].name = str(seat.get("nickname", "Player"))
		NetworkSession.attach_game(board)
		NetworkSession.notice.connect(_on_network_notice)
		NetworkSession.lobby_changed.connect(_queue_hud_refresh)
	elif SnapshotStore.exists():
		if SnapshotStore.load_snapshot():
			status_message = "Restored the saved snapshot."
		else:
			SnapshotStore.delete_snapshot()
			status_message = "The saved snapshot was invalid; started a new match."
	board.refresh_board()
	_refresh_hud()

## H toggles inspection; holding Ctrl temporarily shows retained info and allows left-dragging anywhere on its panel.
## Godot routes input before board selection; Ctrl release restores the H preference and ends dragging without resetting position.
## Drag start/release refresh cursor shapes immediately, showing a closed hand only while moving the retained panel.
func _input(event: InputEvent) -> void:
	if event is InputEventKey and not event.echo:
		if event.keycode == KEY_CTRL:
			hover_ctrl_held = event.pressed
			if not hover_ctrl_held: hover_dragging = false
			_update_rule_guide()
		elif event.keycode == KEY_H and event.pressed:
			hover_info_enabled = not hover_info_enabled
		else: return
		counter_pointer_inside = false
		_refresh_hover_panel()
		if hover_panel != null: _sync_hover_target_input(hover_panel)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if not event.pressed and hover_dragging:
			hover_dragging = false
			_sync_hover_target_input(hover_panel)
			get_viewport().set_input_as_handled()
		elif event.pressed and hover_ctrl_held and hover_panel != null and hover_panel.visible and hover_panel.get_global_rect().has_point(event.position):
			hover_dragging = true
			hover_custom_position = true
			hover_preferred_position = hover_panel.position
			hover_drag_offset = event.position - hover_panel.position
			_sync_hover_target_input(hover_panel)
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and hover_dragging:
		hover_preferred_position = event.position - hover_drag_offset
		_layout_hover_panel()
		get_viewport().set_input_as_handled()

## Lets players choose an action slot before clicking a unit; slot 1 is Move/Fly by default.
## Godot routes number keys to the selected parchment action or pending preview; Escape closes an idle menu.
func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	var key := (event as InputEventKey).keycode
	if key == KEY_ESCAPE and selected_unit_id >= 0 and not Match.rules_runner.busy():
		_on_selection_abandoned()
		get_viewport().set_input_as_handled()
		return
	if key < KEY_1 or key > KEY_9: return
	preferred_action_slot = key - KEY_0
	if Match.rules_runner.busy():
		var selected_unit := Match.get_unit(selected_unit_id)
		if selected_unit == null: return
		var ordered := _ordered_effect_indices(selected_unit)
		var effect_index := _action_index_for_slot(ordered, preferred_action_slot)
		if effect_index >= 0: _switch_pending_action(effect_index)
		get_viewport().set_input_as_handled()
		return
	var selected := Match.get_unit(selected_unit_id)
	if selected != null:
		var index := _action_index_for_slot(_ordered_effect_indices(selected), preferred_action_slot)
		if index >= 0: _begin_unit_action(selected_unit_id, index)
		get_viewport().set_input_as_handled()
		return
	status_message = "Action %d selected. Click a friendly unit to choose its target." % preferred_action_slot
	_refresh_hud()
	get_viewport().set_input_as_handled()

## Creates the parchment backdrop, player panels and a top-centered pair of parchment Save/Reset buttons.
## start_match() calls this once; animated control handlers call _save_snapshot() and _reset_match().
## Turn/phase/action summaries stay in the player-info panels and inn sign; no top status or instruction text is shown.
## Adds the terrain-anchored inn sign left of the side cards; its signal bindings queue the four visible phase labels.
## Player info stays visible; each unit roster begins collapsed behind its own bottom-corner arrow sign.
func _build_hud() -> void:
	var background_layer := CanvasLayer.new()
	background_layer.layer = -1
	get_parent().add_child(background_layer)
	var parchment := TextureRect.new()
	parchment.texture = load("res://assets/ui/background.png")
	parchment.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	parchment.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	parchment.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parchment.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background_layer.add_child(parchment)

	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(root)
	status_header = HBoxContainer.new()
	status_header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status_header.alignment = BoxContainer.ALIGNMENT_CENTER
	status_header.add_theme_constant_override("separation", 10)
	root.add_child(status_header)
	save_snapshot_button = Button.new()
	save_snapshot_button.text = "Save"
	save_snapshot_button.pressed.connect(_on_save_pressed)
	_style_parchment_hud_button(save_snapshot_button)
	status_header.add_child(save_snapshot_button)
	reset_match_button = Button.new()
	reset_match_button.text = "Leave" if NetworkSession.online else "Reset"
	reset_match_button.pressed.connect(_on_reset_pressed)
	_style_parchment_hud_button(reset_match_button)
	status_header.add_child(reset_match_button)
	if NetworkSession.online:
		var reconnect := Button.new()
		reconnect.text = "Reconnect"
		reconnect.pressed.connect(func() -> void: NetworkSession.connect_relay(NetworkSession.nickname))
		_style_parchment_hud_button(reconnect)
		status_header.add_child(reconnect)
		network_status = Label.new()
		network_status.text = "You are Player %d" % NetworkSession.local_player
		status_header.add_child(network_status)
	for player_id in [2, 1]:
		_make_player_tray(root, player_id)
	for player_id in [1, 2]: _build_side_drawer_button(root, player_id)
	_build_hover_panel(root)
	phase_sign = preload("res://scripts/ui/phase_sign.gd").new()
	phase_sign.set("board", board)
	root.add_child(phase_sign)
	_layout_hud()

## _build_hud() styles Save and Reset with the settled parchment artwork used by unit actions, retaining standard Button input/disabled behavior.
## Shared paper colors stay constant across hover/press states; dark 23px captions remain centered above the frame.
func _style_parchment_hud_button(button: Button) -> void:
	button.custom_minimum_size = Vector2(138, 44)
	button.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_size_override("font_size", 23)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(state, Color("#382419"))
	button.add_theme_color_override("font_disabled_color", Color("#897d6b"))
	var paper := StyleBoxTexture.new()
	paper.texture = preload("res://assets/ui/parchment/frame_6.png")
	for side in [SIDE_LEFT, SIDE_RIGHT]: paper.set_content_margin(side, 12.0)
	for side in [SIDE_TOP, SIDE_BOTTOM]: paper.set_content_margin(side, 6.0)
	for state in ["normal", "hover", "pressed", "disabled"]:
		button.add_theme_stylebox_override(state, paper)
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

## Save clicks play a cosmetic parchment press/rebound while saving immediately, so the captured state is the state clicked.
func _on_save_pressed() -> void:
	if reset_requested: return
	_animate_hud_button(save_snapshot_button)
	_save_snapshot()

## Reset/online Leave clicks finish their parchment animation before reload/room departure; repeated clicks are ignored during that animation.
func _on_reset_pressed() -> void:
	if reset_requested: return
	reset_requested = true
	reset_match_button.disabled = true
	save_snapshot_button.disabled = true
	await _animate_hud_button(reset_match_button).finished
	_reset_match()

## Both top controls squash to 94%, rebound to 104%, then settle over 320ms; rapid Save clicks retarget from the visible scale.
## The button-local tween preserves parchment colors and leaves its final scale at one for later HUD layout.
func _animate_hud_button(button: Button) -> Tween:
	var previous: Tween = button.get_meta("press_tween", null)
	if previous != null: previous.kill()
	button.pivot_offset = button.size * 0.5
	var tween := button.create_tween()
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(button, "scale", Vector2.ONE * 0.94, 0.08)
	tween.tween_property(button, "scale", Vector2.ONE * 1.04, 0.1)
	tween.tween_property(button, "scale", Vector2.ONE, 0.14)
	button.set_meta("press_tween", tween)
	return tween

## _build_hud() adds a mirrored pair of bottom-corner arrow buttons; each controls only its own player's roster.
func _build_side_drawer_button(root: Control, player_id: int) -> void:
	var button := preload("res://scripts/ui/side_roster_toggle.gd").new()
	button.setup(player_id)
	button.pressed.connect(_toggle_side_drawer.bind(player_id))
	root.add_child(button)
	side_drawers[player_id] = {"button": button, "open": false, "progress": 0.0, "tween": null}

## Arrow clicks reverse that player's roster fade and smoothly reflect its sign; player info remains visible.
## Closing clears inspection hover, while deployment posture continues to follow its hex highlights.
func _toggle_side_drawer(player_id: int) -> void:
	var drawer: Dictionary = side_drawers[player_id]
	drawer.open = not drawer.open
	drawer.button.set_open(drawer.open)
	if drawer.tween != null: drawer.tween.kill()
	if not drawer.open:
		for card in card_lists[player_id].get_children():
			if card.has_method("set_hovered"): card.set_hovered(false)
		var hovered := Match.get_unit(hovered_unit_id)
		if hovered != null and hovered.player == player_id: _on_card_unhovered(hovered_unit_id)
	drawer.tween = create_tween()
	drawer.tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	drawer.tween.tween_method(_apply_side_drawer.bind(player_id), drawer.progress, 1.0 if drawer.open else 0.0, 0.25)

## Each drawer tween and _layout_hud() fade its roster in the normal container slot; hiding it never hides or shifts player info.
## Fully hidden roster controls accept no pointer input; resizing retains each player's independent fade progress.
func _apply_side_drawer(progress: float, player_id: int) -> void:
	side_drawers[player_id].progress = progress
	var side_column: Control = player_trays.get(player_id)
	if side_column == null: return
	var panel := side_column.get_node("Player%dTray" % player_id) as Control
	panel.modulate.a = progress
	panel.visible = progress > 0.001

## Creates a compact corner hover host with no outer frame; individual card panels provide the background.
## _build_hud() calls this once; the scroll viewport fills the host so its clipped children remain visible.
## Deferred content minimum-size changes fit generated rules while the panel ignores mouse input.
## One shared screen-space material cuts an 80px pointer circle with a 20px soft ring through every hover-info frame, image and text line.
func _build_hover_panel(root: Control) -> void:
	hover_panel = PanelContainer.new()
	hover_panel.name = "HoverInfoWindow"
	hover_panel.visible = false
	hover_panel.modulate.a = 0.0
	hover_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hover_panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	hover_cutout_material = ShaderMaterial.new()
	hover_cutout_material.shader = preload("res://assets/shaders/hover_pointer_cutout.gdshader")
	hover_panel.material = hover_cutout_material
	root.add_child(hover_panel)
	rule_guide_panel = PanelContainer.new()
	rule_guide_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rule_guide_panel.z_index = 20
	rule_guide_panel.modulate.a = 0.0
	var guide_style := StyleBoxFlat.new()
	guide_style.bg_color = Color("#30271fee")
	guide_style.set_content_margin_all(12.0)
	guide_style.set_corner_radius_all(6)
	rule_guide_panel.add_theme_stylebox_override("panel", guide_style)
	root.add_child(rule_guide_panel)
	rule_guide_label = Label.new()
	rule_guide_label.custom_minimum_size.x = 300.0
	rule_guide_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rule_guide_label.add_theme_font_size_override("font_size", 19)
	rule_guide_label.add_theme_color_override("font_color", Color("#f2e2c6"))
	rule_guide_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rule_guide_panel.add_child(rule_guide_label)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2.ZERO
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hover_panel.add_child(scroll)
	hover_content = VBoxContainer.new()
	hover_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hover_content.add_theme_constant_override("separation", 3)
	hover_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scroll.add_child(hover_content)
	hover_content.minimum_size_changed.connect(_layout_hover_panel, CONNECT_DEFERRED)

## Starts tile inspection, clearing any previous tray or Bash participant focus.
## GuerraBoard.hex_hovered calls this before HexCell reports the Bash side under the pointer.
func _on_hex_hovered(hex_id: int) -> void:
	hovered_unit_id = -1
	hovered_hex_id = hex_id
	_refresh_hover_panel()

## Shows only the Bash participant under the pointer, including during the neutral side-change transition.
## GuerraBoard.hex_unit_hovered calls this on entry/side changes without rebuilding any board cells.
func _on_hex_unit_hovered(hex_id: int, unit_id: int) -> void:
	if hovered_hex_id == hex_id and hovered_unit_id == unit_id: return
	hovered_hex_id = hex_id
	hovered_unit_id = unit_id
	_refresh_hover_panel()

## Ignores an old cell's exit when the pointer has already entered a neighboring cell.
## GuerraBoard.hex_unhovered clears both tile and Bash participant focus for the exiting cell.
func _on_hex_unhovered(hex_id: int) -> void:
	if hovered_hex_id != hex_id: return
	hovered_hex_id = -1
	hovered_unit_id = -1
	_refresh_hover_panel()

## Displays a card's information while its tray card is under the pointer.
## _make_card() connects mouse_entered with stable identity; hover arbitration stops every other side portrait.
func _on_card_hovered(unit_id: int) -> void:
	_set_side_portrait_hover(unit_id)
	hovered_hex_id = -1
	hovered_unit_id = unit_id
	_refresh_hover_panel()

## Restores board hover details or hides the card window after leaving a tray card.
## _make_card() connects its mouse_exited signal and supplies the leaving unit ID.
func _on_card_unhovered(unit_id: int) -> void:
	if hovered_unit_id != unit_id: return
	_set_side_portrait_hover(-1)
	hovered_unit_id = -1
	_refresh_hover_panel()

## Rebuilds compact card/stat/rule panels without a redundant 'Hex details' or 'Card details' heading.
## Hover signals and _refresh_hud() call this; Bash inspection follows one unit and drops stale/moved participants.
## Bombs and pending attacks share a detached 25px counter box using value/P, action icon and source troop name.
## Empty target tiles retain this box; resolved attacks disappear on the next HUD refresh.
## Positive Stun counts for the inspected troops share that box; their health rows contain only life.
## Named unit resource counters such as Soul are displayed in the same detached counter box, separately from modifier/Bow counters.
## Bow rows are exact-attack replay links and retain the panel while its counter text is hovered.
## Troop/counter boxes use the shared tiled wooden frame; the outer scrolling host stays unframed.
## White/grey hover copy sits directly on dark wood with no reading rectangle; boxes retain a compact 3px separation.
## Leaving targets retains the last content through a short grace period/fade; entering a new target cancels that hide.
## Rebuilt controls inherit target click-through while the pointer overlaps a selectable hex beneath the panel.
## Counter replay links retain their click behavior without URL underlines.
## H-disabled inspection tracks identities; Ctrl shows the current target and retains existing content only when there is no new inspectable target.
## The phase blink takes inspection priority and describes the captured execution even when its source has died.
func _refresh_hover_panel() -> void:
	if hover_panel == null or not is_instance_valid(hover_panel): return
	if phase_trigger_hovered and (hover_info_enabled or hover_ctrl_held):
		_show_phase_trigger_hover()
		return
	if not hover_info_enabled and not hover_ctrl_held:
		_set_hover_visible(false)
		return
	if hovered_hex_id < 0 and hovered_unit_id < 0:
		_set_hover_visible(false)
		return
	var tile: HexInfo = null
	if hovered_hex_id >= 0: tile = Match.get_hex(hovered_hex_id)
	var focused_unit: UnitInfo = null
	if hovered_unit_id >= 0: focused_unit = Match.get_unit(hovered_unit_id)
	if tile != null and focused_unit != null and (focused_unit.t_state != Enum.t_state.DEPLOYED or focused_unit.ihx != hovered_hex_id):
		focused_unit = null
		hovered_unit_id = -1
	if tile == null and focused_unit == null:
		_set_hover_visible(false)
		return
	if focused_unit == null and tile != null and Match.occupants(hovered_hex_id).is_empty() \
			and Match.bomb_at(hovered_hex_id) == null and _pending_attack_hover_rows(hovered_hex_id).is_empty():
		_set_hover_visible(false)
		return
	for child in hover_content.get_children():
		hover_content.remove_child(child)
		child.queue_free()
	counter_pointer_inside = false
	var unit_count := 0
	var inspected_units: Array[UnitInfo] = []
	if focused_unit != null:
		unit_count = 1
		inspected_units.append(focused_unit)
		hover_content.add_child(_make_hover_unit_card(focused_unit))
	elif tile != null:
		for ref in Match.occupants(hovered_hex_id):
			if ref.kind != TargetRef.Kind.UNIT: continue
			var unit := Match.get_unit(ref.id)
			if unit == null: continue
			unit_count += 1
			inspected_units.append(unit)
			hover_content.add_child(_make_hover_unit_card(unit))
	var bomb: BombInfo = null
	if hovered_hex_id >= 0: bomb = Match.bomb_at(hovered_hex_id)
	var attack_rows := _pending_attack_hover_rows(hovered_hex_id) if tile != null else PackedStringArray()
	for unit: UnitInfo in inspected_units:
		var stun := _unit_counter(unit, UnitInfo.STUN_COUNTER)
		if stun > 0:
			attack_rows.append(_counter_hover_row(stun, false, &"stun", unit.player, unit.iun))
		for prop in unit.props:
			if prop.increment != Enum.p_increment.COUNTER or prop.value <= 0: continue
			if prop.name in ["stun", "physical", "magical", "temp_physical", "temp_magical", "bow_damage", "bow_range"]: continue
			attack_rows.append(_counter_hover_row(prop.value, false, StringName(prop.name), unit.player, unit.iun))
	if bomb != null:
		attack_rows.append(_counter_hover_row(bomb.damage, bomb.pierce, &"bomb", bomb.owner, bomb.source_id))
	if not attack_rows.is_empty():
		var counter_box := PanelContainer.new()
		counter_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		counter_box.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		counter_box.add_theme_stylebox_override("panel", _hover_frame_style())
		hover_content.add_child(counter_box)
		var attacks_line := RichTextLabel.new()
		attacks_line.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		attacks_line.add_theme_font_size_override("normal_font_size", 25)
		attacks_line.bbcode_enabled = true
		attacks_line.meta_underlined = false
		attacks_line.fit_content = true
		attacks_line.scroll_active = false
		attacks_line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		attacks_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		attacks_line.mouse_filter = Control.MOUSE_FILTER_STOP
		attacks_line.meta_clicked.connect(_on_counter_replay_clicked)
		attacks_line.meta_hover_started.connect(_on_rule_guide_entered)
		attacks_line.meta_hover_ended.connect(_on_rule_guide_exited)
		attacks_line.mouse_entered.connect(func() -> void:
			counter_pointer_inside = true
			_set_hover_visible(true))
		attacks_line.mouse_exited.connect(func() -> void:
			counter_pointer_inside = false
			_refresh_hover_panel())
		attacks_line.text = RuleGuide.decorate("\n".join(attack_rows))
		counter_box.add_child(attacks_line)
	_set_hover_visible(unit_count > 0 or bomb != null or not attack_rows.is_empty())
	_sync_hover_target_input(hover_panel)
	_layout_hover_panel()

## Godot checks real hex picking polygons even beneath GUI controls, preventing an overlapping counter link from hiding/blocking a target.
## The cutout follows the pointer whenever hover info is visible, independently of target availability or normal panel visibility fades.
## Existing hover life labels also follow the shared Slash beat without rebuilding the panel or restarting its fade.
## Only health labels carry life_unit metadata; other rule/counter labels are skipped before lookup to avoid missing-metadata errors.
## Normalized viewport coordinates account for canvas_items window stretching; the shader measures its 80px radius and 20px ring in rendered pixels.
func _process(_delta: float) -> void:
	_resume_online_switch()
	if hover_panel == null or not is_instance_valid(board): return
	var waiting: EffectExecution = Match.rules_runner.presentation_waiting
	var on_blink: bool = phase_sign != null and phase_sign.contains_trigger_blink(get_viewport().get_mouse_position()) and waiting != null
	if on_blink != phase_trigger_hovered or (on_blink and waiting != phase_hover_execution):
		phase_trigger_hovered = on_blink
		phase_hover_execution = waiting if on_blink else null
		_refresh_hover_panel()
	if rule_guide_panel != null:
		var guide_pointer := get_viewport().get_mouse_position()
		var guide_view := get_viewport().get_visible_rect().size
		rule_guide_panel.position = Vector2(clampf(guide_pointer.x + 18.0, 0.0, maxf(0.0, guide_view.x - rule_guide_panel.size.x)), clampf(guide_pointer.y + 24.0, 0.0, maxf(0.0, guide_view.y - rule_guide_panel.size.y)))
	for label in hover_content.find_children("*", "RichTextLabel", true, false):
		if not label.has_meta("life_unit"): continue
		var unit: UnitInfo = label.get_meta("life_unit")
		if unit != null:
			var next := _hover_life_text(unit, label)
			if label.text != next: label.text = next
	var over_target := false
	var pointer := get_viewport().get_mouse_position()
	var viewport_rect := get_viewport().get_visible_rect()
	hover_cutout_material.set_shader_parameter("pointer_uv", Vector2(-10, -10) if hover_ctrl_held else (pointer - viewport_rect.position) / viewport_rect.size)
	for cell: HexCell in board.hex_grid.get_children():
		if not cell.targetable: continue
		var collision := cell.get_node("CollisionShape2D") as CollisionShape2D
		var polygon := collision.shape as ConvexPolygonShape2D
		var local_pointer := collision.get_global_transform_with_canvas().affine_inverse() * pointer
		if Geometry2D.is_point_in_polygon(local_pointer, polygon.points):
			over_target = true
			break
	if over_target == hover_over_target: return
	hover_over_target = over_target
	if over_target: counter_pointer_inside = false
	_sync_hover_target_input(hover_panel)

## Hover-card updates preserve Slash timing; only effect-altered maximum life is magenta and links to its retained source breakdown.
func _hover_life_text(unit: UnitInfo, label: RichTextLabel) -> String:
	var font_size := label.get_theme_font_size("normal_font_size")
	var maximum := board.life_number(unit, true, font_size)
	var visible_max := unit.max_life
	var feedback: Variant = board.life_feedback.get(unit.get_instance_id())
	if is_instance_valid(feedback) and not feedback.life_revealed: visible_max = feedback.previous_life.y
	if visible_max != int(unit.printed_state.get("life", unit.max_life)):
		maximum = "[url=maxlife:%d][color=#ef70df]%s[/color][/url]" % [unit.iun, maximum]
	return RuleGuide.decorate("%s %s %s" % [board.life_number(unit, false, font_size), GameIcons.bb(&"heart", unit.player), maximum])

## _process() and hover rebuilds disable every panel hitbox while a target lies beneath the pointer, restoring original filters afterward.
## Counter replay links and scrollbars remain usable elsewhere; original filter metadata also covers newly rebuilt content.
## Assigns the shared material directly to each CanvasItem so clipping/container material inheritance cannot omit frames, portraits or glyphs.
## H-disabled hover info accepts no pointer input unless Ctrl is temporarily showing it; Ctrl drag takes precedence in _input.
## Original cursor shapes are retained alongside filters; Ctrl offers an open hand, active dragging a closed hand.
func _sync_hover_target_input(node: Node) -> void:
	if node is CanvasItem:
		node.use_parent_material = false
		node.material = hover_cutout_material
	if node is Control:
		if not node.has_meta("hover_original_filter"): node.set_meta("hover_original_filter", node.mouse_filter)
		if not node.has_meta("hover_original_cursor"): node.set_meta("hover_original_cursor", node.mouse_default_cursor_shape)
		node.mouse_default_cursor_shape = Control.CURSOR_DRAG if hover_dragging else (Control.CURSOR_MOVE if hover_ctrl_held else int(node.get_meta("hover_original_cursor")))
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE if (hover_over_target and not hover_ctrl_held) or not (hover_info_enabled or hover_ctrl_held) else int(node.get_meta("hover_original_filter"))
	for child in node.get_children(): _sync_hover_target_input(child)

## _refresh_hover_panel() requests visibility without restarting an unchanged transition on HUD refresh.
## New targets fade in over 0.18s; leaving retains content for 0.18s before a 0.22s fade, bridging pointer gaps.
## An incoming target interrupts from current opacity; hovering counter text retains it so Bow replay links can be clicked.
## Explicit H hiding bypasses pointer retention and leave grace; Ctrl temporarily retains existing content with the same fade.
func _set_hover_visible(show_panel: bool) -> void:
	var enabled := hover_info_enabled or hover_ctrl_held
	show_panel = (show_panel or (hover_ctrl_held and hover_content.get_child_count() > 0)) and enabled
	if not show_panel and counter_pointer_inside and enabled: return
	if hover_wants_visible == show_panel: return
	hover_wants_visible = show_panel
	if hover_visibility_tween != null: hover_visibility_tween.kill()
	hover_visibility_tween = create_tween()
	hover_visibility_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if show_panel:
		hover_panel.visible = true
		hover_visibility_tween.tween_property(hover_panel, "modulate:a", 1.0, 0.18)
	else:
		if enabled: hover_visibility_tween.tween_interval(0.18)
		hover_visibility_tween.tween_property(hover_panel, "modulate:a", 0.0, 0.22)
		hover_visibility_tween.tween_callback(func() -> void:
			if not hover_wants_visible: hover_panel.visible = false)

## _refresh_hover_panel() queries captured pending attacks as presentation counters on their target hex.
## Keeps each attack separate: values, piercing and owners must not combine into a different damage/Fire resolution.
## Fire, Bow, Gore and each Cannon/Bomb area victim share this display; Gore has no piercing flag.
## Reads existing attack records without creating properties, mutating rules or following a moved source.
## Each row uses the shared icon/value/source wording from _counter_hover_row(), without extra labels.
## Bow uses a BBCode link keyed to its pending record's instance identity, preventing accidental replay of another shot.
func _pending_attack_hover_rows(hex_id: int) -> PackedStringArray:
	var rows := PackedStringArray()
	var families := [
		{"name": "Fire", "attacks": Match.pending_attacks},
		{"name": "Bow", "attacks": Match.pending_bow_attacks},
		{"name": "Gore", "attacks": Match.pending_gore_attacks},
		{"name": "Cannon", "attacks": Match.pending_cannon_attacks}]
	for family: Dictionary in families:
		for attack in family.attacks:
			if attack.resolved or attack.target_hex != hex_id: continue
			var piercing := false if family.name == "Gore" else bool(attack.pierce)
			var attack_name: String = family.name
			if attack is CannonAttack and attack.explosion: attack_name = "Bomb"
			var row := _counter_hover_row(attack.amount, piercing, StringName(attack_name.to_lower()), attack.owner, attack.source_id)
			if attack is BowAttack: row = "[url=bow:%d]%s[/url]" % [attack.get_instance_id(), row]
			rows.append(row)
	return rows

## Counter RichTextLabel.meta_clicked requests one cosmetic replay of the exact still-pending Bow record.
## Searches current records rather than trusting a stale link or resolving arbitrary object IDs; no rules are executed.
func _on_counter_replay_clicked(meta: Variant) -> void:
	var link := str(meta)
	if not link.begins_with("bow:"): return
	var attack_id := link.trim_prefix("bow:").to_int()
	for attack: BowAttack in Match.pending_bow_attacks:
		if attack.get_instance_id() == attack_id:
			board.replay_bow_counter(attack)
			return

## Pending attacks, inert bombs and stored Stun share value/icon/name rows without a dot; troop names use the captured owner's light red/blue.
## P remains attached to piercing values; source lookup uses stable identity, including defeated troops.
## For Stun the identity names the troop holding the counter, since Stun totals do not retain an attacker.
## Missing sources show Unknown troop and BBCode-sensitive names remain literal text.
func _counter_hover_row(amount: int, piercing: bool, action: StringName, owner: int, source_id: int) -> String:
	var source := Match.get_unit(source_id)
	var troop_name := source.name if source != null else "Unknown troop"
	troop_name = troop_name.replace("[", "[lb]")
	var icon := GameIcons.bb(action, owner, 32)
	if icon.is_empty(): icon = "🐗" if action == &"gore" else str(action)
	var color := "#f2f2ef"
	var owner_color := "#ef7770" if owner == 1 else ("#6da9ee" if owner == 2 else color)
	return "[color=%s]%d%s %s [color=%s]%s[/color][/color]" % [color, amount, "P" if piercing else "", icon, owner_color, troop_name]

## Builds one compact dark-wood hover card with white/grey stats and automatically summarized rule BBCode.
## _refresh_hover_panel() calls this for the inspected card/Bash participant; health uses shared PixelLab icons and Stun appears in the separate counter box.
## Uses the enlarged Jersey 10 text sizes (approximately 20% above the original HUD scale).
## The dark PixelLab frame tiles around white/grey copy directly, without an extra backing rectangle.
## Effects retain 21px text and life shares the bright foreground. Life labels retain unit metadata for Slash-timed value/pulse updates.
func _make_hover_unit_card(unit: UnitInfo) -> Control:
	var row := PanelContainer.new()
	row.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	row.add_theme_stylebox_override("panel", _hover_frame_style())
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var layout := HBoxContainer.new()
	layout.add_theme_constant_override("separation", 9)
	layout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(layout)
	var art := TextureRect.new()
	art.custom_minimum_size = Vector2(54, 72)
	art.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var art_path := BoardCharacter.card_art_path(unit)
	if not art_path.is_empty(): art.texture = load(art_path)
	layout.add_child(art)
	var copy := VBoxContainer.new()
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.add_theme_constant_override("separation", 2)
	copy.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout.add_child(copy)
	var title := Label.new()
	title.text = unit.name
	title.add_theme_color_override("font_color", Color("#f2f2ef"))
	title.add_theme_font_size_override("font_size", 17)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	copy.add_child(title)
	var health := RichTextLabel.new()
	health.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	health.bbcode_enabled = true
	health.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	health.fit_content = true
	health.scroll_active = false
	health.set_meta("life_unit", unit)
	health.text = _hover_life_text(unit, health)
	health.meta_underlined = false
	health.meta_hover_started.connect(_on_rule_guide_entered)
	health.meta_hover_ended.connect(_on_rule_guide_exited)
	health.add_theme_color_override("default_color", Color("#f2f2ef"))
	health.add_theme_color_override("font_color", Color("#f2f2ef"))
	health.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	health.mouse_filter = Control.MOUSE_FILTER_PASS
	copy.add_child(health)
	var modifiers := RichTextLabel.new()
	modifiers.bbcode_enabled = true
	modifiers.fit_content = true
	modifiers.scroll_active = false
	modifiers.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	modifiers.text = "[url=modifier:%d:physical]physical %s%d[/url] · [url=modifier:%d:magical][color=#c084fc]magic: %s%d[/color][/url]" % [unit.iun,
		"+" if unit.physical_modifier >= 0 else "", unit.physical_modifier,
		unit.iun, "+" if unit.magical_modifier >= 0 else "", unit.magical_modifier]
	modifiers.meta_underlined = false
	modifiers.meta_hover_started.connect(_on_rule_guide_entered)
	modifiers.meta_hover_ended.connect(_on_rule_guide_exited)
	modifiers.add_theme_color_override("default_color", Color("#c8c8c5"))
	modifiers.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	modifiers.mouse_filter = Control.MOUSE_FILTER_PASS
	copy.add_child(modifiers)
	var effects := _unit_effect_details(unit)
	if not effects.is_empty():
		var effect_text := RichTextLabel.new()
		effect_text.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		effect_text.bbcode_enabled = true
		effect_text.fit_content = true
		effect_text.scroll_active = false
		effect_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		effect_text.text = RuleGuide.decorate(effects)
		effect_text.meta_underlined = false
		effect_text.meta_hover_started.connect(_on_rule_guide_entered)
		effect_text.meta_hover_ended.connect(_on_rule_guide_exited)
		effect_text.add_theme_font_size_override("bold_font_size", 21)
		effect_text.add_theme_color_override("default_color", Color("#f2f2ef"))
		effect_text.add_theme_color_override("font_color", Color("#f2f2ef"))
		effect_text.add_theme_font_size_override("normal_font_size", 21)
		effect_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		effect_text.mouse_filter = Control.MOUSE_FILTER_PASS
		copy.add_child(effect_text)
	else:
		var effect_text := Label.new()
		effect_text.text = "No authored effects"
		effect_text.add_theme_font_size_override("font_size", 21)
		effect_text.add_theme_color_override("font_color", Color("#c8c8c5"))
		effect_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
		copy.add_child(effect_text)
	return row

## Joins compact actions and summarized triggers/continuous rules with single line breaks for the small hover card.
## _make_hover_unit_card() renders this as BBCode; descriptions are derived from reusable rule objects.
## Only definitions with active board trigger cues receive yellow emphasis.
## Magenta authored upgrade values link to their rule's source; actual maximum-life changes use their separate retained history.
func _unit_effect_details(unit: UnitInfo) -> String:
	var lines: PackedStringArray = []
	var upgrades := RegEx.new()
	upgrades.compile("\\[color=#ef70df\\]([^\\[]+)\\[/color\\]")
	for detail in RuleText.unit_lines(unit, board.highlighted_triggers(unit)):
		lines.append("• " + upgrades.sub(detail, "[url=upgrade:%d][color=#ef70df]$1[/color][/url]" % unit.iun, true))
	return "\n".join(lines)

## Phase-blink inspection uses the standard frame/position and captured source identity; death never removes a unit's stable Match identity.
## _refresh_hover_panel calls this before ordinary unit inspection; acknowledgement and pointer exit retain the usual fade lifecycle.
func _show_phase_trigger_hover() -> void:
	var execution: EffectExecution = Match.rules_runner.presentation_waiting
	if execution == null: return
	var unit := Match.get_unit(execution.source.id) if execution.source != null and execution.source.kind == TargetRef.Kind.UNIT else null
	for child in hover_content.get_children():
		hover_content.remove_child(child)
		child.queue_free()
	counter_pointer_inside = false
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", _hover_frame_style())
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hover_content.add_child(frame)
	var text := RichTextLabel.new()
	text.bbcode_enabled = true
	text.fit_content = true
	text.scroll_active = false
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_font_size_override("normal_font_size", 21)
	text.add_theme_color_override("default_color", Color("#f2f2ef"))
	text.meta_underlined = false
	text.mouse_filter = Control.MOUSE_FILTER_PASS
	text.meta_hover_started.connect(_on_rule_guide_entered)
	text.meta_hover_ended.connect(_on_rule_guide_exited)
	var attribution := ""
	if unit != null:
		attribution = "\n[color=#ffd84a]%s[/color] [color=%s](Player %d)[/color]" % [unit.name.replace("[", "[lb]"), "#ef7770" if unit.player == 1 else "#6da9ee", unit.player]
	text.text = RuleGuide.decorate("[color=#ffd84a]%s[/color]%s" % [RuleText.describe_effect(execution.definition, unit), attribution])
	frame.add_child(text)
	_set_hover_visible(true)
	_sync_hover_target_input(hover_panel)
	_layout_hover_panel()

## RichTextLabel metadata hover enters a glossary or live modifier summary without mutating the inspected rule.
func _on_rule_guide_entered(meta: Variant) -> void:
	var value := str(meta)
	if value.begins_with("modifier:") or value.begins_with("maxlife:") or value.begins_with("upgrade:"):
		rule_guide_key = value
		_update_rule_guide()
		return
	if not value.begins_with("guide:"): return
	rule_guide_key = value.trim_prefix("guide:")
	_update_rule_guide()

## Metadata exit clears only its own entry so rapid movement between adjacent terms cannot dismiss a newer tooltip.
func _on_rule_guide_exited(meta: Variant) -> void:
	if str(meta) != "guide:" + rule_guide_key and str(meta) != rule_guide_key: return
	rule_guide_key = ""
	_update_rule_guide()

## Ctrl transitions and metadata signals fade the separate guide; modifier summaries also appear on ordinary hover and read current values.
## Attack-icon guide keys include occurrence-specific sticker markers; RuleGuide.description adds their explanations on separate lines.
func _update_rule_guide() -> void:
	if rule_guide_panel == null: return
	var show_guide := hover_ctrl_held and not RuleGuide.description(rule_guide_key).is_empty()
	if rule_guide_key.begins_with("maxlife:") or rule_guide_key.begins_with("upgrade:"):
		var parts := rule_guide_key.split(":")
		var unit := Match.get_unit(parts[1].to_int()) if parts.size() == 2 else null
		show_guide = unit != null
		if unit != null:
			rule_guide_label.text = "Maximum life\n" + "\n".join(unit.max_life_breakdown()) if parts[0] == "maxlife" else "Effect from " + unit.name + "\nThis number is an upgrade granted by the described effect."
	elif rule_guide_key.begins_with("modifier:"):
		var parts := rule_guide_key.split(":")
		var unit := Match.get_unit(parts[1].to_int()) if parts.size() == 3 else null
		show_guide = unit != null
		if unit != null:
			rule_guide_label.text = ("Magical" if parts[2] == "magical" else "Physical") + " modifiers\n" + "\n".join(unit.modifier_breakdown(parts[2] == "magical"))
	elif show_guide:
		rule_guide_label.text = RuleGuide.description(rule_guide_key)
	if show_guide:
		rule_guide_panel.reset_size()
	if rule_guide_tween != null: rule_guide_tween.kill()
	rule_guide_tween = create_tween()
	rule_guide_tween.tween_property(rule_guide_panel, "modulate:a", 1.0 if show_guide else 0.0, 0.15)

## Reads a named counter from the unit's properties without changing game state.
## _make_hover_unit_card() uses it to show the current Stun count.
func _unit_counter(unit: UnitInfo, key: StringName) -> int:
	for prop in unit.props:
		if prop != null and prop.name == key: return prop.value
	return 0

## Hover troop/counter builders use the dark gold-trimmed frame previously used by side cards.
## Source 256px guides L165/R34/T37/B32 become L22/R20/T22/B17 after cropping (143,15,99,226).
## Content margins keep portraits, light labels and controls clear of the border.
func _hover_frame_style() -> StyleBoxTexture:
	if hover_frame_style != null: return hover_frame_style
	var atlas := AtlasTexture.new()
	atlas.atlas = load("res://assets/ui/side-wood-frame.png")
	atlas.region = Rect2(143, 15, 99, 226)
	atlas.filter_clip = true
	hover_frame_style = StyleBoxTexture.new()
	hover_frame_style.texture = atlas
	hover_frame_style.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	hover_frame_style.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	hover_frame_style.set_texture_margin(SIDE_LEFT, 22.0)
	hover_frame_style.set_texture_margin(SIDE_RIGHT, 20.0)
	hover_frame_style.set_texture_margin(SIDE_TOP, 22.0)
	hover_frame_style.set_texture_margin(SIDE_BOTTOM, 17.0)
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		hover_frame_style.set_content_margin(side, 24.0)
	return hover_frame_style

## Fits the hover host at the lower right until Ctrl-dragged; clamps display without overwriting the user's preferred position.
## HUD refreshes, viewport resizing and deferred text layout can temporarily enlarge content; later layouts restore the preferred position.
## Default inspection sits half the 40px hand-pointer height higher; Ctrl-dragged placement remains under direct user control.
func _layout_hover_panel() -> void:
	if hover_panel == null or not is_instance_valid(hover_panel): return
	var view_size := get_viewport().get_visible_rect().size
	var margin := clampf(view_size.x * 0.014, 8.0, 22.0)
	var width := minf(360.0, maxf(0.0, view_size.x - margin * 2.0))
	hover_panel.size.x = width
	var content_height := hover_content.get_combined_minimum_size().y + 4.0
	var panel_height := minf(maxf(76.0, content_height), maxf(76.0, view_size.y - margin * 2.0))
	if hover_custom_position:
		hover_panel.position = Vector2(clampf(hover_preferred_position.x, 0.0, maxf(0.0, view_size.x - width)), clampf(hover_preferred_position.y, 0.0, maxf(0.0, view_size.y - panel_height)))
	else:
		hover_panel.position = Vector2(maxf(margin, view_size.x - width - margin), maxf(margin, view_size.y - panel_height - margin - 20.0))
	hover_panel.size = Vector2(width, panel_height)

## Match state/runner/cue signals schedule one repaint for an event burst; direct input handlers may still request an immediate HUD update.
## The deferred call does not own any rules continuation, command payment or animation acknowledgement.
func _queue_hud_refresh() -> void:
	if _hud_refresh_queued: return
	_hud_refresh_queued = true
	call_deferred("_flush_hud_refresh")

## Paints one queued final state; an intervening direct _refresh_hud already satisfied the request and makes this callback a no-op.
func _flush_hud_refresh() -> void:
	if not _hud_refresh_queued: return
	_refresh_hud()

## Synchronizes retained unit trays, player resources, snapshot availability, hover details and the selected parchment menu once per queued burst.
## Match.state_changed and RulesRunner.idle call it after state/choice transitions; player info reads authoritative allowances and counters.
## Retained player-info rows use owner colors and bump individual resource lines when authoritative values change.
## Trigger-cue notifications refresh hover details; the inn-sign blink remains the visible acknowledgement affordance.
func _refresh_hud() -> void:
	_hud_refresh_queued = false
	_sync_parchment_menu()
	if status_header == null: return
	if network_status != null:
		network_status.text = "P%d · %s" % [NetworkSession.local_player, "Your turn" if Match.active_player == NetworkSession.local_player else "Opponent's turn"] if NetworkSession.both_connected() else "Disconnected · Reconnect"
	if save_snapshot_button != null:
		save_snapshot_button.disabled = NetworkSession.online or reset_requested or pending_deployment >= 0 or not SnapshotStore.can_save()
	for player_id in [1, 2]:
		var list: BoxContainer = card_lists.get(player_id)
		if list == null: continue
		var player_cards := Match.army.filter(func(unit: UnitInfo) -> bool: return unit.player == player_id and unit.t_state != Enum.t_state.DEPLOYED)
		var info: Control = player_info_panels.get(player_id)
		if info != null: info.sync_player(Match.players[player_id])
		_sync_side_cards(list, player_cards)
	_layout_hud()
	_refresh_hover_panel()

## Saves the stable current match so the next Godot launch resumes this exact state.
## _on_save_pressed calls this immediately after starting click feedback; MatchSnapshot rejects busy or non-Action phases.
func _save_snapshot() -> void:
	if NetworkSession.online: return
	if pending_deployment >= 0:
		status_message = "Finish or cancel the deployment selection before saving."
		_refresh_hud()
		return
	if SnapshotStore.save_snapshot():
		status_message = "Snapshot saved. It will load the next time Godot starts."
	elif not SnapshotStore.can_save():
		status_message = "Save is available after the current action finishes."
	else:
		status_message = "Could not write the snapshot to Godot's user data folder."
	_refresh_hud()

## Deletes the saved snapshot and reloads a fresh turn-one match in the current window.
## _on_reset_pressed calls this after its finite click animation, so future launches also start from the new game.
## Online Leave closes room membership instead; it never deletes the offline snapshot.
func _reset_match() -> void:
	if NetworkSession.online:
		if not NetworkSession.authenticated:
			reset_requested = false
			reset_match_button.disabled = false
			_on_network_notice("Reconnect first, then leave the room.")
			return
		NetworkSession.lobby_command({"type": "leave"})
		return
	SnapshotStore.delete_snapshot()
	get_tree().reload_current_scene()

## _build_hud() creates a side column containing separate player-info and unit-roster panels with the same 90%-opaque wood frame.
## _refresh_hud() updates independent animated info rows and retains unit portraits; _layout_hud() sizes both players’ columns equally.
## Player info uses enlarged 16px text in its owner's light red/blue hover-info color.
func _make_player_tray(root: Control, player_id: int) -> void:
	var side_column := VBoxContainer.new()
	side_column.name = "Player%dSideColumn" % player_id
	side_column.add_theme_constant_override("separation", 8)
	root.add_child(side_column)
	player_trays[player_id] = side_column
	var info_panel := PanelContainer.new()
	info_panel.name = "PlayerInfo"
	info_panel.add_theme_stylebox_override("panel", _side_card_frame_style())
	side_column.add_child(info_panel)
	var panel := PanelContainer.new()
	panel.name = "Player%dTray" % player_id
	panel.clip_contents = true
	panel.add_theme_stylebox_override("panel", _side_card_frame_style())
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side_column.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 5)
	panel.add_child(column)
	var info := preload("res://scripts/ui/player_info.gd").new()
	info.add_theme_constant_override("separation", 0)
	info_panel.add_child(info)
	player_info_panels[player_id] = info
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	var list := BoxContainer.new()
	list.vertical = true
	list.add_theme_constant_override("separation", 5)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	card_lists[player_id] = list

## _refresh_hud() builds a square unit-only portrait with stand/sit playback owned by the presentation component.
## Existing hover inspection remains available; clicking the portrait replaces the former Deploy/Choose unit buttons.
func _make_card(unit: UnitInfo) -> Control:
	var card := preload("res://scripts/ui/side_unit_portrait.gd").new()
	card.setup(unit, BoardCharacter.card_art_path(unit))
	card.mouse_entered.connect(_on_card_hovered.bind(unit.iun))
	card.mouse_exited.connect(_on_card_unhovered.bind(unit.iun))
	card.pressed.connect(_on_side_card_pressed)
	return card

## Portrait clicks preserve existing authoritative legality: hand cards choose deployment, active deployed cards select their default action.
## No inline command buttons or statistics are added back to the side tray.
## Clicking an owned hand unit with no deployments remaining bumps that player's deployments line instead of opening target selection.
func _on_side_card_pressed(unit_id: int) -> void:
	if NetworkSession.online and NetworkSession.local_player != Match.active_player: return
	var unit := Match.get_unit(unit_id)
	if unit == null or unit.player != Match.active_player or Match.winner != 0: return
	if unit.t_state == Enum.t_state.UNDEPLOYED:
		if Match.players[unit.player].deployments_remaining <= 0:
			var info: Control = player_info_panels.get(unit.player)
			if info != null: info.bump_deployments()
			return
		if Match.phase == Match.Phase.ACTION and not Match.rules_runner.busy() and _has_valid_deployment(unit_id): _begin_deployment(unit_id)
	elif unit.t_state == Enum.t_state.DEPLOYED:
		_select_unit(unit_id)

## HUD refresh retains exact unit-instance portraits so animation, hover and scrolling survive ordinary match updates.
## Hand portraits precede a separator and defeated portraits; deployed/replaced entries fade away while retained controls keep hover state.
## Posture follows pending_deployment, the same identity used for deployment hex highlights; mouse exit never clears that selection.
func _sync_side_cards(list: BoxContainer, units: Array) -> void:
	var existing := {}
	var divider := list.get_node_or_null("DefeatedDivider") as HSeparator
	if divider == null:
		divider = HSeparator.new()
		divider.name = "DefeatedDivider"
		divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
		list.add_child(divider)
	divider.visible = units.any(func(unit: UnitInfo) -> bool: return unit.t_state == Enum.t_state.DEFEATED)
	for child in list.get_children():
		if child == divider: continue
		if child.get_meta("unit_instance", null) not in units:
			if child.has_method("fade_out"): child.fade_out()
			else: child.queue_free()
		elif not child.removing:
			existing[child.get_meta("unit_id")] = child
	var index := 0
	var ordered := units.filter(func(unit: UnitInfo) -> bool: return unit.t_state == Enum.t_state.UNDEPLOYED)
	ordered.append_array(units.filter(func(unit: UnitInfo) -> bool: return unit.t_state == Enum.t_state.DEFEATED))
	var divider_placed := false
	for unit: UnitInfo in ordered:
		if unit.t_state == Enum.t_state.DEFEATED and not divider_placed:
			list.move_child(divider, index)
			index += 1
			divider_placed = true
		var card: Control = existing.get(unit.iun)
		if card == null:
			card = _make_card(unit)
			card.modulate.a = 0.0
			list.add_child(card)
			card.create_tween().tween_property(card, "modulate:a", 1.0, 0.18)
		card.set_hand_selected(unit.iun == pending_deployment)
		list.move_child(card, index)
		index += 1

## Repositions top-centered parchment controls, two card trays and hover window for compact or landscape viewports.
## Both landscape trays share width, height and top margin, retaining their screen-edge anchors.
## The viewport size_changed signal calls this; GuerraBoard independently refits its camera.
## Both columns keep their original positions; independent bottom-corner arrows toggle only their corresponding rosters.
func _layout_hud() -> void:
	if status_header == null or not is_instance_valid(status_header): return
	var view_size := get_viewport().get_visible_rect().size
	var margin := clampf(view_size.x * 0.014, 8.0, 22.0)
	var compact := view_size.x < 900.0
	if compact:
		var tray_top := view_size.y * 0.65
		var half_width := (view_size.x - margin * 3.0) * 0.5
		status_header.position = Vector2(margin, 5.0)
		status_header.size = Vector2(view_size.x - margin * 2.0, 44.0)
		for player_id in [2, 1]:
			var panel: Control = player_trays.get(player_id)
			var list: BoxContainer = card_lists.get(player_id)
			if panel == null or list == null: continue
			panel.position = Vector2(margin if player_id == 1 else margin * 2.0 + half_width, tray_top)
			panel.size = Vector2(half_width, maxf(0.0, view_size.y - tray_top - margin))
			list.vertical = true
			list.custom_minimum_size = Vector2.ZERO
			var scroll := list.get_parent() as ScrollContainer
			scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
			scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
			for card in list.get_children(): _size_card(card, half_width - 18.0, true)
	else:
		var tray_width := clampf(view_size.x * 0.095, 96.0, 124.0)
		status_header.position = Vector2(tray_width + margin, 5.0)
		status_header.size = Vector2(view_size.x - 2.0 * (tray_width + margin), 44.0)
		for player_id in [2, 1]:
			var panel: Control = player_trays.get(player_id)
			var list: BoxContainer = card_lists.get(player_id)
			if panel == null or list == null: continue
			panel.position = Vector2(margin if player_id == 1 else view_size.x - tray_width - margin, margin)
			panel.size = Vector2(tray_width, view_size.y - 2.0 * margin)
			list.vertical = true
			list.custom_minimum_size = Vector2(0.0, 0.0)
			var scroll := list.get_parent() as ScrollContainer
			scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
			scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
			for card in list.get_children(): _size_card(card, tray_width, false)
	for player_id in side_drawers:
		var drawer: Dictionary = side_drawers[player_id]
		var button: Control = drawer.button
		button.position = Vector2(0.0 if player_id == 1 else view_size.x - button.size.x, maxf(0.0, view_size.y - button.size.y - 5.0))
		_apply_side_drawer(drawer.progress, player_id)
	_layout_hover_panel()

## _layout_hud() fits each square portrait inside the wood frame/scroll gutter without changing the single-column layout.
func _size_card(card: Control, width: float, _compact: bool) -> void:
	if card is HSeparator: return
	var style := _side_card_frame_style()
	var padding := style.get_content_margin(SIDE_LEFT) + style.get_content_margin(SIDE_RIGHT)
	var side := clampf(width - padding - 12.0, 48.0, 128.0)
	card.custom_minimum_size = Vector2.ONE * side
	card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

## Adds a parchment-toned border and background to card/tray panels.
## _make_player_tray() and _make_card() use it to match the JS game's paper palette.
func _panel_style(fill: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(5)
	style.content_margin_left = 4.0
	style.content_margin_right = 4.0
	style.content_margin_top = 4.0
	style.content_margin_bottom = 4.0
	return style

## Applies matching warm normal/hover/pressed colors to card action buttons.
## _make_card() calls it for Deploy and action controls; nearest filtering preserves pixel icon edges.
## Uses the enlarged Jersey 10 text sizes (approximately 20% above the original HUD scale).
func _style_button(button: Button) -> void:
	button.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var normal := _panel_style(Color("#75502e"), Color("#4b321e"))
	var hover := _panel_style(Color("#916637"), Color("#4b321e"))
	var pressed := _panel_style(Color("#5c4027"), Color("#4b321e"))
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("disabled", _panel_style(Color("#8b806d"), Color("#6a5944")))
	button.add_theme_color_override("font_color", Color("#fff0cf"))
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_disabled_color", Color("#ded1b8"))
	button.add_theme_font_size_override("font_size", 11)

## Tests whether at least one tile currently satisfies Match's full deployment rule.
## Side portrait clicks use this before offering deployment destinations.
func _has_valid_deployment(unit_id: int) -> bool:
	for tile in Match.map:
		if Match.can_deploy(unit_id, tile.hex_id): return true
	return false

## Enters destination choice for one undeployed card and highlights controlled vacant tiles.
## The side portrait click handler calls this; _on_hex_selected commits the choice.
func _begin_deployment(unit_id: int) -> void:
	if Match.rules_runner.busy(): return
	selected_unit_id = -1
	board.select_unit(-1)
	pending_deployment = unit_id
	status_message = ""
	var legal_hexes: Array[int] = []
	for tile in Match.map:
		if Match.can_deploy(unit_id, tile.hex_id): legal_hexes.append(tile.hex_id)
	board.show_hex_choices(legal_hexes)
	_refresh_hud()

## Applies the pending deployment only when the clicked hex still satisfies current rules.
## Board.hex_selected calls this; Match.deploy rechecks before changing state.
func _on_hex_selected(hex_id: int) -> void:
	if pending_deployment < 0: return
	var unit_id := pending_deployment
	if Match.deploy(unit_id, hex_id):
		pending_deployment = -1
		board.show_hex_choices([])
		_refresh_hud()

## Clears a deployment card and its highlights when the player clicks outside legal tiles.
## GuerraBoard.selection_abandoned emits this for invalid tile clicks and unrelated viewport clicks.
func _on_selection_abandoned() -> void:
	pending_deployment = -1
	selected_unit_id = -1
	board.select_unit(-1)
	status_message = "Selection cleared."
	_refresh_hud()

## Starts one object-authored action with target preview before its cost is submitted.
## Unit clicks call this through _select_unit(); inactive units are ignored and RulesRunner rejects competing commands.
## All single-phrase actions check legal subjects/targets before submission; impossible buttons and shortcuts never start a command.
func _begin_unit_action(unit_id: int, effect_index: int) -> void:
	if Match.rules_runner.busy():
		if unit_id == selected_unit_id: _switch_pending_action(effect_index)
		return
	var unit := Match.get_unit(unit_id)
	if unit == null or not unit.active or effect_index < 0 or effect_index >= unit.effects.size(): return
	if not _action_available(unit, effect_index): return
	selected_unit_id = unit_id
	board.select_unit(unit_id)
	pending_deployment = -1
	board.show_hex_choices([])
	var effect := unit.effects[effect_index]
	var target_error := _stun_target_error(effect, unit_id)
	if not target_error.is_empty():
		status_message = target_error
		_refresh_hud()
		return
	status_message = "Choose a highlighted hex for %s to %s." % [unit.name, _effect_label(effect, unit)]
	Match.rules_runner.submit(effect, TargetRef.unit(unit_id), true)

## Action entry/switch queries Stun recipients before cancelling an unpaid preview or submitting a command.
## Uses selector/conversion/legality with numeric preview bindings, so unpaid X is a positive minimum rather than a definition object.
## Returns a visible reason when no enemy is legal, keeping the selected unit available for movement or another action.
func _stun_target_error(effect: Effect, unit_id: int) -> String:
	if not effect.consequence is Effect.ConsequencePhrase: return ""
	var phrase := effect.consequence as Effect.ConsequencePhrase
	if phrase.verb.name != &"stun": return ""
	var ctx := RuleContext.new(TargetRef.unit(unit_id))
	ctx.subject = ctx.source
	ctx.preview_numbers = true
	var verb := phrase.verb.bound_to(ctx)
	var result := TargetResolver.resolve(phrase.target, phrase.verb.target_kind, ctx)
	if not result.error.is_empty(): return result.error
	for target: TargetRef in result.candidates:
		if verb.can_apply(ctx.subject, target): return ""
	var radius := int(phrase.verb.user_params[1])
	if radius < 0: return "Stun needs a deployed enemy unit. Choose another action."
	return "Stun needs an enemy within %d hex%s. Choose another action or move closer." % [radius, "" if radius == 1 else "es"]

## Selects a friendly figure, opens its parchment menu and starts Walk/Fly as the default unpaid target preview.
## Board.unit_selected and side portrait clicks call this; inactive units are ignored before any selection or pose change.
## A different active unit can replace an unpaid preview; its selection waits until cancellation releases the runner.
func _select_unit(unit_id: int) -> void:
	if NetworkSession.online and NetworkSession.local_player != Match.active_player: return
	if Match.winner != 0: return
	var unit := Match.get_unit(unit_id)
	if unit == null or not unit.active or unit.player != Match.active_player or unit.t_state != Enum.t_state.DEPLOYED: return
	if Match.rules_runner.busy():
		if unit_id == selected_unit_id or not _can_switch_pending_action() \
				or pending_unit_switch_id >= 0 or pending_action_switch_index >= 0: return
		pending_unit_switch_id = unit_id
		Match.rules_runner.active.cancel()
		return
	selected_unit_id = unit_id
	board.select_unit(unit_id)
	var default_index := _default_action_index(unit, _ordered_effect_indices(unit))
	if default_index >= 0 and _action_available(unit, default_index):
		_begin_unit_action(unit_id, default_index)
	else:
		status_message = "Choose an action or press its number."
	_refresh_hud()

## Maps a one-based keyboard/card slot to this unit's movement-first action ordering.
## _select_unit() uses it so action keys work consistently across different cards.
func _action_index_for_slot(ordered_indices: Array[int], slot: int) -> int:
	var offset := slot - 1
	return ordered_indices[offset] if offset >= 0 and offset < ordered_indices.size() else -1

## Orders movement first so Move/Fly is slot 1 when the card supports it.
## _select_unit() uses this ordering for keyboard slots and fallback actions.
func _ordered_effect_indices(unit: UnitInfo) -> Array[int]:
	var indices: Array[int] = []
	for index in unit.effects.size(): indices.append(index)
	indices.sort_custom(func(left: int, right: int) -> bool:
		var left_movement := _is_movement_effect(unit.effects[left])
		var right_movement := _is_movement_effect(unit.effects[right])
		if left_movement != right_movement: return left_movement
		return left < right)
	return indices

## Chooses the first Move/Fly effect, falling back to the first printed action.
## _select_unit() calls this if the requested keyboard slot is unavailable.
func _default_action_index(unit: UnitInfo, ordered_indices: Array[int]) -> int:
	for index in ordered_indices:
		if _is_movement_effect(unit.effects[index]): return index
	return ordered_indices[0] if not ordered_indices.is_empty() else -1

## Identifies the reusable Move/Fly verb used to order the card's action menu.
## _ordered_effect_indices() and _default_action_index() call this helper.
func _is_movement_effect(effect: Effect) -> bool:
	if effect == null or not effect.consequence is Effect.ConsequencePhrase: return false
	var phrase := effect.consequence as Effect.ConsequencePhrase
	return phrase.verb.name in [&"move", &"fly"]

## Formats the authored verb and magnitude as the unit's short HUD button label.
## _begin_unit_action() and _switch_pending_action() use this short status label; parchment rows and hover rules use their own shared formatters.
func _effect_label(effect: Effect, unit: UnitInfo = null) -> String:
	if effect == null or not effect.consequence is Effect.ConsequencePhrase: return "Action"
	var phrase := effect.consequence as Effect.ConsequencePhrase
	var name := String(phrase.verb.name).replace("_", " ").capitalize()
	var params := phrase.verb.user_params
	var icon := _action_icon(phrase.verb.name)
	if phrase.verb.name in [&"bow", &"fire", &"cannon", &"gore", &"mend", &"stun"] and not params.is_empty():
		var action_range := int(params[1]) if params.size() >= 2 and phrase.verb.name != &"fire" else EffectText.selector_range(phrase.target)
		var amount := EffectText._numeric(params[0])
		if phrase.verb.name == &"bow" and unit != null:
			amount += unit.effective_bow_bonus().x
			action_range += unit.effective_bow_bonus().y
		var value: String = params[0].symbol if params[0] is RuleNumber else str(amount)
		return "%s %s %s%s" % [icon, name, value, "/%d" % action_range if action_range >= 0 else ""]
	if phrase.verb.name in [&"push", &"pull", &"push_bomb", &"pull_bomb"] and params.size() >= 2:
		return "%s %s %d/%d" % [icon, name, int(params[0]), int(params[1])]
	if phrase.verb.name == &"bomb_throw" and params.size() >= 2:
		return "%s %s %d/%d" % [icon, name, int(params[0]), int(params[1])]
	if phrase.verb.name in [&"shield", &"mshield"] and not params.is_empty():
		return "%s %s %d" % [icon, name, int(params[0])]
	if phrase.verb.name == &"upgrade_bow" and params.size() >= 2:
		return "%s +%d/+%d" % [icon, int(params[0]), int(params[1])]
	if phrase.verb.name == &"up_life" and params.size() >= 2:
		return RuleText.life_change(int(params[0]), int(params[1]), unit.player)
	if phrase.verb.name in [&"move", &"fly"] and not params.is_empty():
		return "%s %s %d" % [icon, name, int(params[0])]
	return "%s %s" % [icon, name] if not icon.is_empty() else name

## Keeps fallback glyphs in plain labels; PixelLab actions use Button.icon instead of unsupported BBCode.
## _effect_label() adds this to each selectable normal action in the card tray.
func _action_icon(action: StringName) -> String:
	if not GameIcons.action_path(action).is_empty(): return ""
	if action == &"up_life": return "❤️"
	if action == &"upgrade_bow": return "🏹"
	return GameIcons.fallback_glyph(action)

## Displays the completed command result after RulesRunner handles payment and followups.
## RulesRunner.command_finished connects here; this handler never spends tokens.
## Cancelling for a unit switch first deselects the old unit (sit), then selects the new one (stand) after runner release.
func _on_effect_completed(success: bool, cost_paid: bool, _action_free: bool) -> void:
	if NetworkSession.online and (pending_unit_switch_id >= 0 or pending_action_switch_index >= 0):
		_queue_hud_refresh()
		return
	if pending_unit_switch_id >= 0:
		var next_unit := pending_unit_switch_id
		pending_unit_switch_id = -1
		selected_unit_id = -1
		board.select_unit(-1)
		_select_unit(next_unit)
		return
	if pending_action_switch_index >= 0:
		var next_effect_index := pending_action_switch_index
		pending_action_switch_index = -1
		_begin_unit_action(selected_unit_id, next_effect_index)
		return
	selected_unit_id = -1
	preferred_action_slot = 1
	board.select_unit(-1)
	if success:
		status_message = "Action completed."
	elif cost_paid:
		status_message = "Action cancelled after payment; the Stun cost remains."
	else:
		status_message = "Action cancelled before payment."
	_refresh_hud()

## Reports whether the selected command is still a cancellable, pre-payment target preview.
## The number keys and selected card's action buttons use this to allow a safe action switch.
## Online switching waits for explicit cancellation/host confirmation instead of starting an unreplicated follow-up from a completion signal.
func _can_switch_pending_action() -> bool:
	if NetworkSession.online and (NetworkSession.local_player != Match.active_player or NetworkSession.pending_command): return false
	var execution := Match.rules_runner.active
	return execution != null and execution.defer_cost_until_target and not execution.cost_paid \
		and execution.status == EffectExecution.Status.CONSEQUENCE and execution.current != null \
		and execution.current.status in [PhraseExecution.Status.SUBJECT, PhraseExecution.Status.TARGET] \
		and execution.source != null and execution.source.kind == TargetRef.Kind.UNIT \
		and execution.source.id == selected_unit_id

## Cancels an uncommitted target preview and starts another action after RulesRunner releases it.
## Number keys and the selected card's action buttons call this without paying either cost.
## Unavailable actions preserve the existing unpaid preview; the same read-only check drives disabled parchment rows.
func _switch_pending_action(effect_index: int) -> void:
	if not _can_switch_pending_action() or pending_action_switch_index >= 0: return
	var unit := Match.get_unit(selected_unit_id)
	if unit == null or not unit.active or effect_index < 0 or effect_index >= unit.effects.size(): return
	if not _action_available(unit, effect_index): return
	var target_error := _stun_target_error(unit.effects[effect_index], unit.iun)
	if not target_error.is_empty():
		status_message = target_error
		_refresh_hud()
		return
	if not Match.rules_runner.available(unit.effects[effect_index], TargetRef.unit(unit.iun)):
		status_message = "%s is not available right now." % _effect_label(unit.effects[effect_index], unit)
		_refresh_hud()
		return
	pending_action_switch_index = effect_index
	status_message = "Changing action…"
	Match.rules_runner.active.cancel()

## Runner execution starts queue one HUD paint after choice setup instead of repainting both immediately and again deferred.
## Match remains authoritative during the short UI delay, so a stale-looking button cannot submit a competing command.
func _on_execution_started(_execution: EffectExecution) -> void:
	_queue_hud_refresh()

## Relay feedback uses the ordinary HUD status; peer disconnects preserve the board for reconnect rather than resetting it.
func _on_network_notice(text: String) -> void:
	status_message = text
	if network_status != null: network_status.tooltip_text = text
	_queue_hud_refresh()


## Adds a short status line for deployment, combat, displacement, Return and activity; off-board target labels retain stable card identity.
## Match.action_event calls this; game rules remain in Match and the resolvers.
func _on_action_event(event: EffectEvent) -> void:
	if event == null: return
	if NetworkSession.online and event.action == &"deploy" and event.subject != null and pending_deployment == event.subject.id:
		pending_deployment = -1
		board.show_hex_choices([])
	if event.action == &"deploy": status_message = "%s deployed." % event.subject.label()
	elif event.action == &"return_to_hand": status_message = "%s returned to hand." % event.target.label()
	elif event.action in [&"fire", &"bow", &"cannon", &"gore"] and event.stage == &"target":
		status_message = "%s declared %s at %s." % [event.subject.label(), String(event.action).capitalize(), event.target.label()]
	elif event.action in [&"fire", &"bow", &"cannon", &"gore", &"bomb_explosion"] and event.stage == &"resolved":
		status_message = "Bomb blast resolved." if event.action == &"bomb_explosion" else "%s resolved." % String(event.action).capitalize()
	elif event.action == &"bash":
		status_message = "Bash started." if event.stage == &"target" else "Bash resolved."
	elif event.action in [&"push", &"pull", &"push_bomb", &"pull_bomb"]:
		status_message = "%s completed." % String(event.action).replace("_", " ").capitalize()
	elif event.action == &"move":
		status_message = "%s completed." % String(event.data.get("movement_kind", "move")).capitalize()
	elif event.action == &"mend":
		status_message = "%s healed %d life." % [event.target.label(), int(event.data.get("amount", 0))]
	elif event.action == &"stun":
		status_message = "%s gained %d Stun." % [event.target.label(), int(event.data.get("amount", 0))]
	elif event.action == &"die": status_message = "%s was defeated." % event.subject.label()
	elif event.action == &"bomb_throw": status_message = "Bomb placed or strengthened."
	elif event.action == &"bomb_defuse": status_message = "Inert bomb defused."
	elif event.action == &"bomb_light": status_message = "Bomb lit; blast queued."

## Produces the short status shown beside each card in the local roster.
## _refresh_hud() calls this while rebuilding unit rows.
func _state_name(unit: UnitInfo) -> String:
	match unit.t_state:
		Enum.t_state.UNDEPLOYED: return "in hand"
		Enum.t_state.DEPLOYED: return "active" if unit.active else "inactive"
		Enum.t_state.DEFEATED: return "defeated"
	return "unknown"

## Converts Match's phase enum to a readable HUD label.
## _refresh_hud() calls this; it does not change turn state.
func _phase_name(value: int) -> String:
	match value:
		Match.Phase.START: return "Start"
		Match.Phase.ACTION: return "Action"
		Match.Phase.ACTION_RESOLVE: return "Action resolve"
		Match.Phase.COMBAT_RESOLVE: return "Combat resolve"
		Match.Phase.END: return "End"
	return "Unknown"

## Side trays use the newly edited PixelLab broken-plank frame; square unit portraits sit inside its tiled interior.
## Source L21/R134/T173/B19 guides become L13/R14/T13/B12 after cropping transparent bounds (8,160,128,89).
## Original nine-slice corners stay fixed; 14px content padding and narrower trays reduce framing without shrinking unit art.
## Only the frame texture uses 90% opacity; portraits and other tray contents retain their own opacity.
func _side_card_frame_style() -> StyleBoxTexture:
	if side_frame_style != null: return side_frame_style
	var atlas := AtlasTexture.new()
	atlas.atlas = load("res://assets/ui/side-cards-wood-frame.png")
	atlas.region = Rect2(8, 160, 128, 89)
	atlas.filter_clip = true
	side_frame_style = StyleBoxTexture.new()
	side_frame_style.texture = atlas
	side_frame_style.modulate_color = Color(1, 1, 1, 0.9)
	side_frame_style.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	side_frame_style.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	side_frame_style.set_texture_margin(SIDE_LEFT, 13.0)
	side_frame_style.set_texture_margin(SIDE_RIGHT, 14.0)
	side_frame_style.set_texture_margin(SIDE_TOP, 13.0)
	side_frame_style.set_texture_margin(SIDE_BOTTOM, 12.0)
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]: side_frame_style.set_content_margin(side, 14.0)
	return side_frame_style

## _refresh_hud() creates one menu per selected deployed unit and reverses the old menu on deselection, defeat or turn change.
## Existing menus survive refreshes; switching units waits for closed before opening the latest selected unit's menu.
func _sync_parchment_menu() -> void:
	var unit := Match.get_unit(selected_unit_id)
	var wanted := unit != null and unit.t_state == Enum.t_state.DEPLOYED and unit.active and unit.player == Match.active_player and Match.winner == 0
	if is_instance_valid(parchment_menu):
		if wanted and not parchment_menu.is_queued_for_deletion() and not parchment_menu.closing and parchment_menu.unit_id == selected_unit_id: return
		parchment_menu.begin_close()
		return
	if not wanted: return
	parchment_menu = preload("res://scripts/ui/parchment_actions.gd").new()
	parchment_menu.setup(self, unit)
	parchment_menu.closed.connect(_on_parchment_closed)
	overlay.add_child(parchment_menu)

## The closing menu emits closed after its last reverse frame; defer replacement until its node has queued deletion.
## Resolves the current selected identity at replacement time so rapid switching opens only the latest unit's actions.
func _on_parchment_closed() -> void:
	parchment_menu = null
	call_deferred("_sync_parchment_menu")

## Parchment rows use magnitude, shared PixelLab icon and range, with the shortcut independently aligned on the left.
## Reads printed numeric parameters/selectors including Bow bonuses; movement flags are never displayed as ranges.
## The Soul conversion action uses its explicit resource-cost wording rather than an internal grant verb name.
## Uses EffectText's shared qualifier formatter so F/T/P and action-free stickers match hover descriptions, including legacy timing flags.
## Life changes share current-heart-maximum notation and neutral numbers with detailed hover clauses.
## Upgrade rows reuse EffectText's damage/range-upgrade-radius notation instead of confusing the two deltas with reach.
func _parchment_action_text(effect: Effect, unit: UnitInfo) -> String:
	if effect == null: return "Action"
	if effect.consequence is Effect.ConsequenceSequence:
		var last: Effect.Phrase = effect.consequence.phrases.back()
		if last.verb.name == &"upgrade_ability": return EffectText._steps(effect.consequence, unit)
		return "Action"
	if not effect.consequence is Effect.ConsequencePhrase: return "Action"
	var phrase := effect.consequence as Effect.ConsequencePhrase
	var name := phrase.verb.name
	var ctx := RuleContext.new(TargetRef.unit(unit.iun))
	ctx.subject = ctx.source
	var params := phrase.verb.bound_to(ctx).user_params
	if name == &"grant_deployments" and effect.cost is Effect.CostBundle: return "2 Soul → +1 deploy"
	if name == &"up_life" and params.size() >= 2: return RuleText.life_change(int(params[0]), int(params[1]), unit.player, 24)
	if name == &"reset": return "Reset"
	if name == &"return_to_hand": return "return"
	if name == &"change_counter" and phrase.target is Selectors.PropertyOf \
			and not phrase.verb.user_params.is_empty() and phrase.verb.user_params[0] is RuleNumber:
		return "+X %s" % String(phrase.target.key)
	if name == &"change_counter" and phrase.target is Selectors.PropertyOf: return "%+d %s" % [params[0], String(phrase.target.key)]
	if name == &"upgrade_bow": return "+%d %s +%d" % [params[0], GameIcons.bb(&"bow", unit.player, 24), params[1]]
	if name == &"grant_action_values":
		return ("[lb]A[rb] " if phrase.action_free else "") + EffectText._action_grant(params[0], params[1])
	var icon := GameIcons.bb(name, unit.player, 24)
	if icon.is_empty(): icon = _action_icon(name)
	if icon.is_empty(): icon = String(name).capitalize()
	var amount := str(params[0]) if not params.is_empty() else ""
	if not params.is_empty() and phrase.verb.user_params[0] is RuleNumber: amount = phrase.verb.user_params[0].symbol
	var reach := ""
	if name in [&"bow", &"fire", &"cannon", &"gore", &"mend", &"stun", &"push", &"pull", &"push_bomb", &"pull_bomb", &"bomb_throw"]:
		var distance := int(params[1]) if params.size() >= 2 and name != &"fire" else EffectText.selector_range(phrase.target)
		if name == &"fire": distance += unit.ability_bonus(phrase.verb).y
		if name == &"bow":
			amount = EffectText.action_value(int(params[0]) + unit.effective_bow_bonus().x, int(phrase.verb.user_params[0]))
			distance += unit.effective_bow_bonus().y
		elif not phrase.verb.user_params[0] is RuleNumber:
			amount = EffectText.action_value(int(params[0]), int(phrase.verb.user_params[0]))
		if distance >= 0:
			var printed_distance := int(phrase.verb.user_params[1]) if params.size() >= 2 and name != &"fire" else EffectText.selector_range(phrase.target)
			reach = EffectText.action_value(distance, printed_distance)
	elif params.size() >= 2 and typeof(params[1]) in [TYPE_INT, TYPE_FLOAT]: reach = str(params[1])
	return "%s%s %s %s" % [amount, RuleText._qualifiers(phrase), icon, reach]

## Parchment buttons and action/shortcut entry points share the authoritative, read-only command query with Match's loss check.
## Cost affordability and first-step target legality are checked without paying, previewing, or resolving consequences.
func _action_available(unit: UnitInfo, effect_index: int) -> bool:
	if unit == null or effect_index < 0 or effect_index >= unit.effects.size(): return false
	return Match.rules_runner.command_available(unit.effects[effect_index], TargetRef.unit(unit.iun))

## Side-card enter/exit callbacks grant inspection hover to one portrait; deployment posture follows selection independently.
func _set_side_portrait_hover(unit_id: int) -> void:
	for list in card_lists.values():
		for card in list.get_children():
			if card.has_method("set_hovered"): card.set_hovered(int(card.get_meta("unit_id", -1)) == unit_id)

## Frame polling resumes locally requested online switches only after authoritative cancellation and replay settle.
## Turn changes discard requests; disconnected peers pause them. Replacement actions use the normal authenticated submit path.
func _resume_online_switch() -> void:
	if not NetworkSession.online: return
	if pending_unit_switch_id < 0 and pending_action_switch_index < 0: return
	if NetworkSession.local_player != Match.active_player or Match.winner != 0:
		pending_unit_switch_id = -1
		pending_action_switch_index = -1
		return
	if NetworkSession.pending_command or not NetworkSession.incoming.is_empty() or Match.rules_runner.busy() or not NetworkSession.both_connected(): return
	if pending_unit_switch_id >= 0:
		var next_unit := pending_unit_switch_id
		pending_unit_switch_id = -1
		pending_action_switch_index = -1
		_select_unit(next_unit)
	else:
		var next_action := pending_action_switch_index
		pending_action_switch_index = -1
		_begin_unit_action(selected_unit_id, next_action)
