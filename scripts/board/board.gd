class_name GuerraBoard
extends Node2D

signal hex_selected(hex_id: int)
signal unit_selected(unit_id: int)
signal hex_hovered(hex_id: int)
signal hex_unhovered(hex_id: int)
signal hex_unit_hovered(hex_id: int, unit_id: int)
signal effect_completed(success: bool, cost_paid: bool, action_free: bool)
signal selection_abandoned
signal trigger_cues_changed

const HEX_CELL_SCENE := preload("res://scenes/board/hex_cell.tscn")
const FIRE_VISUAL := preload("res://scripts/board/board_fire.gd")
const HEX_SIZE := Vector2(260.0, 260.0 * 2.0 / 3.0)
const HEX_SPACING := Vector2(230.0, 180.0)
const E1 := Vector2(sqrt(3) / 2, 0.5)
const E2 := Vector2(0, 1)
## Native PNG pixel corresponding to axial (0,0), centered on the current map's central clearing.
@export var terrain_anchor := Vector2(784.0, 464.0)
## Independent world/pixel ratios fit the terrain to the existing axial board's wider hex geometry.
@export var terrain_scale := Vector2(1.73, 2.24)
var origin := Vector2.ZERO
var terrain_fill: Sprite2D
var selection: PhraseExecution
var effect_execution: EffectExecution
var choices: Array[TargetRef] = []
var unit_choice_ids: Array[int] = []
var selected_unit_id := -1
var selectable_hexes: Array[int] = []
var choice_menu := PopupMenu.new()
var offboard_button := Button.new()
var confirm_button := Button.new()
var selection_label := Label.new()
var amount_controls := HBoxContainer.new()
var amount_input := SpinBox.new()
var amount_button := Button.new()
var _selection_click_accepted := false
## Cosmetic move records; rules and input never wait for these overlays.
var walking: Dictionary = {}
var paw_texture: Texture2D
var action_history: Dictionary = {}
var action_replays: Array[Node2D] = []
var presented_triggers: Dictionary = {}
var trigger_cues: Dictionary = {}
var phase_sign_feedback: WeakRef
var observed_life: Dictionary = {}
var life_feedback: Dictionary = {}
var heart_pulses: Dictionary = {}
var cannon_markers: Dictionary = {}
var sleeping_markers: Dictionary = {}
var displacement_presenters: Dictionary = {}
var external_stun_units: Dictionary = {}

@onready var hex_grid: Node2D = $HexGrid
@onready var terrain_background: Sprite2D = $BoardBackground/Terrain

## Builds cells and selection controls, then listens for authoritative match updates.
## Godot calls this after child nodes enter the scene; action events start cosmetic walking before repainting.
## BoardAmbience is initialized after terrain layout and runs independently of rules/input.
## Popup-window input has its own handler; graphical trigger gates retain runner work until two player acknowledgements.
## Registers finite-animation waits and a bounded X picker; choosing an amount never pays outside PhraseExecution's revalidation boundary.
func _ready() -> void:
	if Match.map.is_empty():
		var regions := RegionMap.new()
		regions._generate_hex_grid()
		regions.free()
	for info in Match.map: _add_cell(info)
	get_viewport().size_changed.connect(_layout_board)
	_layout_board()
	$Ambience.setup(self)
	for control in [choice_menu, offboard_button, confirm_button, selection_label, amount_controls]:
		$Interface.add_child(control)
	selection_label.position = Vector2(16, 16)
	selection_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	amount_controls.position = Vector2(16, 48)
	amount_input.min_value = 1
	amount_input.step = 1
	amount_input.rounded = true
	amount_input.custom_minimum_size.x = 110
	amount_controls.add_child(amount_input)
	amount_button.text = "Choose X"
	amount_controls.add_child(amount_button)
	amount_button.pressed.connect(_on_amount_chosen)
	offboard_button.position = Vector2(16, 48)
	offboard_button.text = "Choose player / off-board target"
	confirm_button.position = Vector2(16, 48)
	confirm_button.text = "Use effect"
	confirm_button.pressed.connect(func() -> void:
		_selection_click_accepted = true
		if effect_execution != null and effect_execution.status == EffectExecution.Status.CONFIRMING:
			effect_execution.confirm(true)
		elif selection != null: selection.confirm(true))
	offboard_button.pressed.connect(func() -> void:
		_selection_click_accepted = true
		_show_offboard_choices())
	choice_menu.index_pressed.connect(_on_choice_pressed)
	choice_menu.window_input.connect(_on_choice_window_input)
	Match.state_changed.connect(refresh_board)
	Match.action_event.connect(_on_action_presentation)
	Match.rules_runner.execution_started.connect(observe_execution)
	Match.rules_runner.trigger_acknowledgements_enabled = true
	Match.rules_runner.presentation_busy_query = _phase_presentation_busy
	Match.rules_runner.trigger_presentation_requested.connect(_on_trigger_presentation_requested)
	_on_selection_changed()
	restore_pending_projectiles()

## Board startup and NetworkSession snapshot/replay completion restore stationary Fire/Bow counters for current record identities.
## Existing markers are retained; snapshots replace records, so stale markers retire through their ordinary cosmetic lifecycle.
func restore_pending_projectiles() -> void:
	var shown := {}
	for child in get_children():
		if child.get_script() == FIRE_VISUAL and child.attack != null and not child.is_queued_for_deletion(): shown[child.attack.get_instance_id()] = true
	for attacks in [Match.pending_attacks, Match.pending_bow_attacks]:
		for attack in attacks:
			if attack.resolved or shown.has(attack.get_instance_id()): continue
			_add_fire_visual(attack.origin_hex, attack.target_hex, attack.amount, attack.owner, attack, true, attack.pierce, attack is BowAttack)

## _ready restores pending markers; declarations start travelling Fire/Bow/Cannon markers.
## Each icon-only marker owns its cosmetic timing and optional pending attack lifetime.
## Value/P arguments are retained for caller compatibility; those details are displayed only in hover counters.
## Bow selects arrow art and a higher left-side slot, sharing Fire's nonblocking timing.
## Returns the created marker for weak pending-record tracking, or null for unavailable endpoints.
func _add_fire_visual(origin_hex: int, target_hex: int, amount: int, owner: int,
		attack: RefCounted = null, stationary: bool = false, piercing: bool = false, is_bow: bool = false,
		kind: StringName = &"") -> Node2D:
	if Match.get_hex(origin_hex) == null or Match.get_hex(target_hex) == null: return null
	var visual := FIRE_VISUAL.new()
	visual.setup(self, origin_hex, target_hex, amount, owner, attack, stationary, piercing, is_bow, kind)
	add_child(visual)
	return visual

## Cannon target events arrive before the resolver appends its line records; this deferred callback binds those exact new indices.
## Each captured line hex gets one travelling Cannon; instant/already-resolved records get a short-lived cosmetic marker.
func _show_cannon_line(origin_hex: int, source_id: int, line: Array, pending_start: int, owner: int) -> void:
	for index in line.size():
		var attack: CannonAttack
		var pending_index := pending_start + index
		if pending_index < Match.pending_cannon_attacks.size():
			var candidate: CannonAttack = Match.pending_cannon_attacks[pending_index]
			if not candidate.explosion and candidate.source_id == source_id and candidate.target_hex == int(line[index]): attack = candidate
		if attack != null and cannon_markers.has(attack.get_instance_id()):
			var existing: Node2D = cannon_markers[attack.get_instance_id()].get_ref()
			if existing != null: existing.queue_free()
		var marker := _add_fire_visual(origin_hex, int(line[index]), 0, owner, attack, false, false, false, &"cannon")
		if marker != null and attack != null: cannon_markers[attack.get_instance_id()] = weakref(marker)

## _process() restores stationary Cannon markers for pending records not already presented, including snapshot loads.
## Weak marker tracking avoids duplicates; Bomb blast records retain the existing lit Bomb presentation.
func _sync_cannon_markers() -> void:
	for key in cannon_markers.keys():
		if cannon_markers[key].get_ref() == null: cannon_markers.erase(key)
	for attack: CannonAttack in Match.pending_cannon_attacks:
		if attack.explosion or attack.resolved or cannon_markers.has(attack.get_instance_id()): continue
		var marker := _add_fire_visual(attack.target_hex, attack.target_hex, attack.amount, attack.owner, attack, true, attack.pierce, false, &"cannon")
		if marker != null: cannon_markers[attack.get_instance_id()] = weakref(marker)

## _on_action_presentation routes all resolved attack families through the same destination-frame feedback.
## Uses captured HEX targets (Bash records its hex explicitly) so lethal hits still pulse after their unit has left the board.
## Remaining projectile travel delays the pulse until impact; this cosmetic cue never changes selection or rules.
## Bomb explosions pulse only when a captured target outcome reports positive damage, excluding empty, immune and fully protected hexes.
func _highlight_resolved_attack(event: EffectEvent) -> void:
	if event.stage != &"resolved" or event.action not in [&"fire", &"bow", &"gore", &"cannon", &"bomb_explosion", &"bash"]: return
	if event.data.get("cancelled", false): return
	if event.action == &"bomb_explosion":
		var damaged := false
		for outcome in event.data.get("outcome", {}).get("targets", []):
			if int(outcome.get("damage", 0)) > 0: damaged = true
		if not damaged: return
	var hex_id := int(event.data.get("hex", -1))
	if event.target != null and event.target.kind == TargetRef.Kind.HEX: hex_id = event.target.id
	if hex_id < 0 or hex_id >= hex_grid.get_child_count(): return
	var cell := hex_grid.get_child(hex_id) as HexCell
	cell.play_resolution_highlight(maxf(0.0, _attack_feedback_delay(hex_id) - 0.25))

## Starts character-only walking from the committed event's historical legal path, then repaints Match state.
## Match.action_event connects here; departure text is copied before refresh removes the old occupant.
## Bow/Fire declarations, Bomb throws and resolved Stun/Shield use the mapped action clip after repaint.
## Delayed attacks never repeat their declaration animation; movement keeps all six appearances on their captured path.
## A new action interrupts a still-travelling cosmetic overlay and keeps its last facing for the turn to south.
## A shared 0.2-second presentation lead-in holds the origin sprite/info before walk frames and path travel begin.
## Resolved Deploy starts the stationary standing/drop/fade/sit sequence after repaint; self-cost Stun never starts action art.
## After repaint, reapplies approach positions so a newly created Bash defender starts at its original center.
## Departing Bash actors consume the cell's captured side offset; survivor recentering belongs to the general hex-layout transition.
## Fire target events also launch a looping flame; queued markers persist through resolution and values stay in hover counters.
## Resolved Bomb Throw moves the destination's existing bomb marker with the same travel/fade timing as Fire.
## Bow target events start a direction-facing arrow with the same pending/instant lifetime as Fire.
## Captures committed action presentation for previous-turn click replay, independently of rule execution.
## Reads current/max-life deltas first so damage and maximum-life reductions share cosmetic slash feedback.
## Cannon declarations defer line-marker creation until their pending records have been appended by CombatResolver.
## Resolved Shield/Mshield plays its own finite fading steel/purple barrier clip on the exact receiving unit.
## Push/Pull use the actor's mapped action clip too, including Mouse Engineer's blueprint gesture.
## After repaint, resolved Push/Pull starts a cosmetic target slide with finite actor icons and landing wind.
## Stun received from a different unit enables immediate sleeping feedback; self-Stun waits for the seated pose.
## Actor icons and landing wind finish their finite clips independently of the turn boundary.
## A resolved Stun consequence plays orbiting stars on its recipient; self-Stun activity costs only drive later sleeping feedback.
## Bomb Light starts cosmetic radial ignition after repaint, waiting for any incoming Fire to reach the bomb marker.
## Resolved attack events pulse their captured destination rim, including misses and area-blast hexes; cancelled Bashes do not pulse.
## Resolved bomb damage starts the lit-bomb explosion before damage feedback; radial ignition copies retire at the same hex.
## Empty blast hexes use the shared replica fade; captured outcomes retain victim identity even after lethal damage removes the unit.
## Resource/counter grants and Return play the deployed source's mapped clip; Return also snapshots its exact departing participant before repaint.
func _on_action_presentation(event: EffectEvent) -> void:
	if NetworkSession.fast_replay: return
	if event.action == &"return_to_hand" and event.stage == &"resolved" and event.data.has("last_hex"):
		var returning := preload("res://scripts/board/board_return.gd").new()
		add_child(returning)
		returning.setup(self, event)
	if event.action == &"bomb_explosion" and event.stage == &"resolved" and event.target != null \
			and not event.data.get("outcome", {}).get("targets", []).is_empty():
		var hex_id := event.target.hex_id()
		if Match.get_hex(hex_id) != null:
			var explosion := preload("res://scripts/board/bomb_explosion.gd").new()
			explosion.setup(self, hex_id, maxf(0.0, _attack_feedback_delay(hex_id) - 0.25))
			add_child(explosion)
	_highlight_resolved_attack(event)
	if event.action == &"stun" and event.stage == &"resolved" and not event.data.get("self_cost", false) \
			and event.target != null and event.target.kind == TargetRef.Kind.UNIT and event.subject != null and not event.subject.same(event.target):
		var recipient := Match.get_unit(event.target.id)
		if recipient != null: external_stun_units[recipient.get_instance_id()] = weakref(recipient)
	_observe_life_changes()
	_remember_action(event)
	if event.action in [&"shield", &"mshield"] and event.stage == &"resolved":
		_show_target_feedback(event.target, String(event.action), 1.5)
	if event.action == &"stun" and event.stage == &"resolved" and not event.data.get("self_cost", false):
		_show_target_feedback(event.target, "stun", preload("res://scripts/board/board_trigger.gd").STUN_DURATION)
	if event.action == &"cannon" and event.stage == &"target" and event.subject != null:
		_show_cannon_line.call_deferred(event.subject.hex_id(), event.subject.id, event.data.get("line", []),
			Match.pending_cannon_attacks.size(), Match.owner_of(event.subject))
	if event.action == &"bow" and event.stage == &"target":
		var queued: BowAttack
		for attack: BowAttack in Match.pending_bow_attacks:
			if not attack.resolved and attack.source_id == event.subject.id and attack.target_hex == event.target.id:
				queued = attack
		_add_fire_visual(int(event.data.get("origin_hex", -1)), event.target.id,
			int(event.data.get("amount", 0)), Match.owner_of(event.subject), queued, false,
			bool(event.data.get("pierce", false)), true)
	if event.action == &"fire" and event.stage == &"target":
		var queued: FireAttack
		for attack: FireAttack in Match.pending_attacks:
			if not attack.resolved and attack.source_id == event.subject.id and attack.target_hex == event.target.id:
				queued = attack
		_add_fire_visual(int(event.data.get("origin_hex", -1)), event.target.id,
			int(event.data.get("amount", 0)), Match.owner_of(event.subject), queued, false,
			bool(event.data.get("pierce", false)))
	if event.action == &"move" and event.stage == &"resolved" and event.data.get("movement_kind") == &"move" \
			and event.subject != null and event.subject.kind == TargetRef.Kind.UNIT:
		var unit := Match.get_unit(event.subject.id)
		var path: Array = event.data.get("path", [])
		if BoardCharacter.supports(unit) and path.size() >= 2:
			_finish_walk(unit.iun)
			var origin_cell := hex_grid.get_child(int(path[0])) as HexCell
			var destination_cell := hex_grid.get_child(int(path.back())) as HexCell
			var ghost := origin_cell.get_node("CoordinateLabel").duplicate() as RichTextLabel
			ghost.text = origin_cell.last_unit_info.get(unit.iun, ghost.text)
			ghost.name = "DepartingInfo"
			ghost.modulate.a = 1.0
			origin_cell.add_child(ghost)
			var actor := BoardCharacter.new()
			actor.setup(unit.iun, true)
			actor.z_index = 6
			add_child(actor)
			walking[unit.iun] = {"actor": actor, "ghost": ghost, "path": path,
				"origin": origin_cell, "departure_offset": origin_cell.take_bash_departure_offset(unit.iun),
				"destination": destination_cell, "unit": unit, "elapsed": -BoardCharacter.WALK_START_DELAY}
			destination_cell.set_arrival(unit.iun, 0.0)
			_advance_walk(unit.iun, 0.0)
	refresh_board()
	if event.action == &"bomb_light" and event.stage == &"resolved" and event.target != null:
		_present_bomb_blast(event.target.hex_id())
	if event.action in [&"push", &"pull"] and event.stage == &"resolved":
		_present_displacement(event)
	if event.action == &"bomb_throw" and event.stage == &"resolved" and event.subject != null and event.subject.has_hex():
		var bomb_cell := hex_grid.get_child(event.target.id) as HexCell
		var origin_cell := hex_grid.get_child(event.subject.hex_id()) as HexCell
		bomb_cell.play_bomb_throw(origin_cell)
	for identifier in walking.keys(): _advance_walk(identifier, 0.0)
	if event.action == &"deploy" and event.stage == &"resolved" and event.subject != null and event.subject.kind == TargetRef.Kind.UNIT and event.subject.has_hex():
		var cell := hex_grid.get_child(event.subject.hex_id()) as HexCell
		cell.play_character_deploy(event.subject.id)
		return
	if event.data.get("self_cost", false): return
	if (event.action in [&"bow", &"fire"] and event.stage == &"target") or (event.action in [&"bomb_throw", &"stun", &"shield", &"mshield", &"push", &"pull", &"grant_deployments", &"return_to_hand", &"change_counter", &"upgrade_cannon", &"grant_action_values"] and event.stage == &"resolved"):
		if event.subject != null and event.subject.kind == TargetRef.Kind.UNIT and event.subject.has_hex():
			var travel_sector := -1
			if walking.has(event.subject.id):
				travel_sector = walking[event.subject.id].actor.current_sector
				_finish_walk(event.subject.id)
			var cell := hex_grid.get_child(event.subject.hex_id()) as HexCell
			cell.play_character_action(event.subject.id, travel_sector)

## Resolved Push/Pull presentation starts after the target's authoritative landing has been repainted.
## Stops any earlier target walk/slide, then hides its final figure behind a sliding copy; no movement rules are re-executed.
func _present_displacement(event: EffectEvent) -> void:
	if event.target == null or event.target.kind != TargetRef.Kind.UNIT: return
	var unit := Match.get_unit(event.target.id)
	if unit == null or unit.t_state != Enum.t_state.DEPLOYED: return
	_finish_walk(unit.iun)
	for key in displacement_presenters.keys():
		if not is_instance_valid(displacement_presenters[key]): displacement_presenters.erase(key)
	if displacement_presenters.has(unit.iun): displacement_presenters[unit.iun].finish()
	var source_hex := int(event.data.get("source_hex", event.subject.hex_id()))
	var origin_hex := int(event.data.get("origin_hex", -1))
	var destination_hex := int(event.data.get("destination_hex", -1))
	if Match.get_hex(source_hex) == null or Match.get_hex(origin_hex) == null or Match.get_hex(destination_hex) == null: return
	var presenter := preload("res://scripts/board/board_displacement.gd").new()
	presenter.setup(self, unit, source_hex, origin_hex, destination_hex, event.action == &"pull", event.subject.id)
	add_child(presenter)
	presenter._process(0.0)
	displacement_presenters[unit.iun] = presenter

## Advances nonblocking character overlays; Godot calls this independently from RulesRunner.
## Identity/position checks discard stale animations after death, another move, or a match reset.
## Also restores pending Cannon markers once per record, independently of presentation history.
## Prunes finished displacement references before sleeping/trigger checks so an old Push/Pull cannot block a later walk's seated feedback.
## Synchronizes one sleeping loop per deployed unit with positive Stun, including self-costs and restored snapshots.
## Advances one-second heart gain pulses before checking finite phase continuations; mixed damage/gain waits for the Slash reveal beat.
func _process(delta: float) -> void:
	_advance_heart_pulses(delta)
	for key in displacement_presenters.keys():
		if not is_instance_valid(displacement_presenters[key]): displacement_presenters.erase(key)
	_expire_trigger_cues()
	_sync_trigger_presentation()
	_resume_phase_presentation()
	_sync_cannon_markers()
	_sync_sleeping_markers()
	for identifier in walking.keys():
		var unit := Match.get_unit(identifier)
		var path: Array = walking[identifier].path
		if unit == null or unit != walking[identifier].unit or unit.t_state != Enum.t_state.DEPLOYED or unit.ihx != int(path.back()):
			_finish_walk(identifier)
		else: _advance_walk(identifier, delta)

## Slides the six-frame walking sprite along captured adjacent cells at 0.8 seconds per step, selecting the available travel-facing cycle.
## _process calls this; departure fades over the first half-step, arrival over the final half-step; arrival hands its last facing to the stationary turn/sit.
## The walking anchor includes the 26-pixel upward UnitFigures offset so arrivals align with stationary characters.
## Negative elapsed time is the 0.2s lead-in; clamp path progress to keep the actor and origin text still until it finishes.
## During the final step the attacker approaches its Bash side and the defender smoothly shifts to the opposite side.
## A departing Bash actor starts on its captured side; the former partner's independent hex transition handles recentering.
## Actual cosmetic travel emits alternating left/right paw prints; lead-in/repaint calls emit none while stationary.
func _advance_walk(identifier: int, delta: float) -> void:
	var record: Dictionary = walking[identifier]
	record.elapsed += delta
	var path: Array = record.path
	var progress := clampf(record.elapsed / 0.8, 0.0, float(path.size() - 1))
	var segment := mini(int(progress), path.size() - 2)
	var start := Match.get_hex(int(path[segment]))
	var finish := Match.get_hex(int(path[segment + 1]))
	if start == null or finish == null:
		_finish_walk(identifier)
		return
	record.actor.set_walk_direction(axial_to_screen(finish.coordinate) - axial_to_screen(start.coordinate))
	record.actor.position = axial_to_screen(start.coordinate).lerp(axial_to_screen(finish.coordinate), progress - segment) + Vector2(0, -18)
	var departure := 1.0 - smoothstep(0.0, 1.0, clampf(progress, 0.0, 1.0))
	record.actor.position += Vector2(record.departure_offset) * departure
	var approach := clampf(progress - float(path.size() - 2), 0.0, 1.0)
	record.actor.position += record.destination.bash_arrival_offset(identifier) * smoothstep(0.0, 1.0, approach)
	record.destination.set_bash_approach(identifier, approach)
	_advance_paw_trail(record)
	record.ghost.modulate.a = 1.0 - clampf(progress / 0.5, 0.0, 1.0)
	var arrival := clampf((progress - float(path.size() - 1) + 0.5) / 0.5, 0.0, 1.0)
	record.destination.set_arrival(identifier, arrival)
	if progress >= float(path.size() - 1): _finish_walk(identifier, true)

## _advance_walk() samples the actor's actual grounded travel, including Bash offsets, every 28 world pixels.
## Per-walk spacing/side state avoids duplicate prints on repaint and keeps two staggered rows through turns.
## Only distance travelled creates prints; interrupting a walk leaves existing prints to finish their own fades.
func _advance_paw_trail(record: Dictionary) -> void:
	var current: Vector2 = record.actor.position + Vector2(0, 18)
	if not record.has("paw_position"):
		record.paw_position = current
		record.paw_remaining = 28.0
		record.paw_side = -1.0
		return
	var previous: Vector2 = record.paw_position
	var distance := previous.distance_to(current)
	if distance <= 0.001: return
	var direction := (current - previous) / distance
	var remaining: float = record.paw_remaining
	while distance >= remaining:
		previous += direction * remaining
		distance -= remaining
		_spawn_paw_print(previous + direction.orthogonal() * float(record.paw_side) * 10.0, direction)
		record.paw_side = -float(record.paw_side)
		remaining = 28.0
	record.paw_remaining = remaining - distance
	record.paw_position = current

## _advance_paw_trail() places the user's upward-facing PixelLab paw beneath units, rotated into travel direction.
## Prints hold for one second, then fade over 0.4s and free themselves; no rules events or timers block movement.
## Lazily caches imported art, with a raw-PNG fallback for newly downloaded working-project assets.
func _spawn_paw_print(point: Vector2, direction: Vector2) -> void:
	if paw_texture == null:
		var path := "res://assets/environment/paw-print.png"
		if ResourceLoader.exists(path, "Texture2D"): paw_texture = load(path) as Texture2D
		if paw_texture == null:
			var image := Image.load_from_file(path)
			if image != null and not image.is_empty(): paw_texture = ImageTexture.create_from_image(image)
		if paw_texture == null:
			push_error("Cannot load walking paw print: %s" % path)
			return
	var paw := Sprite2D.new()
	paw.texture = paw_texture
	paw.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	paw.position = point
	paw.rotation = direction.angle() + PI * 0.5
	paw.scale = Vector2.ONE * 1.3
	paw.z_index = -1
	paw.modulate.a = 0.7
	add_child(paw)
	var fade := paw.create_tween()
	fade.tween_interval(1.0)
	fade.tween_property(paw, "modulate:a", 0.0, 0.4).set_trans(Tween.TRANS_SINE)
	fade.tween_callback(paw.queue_free)

## Releases the travelling overlay and restores destination info; a genuine arrival hands its final facing to the stationary turn/sit.
## Movement replacement/invalidation cancel without sitting at a stale destination; neither path changes Match or rule events.
## Settles any remaining Bash defender shift before removing the moving actor.
## Survivor recentering is independent of this overlay's completion or interruption.
func _finish_walk(identifier: int, arrived: bool = false) -> void:
	if not walking.has(identifier): return
	var record: Dictionary = walking[identifier]
	record.destination.set_bash_approach(identifier, 1.0)
	if arrived: record.destination.finish_character_walk(identifier, record.actor.current_sector)
	record.actor.queue_free()
	record.ghost.queue_free()
	record.destination.set_arrival(-1, 1.0)
	walking.erase(identifier)

## Creates one clickable visual cell for a Match hex.
## _ready() connects tile input/hover, explicit Bash participant boxes and the HUD inspection signal.
func _add_cell(info: HexInfo) -> void:
	var cell: HexCell = HEX_CELL_SCENE.instantiate()
	cell.setup(info)
	cell.set_board_position(axial_to_screen(info.coordinate))
	cell.hovered.connect(_on_cell_hovered)
	cell.unhovered.connect(_on_cell_unhovered)
	cell.bash_unit_hovered.connect(_on_cell_bash_unit_hovered)
	cell.pressed.connect(_on_cell_pressed)
	cell.bash_unit_pressed.connect(_on_cell_pressed)
	hex_grid.add_child(cell)

## Converts an axial map coordinate to its centered board position.
## _add_cell() and _layout_board() use this after the map origin is recalculated.
func axial_to_screen(coordinate: Vector2i) -> Vector2:
	return origin + _world_position(coordinate)

## Re-centers the hex map and fits its full bounds inside the space left by the card trays.
## Viewport.size_changed calls this; terrain shares the same world origin/camera and calibrated PNG anchor,
## keeping its clearing and terrain aligned with hexes rather than stretching independently with the HUD.
## The ambience layer reuses this mapping to keep authored grass attached to its terrain positions.
## After fitting the camera, _layout_terrain_fill() extends light grass across exposed horizontal margins.
func _layout_board() -> void:
	if Match.map.is_empty(): return
	var minimum := Vector2(1.0e20, 1.0e20)
	var maximum := Vector2(-1.0e20, -1.0e20)
	for tile in Match.map:
		var point := _world_position(tile.coordinate)
		minimum = minimum.min(point - HEX_SIZE * 0.5)
		maximum = maximum.max(point + HEX_SIZE * 0.5)
	var bounds_size := maximum - minimum
	origin = -(minimum + maximum) * 0.5
	terrain_background.scale = terrain_scale
	terrain_background.position = origin - terrain_anchor * terrain_scale
	$Ambience.realign()
	for cell: HexCell in hex_grid.get_children():
		cell.set_board_position(axial_to_screen(cell.hex_info.coordinate))
	var view_size := get_viewport_rect().size
	var compact := view_size.x < 900.0
	var available_width: float
	var available_height: float
	if compact:
		available_width = view_size.x * 0.94
		available_height = view_size.y * 0.64
	else:
		var tray_width := clampf(view_size.x * 0.11, 108.0, 140.0)
		var margin := clampf(view_size.x * 0.014, 8.0, 22.0)
		available_width = view_size.x - 2.0 * (tray_width + margin)
		available_height = view_size.y - 124.0
	var fit_zoom := minf(available_width / bounds_size.x, available_height / bounds_size.y) * 0.94
	var zoom := clampf(fit_zoom, 0.06, 3.0)
	$Camera2D.zoom = Vector2.ONE * zoom
	$Camera2D.position = Vector2(0.0, view_size.y * (0.18 if compact else 0.0) / zoom)
	_layout_terrain_fill(view_size, zoom)

## _layout_board() tiles light grass beneath the map to cover visible side margins and transparent edge gaps.
## Preserves terrain grid alignment and vertical bounds; decoration creates no playable hexes or input surfaces.
func _layout_terrain_fill(view_size: Vector2, zoom: float) -> void:
	if terrain_fill == null:
		terrain_fill = Sprite2D.new()
		terrain_fill.name = "TerrainEdgeFill"
		var tile := terrain_background.texture.get_image().get_region(Rect2i(32, 32, 32, 32))
		terrain_fill.texture = ImageTexture.create_from_image(tile)
		terrain_fill.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		terrain_fill.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		terrain_fill.centered = false
		terrain_fill.region_enabled = true
		$BoardBackground.add_child(terrain_fill)
		$BoardBackground.move_child(terrain_fill, 0)
	var native_width := float(terrain_background.texture.get_width())
	var camera_left: float = $Camera2D.position.x - view_size.x / (2.0 * zoom)
	var camera_right: float = $Camera2D.position.x + view_size.x / (2.0 * zoom)
	var left := floorf(minf(0.0, (camera_left - terrain_background.position.x) / terrain_scale.x) / 32.0) * 32.0
	var right := ceilf(maxf(native_width, (camera_right - terrain_background.position.x) / terrain_scale.x) / 32.0) * 32.0
	terrain_fill.position = terrain_background.position + Vector2(left * terrain_scale.x, 0.0)
	terrain_fill.scale = terrain_scale
	terrain_fill.region_rect = Rect2(0.0, 0.0, right - left, float(terrain_background.texture.get_height()))

## Converts an axial coordinate to board world units before origin/camera layout.
## Tuned axial spacing closes the vertical stretch and opens the horizontal layout; _layout_board() uses it for bounds.
func _world_position(coordinate: Vector2i) -> Vector2:
	return HEX_SPACING * (coordinate.x * E1 + coordinate.y * E2)

## Reports pointer entry by stable tile identity to the local hover-inspection panel.
## HexCell.hovered connects here and the controller receives hex_hovered.
func _on_cell_hovered(coordinate: Vector2i) -> void:
	var hex_id := _hex_id_at(coordinate)
	if hex_id >= 0: hex_hovered.emit(hex_id)

## Reports when the pointer leaves a board tile so the controller can dismiss its hover panel.
## HexCell.unhovered connects here; the ID lets the UI ignore stale exits between adjacent cells.
func _on_cell_unhovered(coordinate: Vector2i) -> void:
	var hex_id := _hex_id_at(coordinate)
	if hex_id >= 0: hex_unhovered.emit(hex_id)

## Relays the exact participant under the pointer without refreshing the board or interrupting Bash transitions.
## HexCell.bash_unit_hovered connects here; LocalMatchController uses hex_unit_hovered for its hover card.
func _on_cell_bash_unit_hovered(coordinate: Vector2i, unit_id: int) -> void:
	var hex_id := _hex_id_at(coordinate)
	if hex_id >= 0: hex_unit_hovered.emit(hex_id, unit_id)

## Routes a tile click to the active selector or local deployment chooser.
## HexCell.pressed connects here; idle clicks select only active friendly units.
## Existing target/subject choices stay independent, so inactive units remain selectable as legal effect targets.
## An invalid destination on another active friendly unit can switch an unpaid preview; legal effect targets retain priority.
## Bash boxes pass an explicit identity through replay, idle selection and UNIT target choice; AMOUNT locks that identity until its picker completes.
func _on_cell_pressed(coordinate: Vector2i, preferred_unit: int = -1) -> void:
	if selection != null and selection.status == PhraseExecution.Status.AMOUNT: return
	var clicked := _hex_id_at(coordinate)
	if clicked < 0: return
	var clicked_cell := hex_grid.get_child(clicked) as HexCell
	var side_unit := preferred_unit if preferred_unit >= 0 else clicked_cell.bash_unit_at_position(clicked_cell.get_local_mouse_position())
	if side_unit >= 0 and not Match.occupants(clicked).any(func(ref: TargetRef) -> bool: return ref.id == side_unit): return
	var legal_target := selection != null and selection.status in [PhraseExecution.Status.SUBJECT, PhraseExecution.Status.TARGET] \
		and selection.candidates.any(func(ref: TargetRef) -> bool: return ref.has_hex() and ref.hex_id() == clicked)
	if not legal_target and selectable_hexes.is_empty() and _offer_action_replay(clicked, side_unit):
		_selection_click_accepted = true
		return
	_clear_action_replays()
	if selection != null and selection.status in [PhraseExecution.Status.SUBJECT, PhraseExecution.Status.TARGET]:
		var options: Array[TargetRef] = selection.candidates.filter(func(ref: TargetRef) -> bool:
			return ref.has_hex() and Match.get_hex(ref.hex_id()).coordinate == coordinate)
		if options.is_empty():
			if effect_execution != null and effect_execution.defer_cost_until_target and not effect_execution.cost_paid \
					and effect_execution.can_cancel() and _offer_unit_selection(clicked, selected_unit_id, side_unit): return
			selection.cancel()
			return
		_selection_click_accepted = true
		if side_unit >= 0 and options.any(func(ref: TargetRef) -> bool: return ref.kind == TargetRef.Kind.UNIT):
			var chosen := TargetRef.unit(side_unit)
			if TargetResolver.contains(options, chosen): selection.choose(chosen)
			return
		if options.size() == 1: selection.choose(options[0])
		else: _show_choices(options)
		return
	if not selectable_hexes.is_empty():
		if clicked in selectable_hexes:
			_selection_click_accepted = true
			hex_selected.emit(clicked)
		else:
			show_hex_choices([])
			selection_abandoned.emit()
		return
	if selection == null or selection.status not in [PhraseExecution.Status.SUBJECT, PhraseExecution.Status.TARGET]:
		var occupants := Match.occupants(clicked)
		if _offer_unit_selection(clicked, -1, side_unit): return
		if not occupants.is_empty(): return
		hex_selected.emit(clicked)
		return

## _on_action_presentation() records events matching the active manual consequence verb, without an attack-name allowlist.
## Entries bind the actual unit instance and turn so reset/replacement IDs cannot replay an unrelated troop's history.
## Target/resolved duplicates share a phrase/recipient key; additional ALL recipients retain separate records.
## Deploy captures its landing without a phrase; Return retains last_hex after the recipient has already moved to hand.
func _remember_action(event: EffectEvent) -> void:
	if event.subject == null or event.subject.kind != TargetRef.Kind.UNIT or event.data.get("self_cost", false): return
	var unit := Match.get_unit(event.subject.id)
	if unit == null or unit.player != Match.active_player or Match.rules_runner.is_triggered(): return
	if event.action == &"deploy" and event.stage == &"resolved" and unit.t_state == Enum.t_state.DEPLOYED:
		action_history[unit.iun] = {"unit": unit, "turn": Match.turn_number, "keys": {}, "actions": [{
			"action": &"deploy", "origin": unit.ihx, "target": unit.ihx, "path": [],
			"owner": unit.player, "unit": unit, "turn": Match.turn_number}]}
		return
	var execution := Match.rules_runner.active
	if execution == null or execution.status != EffectExecution.Status.CONSEQUENCE or execution.current == null: return
	var phrase := execution.current.phrase
	if phrase == null or phrase.verb.name != event.action or event.stage not in [&"target", &"resolved"]: return
	var path: Array = event.data.get("path", [])
	var walked: bool = event.action == &"move" and event.data.get("movement_kind") == &"move" and path.size() >= 2
	var origin_hex := int(path[0]) if walked else int(event.data.get("source_hex", event.data.get("origin_hex", unit.ihx)))
	var target_hex := event.target.hex_id() if event.target != null and event.target.has_hex() else int(event.data.get("last_hex", unit.ihx))
	if not action_history.has(unit.iun) or action_history[unit.iun].turn != Match.turn_number:
		action_history[unit.iun] = {"unit": unit, "turn": Match.turn_number, "actions": [], "keys": {}}
	var key := "%d:%s:%d:%d" % [execution.current.get_instance_id(), event.action,
		event.target.kind if event.target != null else -1, event.target.id if event.target != null else -1]
	if action_history[unit.iun].keys.has(key): return
	action_history[unit.iun].keys[key] = true
	action_history[unit.iun].actions.append({"action": event.action, "origin": origin_hex,
		"target": target_hex, "path": path.duplicate() if walked else [], "owner": unit.player,
		"unit": unit, "turn": Match.turn_number, "aim_hex": int(event.data.get("origin_hex", target_hex)),
		"target_unit_id": event.target.id if event.target.kind == TargetRef.Kind.UNIT else -1,
		"aim_bomb": event.action == &"fire" and Match.bomb_at(target_hex) != null})
	for identifier in action_history.keys():
		if action_history[identifier].turn < Match.turn_number - 1: action_history.erase(identifier)

## Idle/unmatched board clicks offer replay only for occupants that acted on the immediately previous turn, including inactive enemies.
## Legal targets/deployment take priority; a Bash box restricts replay to that exact participant, while other ambiguous hexes retain their menu.
func _offer_action_replay(hex_id: int, only_unit: int = -1) -> bool:
	var identifiers: Array[int] = []
	for ref: TargetRef in Match.occupants(hex_id):
		if only_unit >= 0 and ref.id != only_unit: continue
		if not action_history.has(ref.id): continue
		var saved: Dictionary = action_history[ref.id]
		if saved.turn == Match.turn_number - 1 and saved.unit == Match.get_unit(ref.id): identifiers.append(ref.id)
	if identifiers.is_empty(): return false
	if identifiers.size() == 1: _replay_unit_action(identifiers[0])
	else:
		var menu := PopupMenu.new()
		add_child(menu)
		for identifier in identifiers: menu.add_item("Replay " + Match.get_unit(identifier).name, identifier)
		menu.id_pressed.connect(_replay_unit_action)
		menu.popup_hide.connect(menu.queue_free)
		menu.position = Vector2i(get_viewport().get_mouse_position())
		menu.popup()
	return true

## Board click/menu calls this; replaces earlier replay markers and starts each saved action without submitting a command.
## No payment, movement, turn progress or Match event occurs; paw prints already created finish their independent fades.
## Generic action_replay nodes play once per click, discovering art by verb name without attack-specific switches.
func _replay_unit_action(identifier: int) -> void:
	if not action_history.has(identifier): return
	_clear_action_replays()
	for saved: Dictionary in action_history[identifier].actions:
		var replay := preload("res://scripts/board/action_replay.gd").new()
		replay.setup(self, saved)
		add_child(replay)
		action_replays.append(replay)

## Replay replacement and ordinary board clicks stop current overlays; independent paw fades finish naturally.
func _clear_action_replays() -> void:
	for replay in action_replays:
		if is_instance_valid(replay): replay.queue_free()
	action_replays.clear()

## Bow marker clicks and hover links replay the exact pending record without resolving or paying it.
func replay_bow_counter(attack: BowAttack) -> void:
	if attack == null or attack.resolved or not Match.pending_bow_attacks.has(attack): return
	_replay_marker_action(&"bow", attack.origin_hex, attack.target_hex, attack.owner)

## Idle Fire marker clicks replay the pending attack's captured endpoints even if its source moved or was defeated.
func replay_fire_counter(attack: FireAttack) -> void:
	if attack == null or attack.resolved or not Match.pending_attacks.has(attack): return
	_replay_marker_action(&"fire", attack.origin_hex, attack.target_hex, attack.owner)

## Idle bomb marker clicks use the saved throw origin when present; restored bombs fall back to their source's current hex.
## BombInfo has no historical origin, so a missing/off-board source falls back to a stationary cosmetic replay at the bomb.
func replay_bomb_counter(bomb: BombInfo) -> void:
	if bomb == null or Match.bomb_at(bomb.hex_id) != bomb: return
	var source := Match.get_unit(bomb.source_id)
	var origin_hex := source.ihx if source != null and source.t_state == Enum.t_state.DEPLOYED else bomb.hex_id
	if action_history.has(bomb.source_id):
		for saved: Dictionary in action_history[bomb.source_id].actions:
			if saved.action == &"bomb_throw" and saved.target == bomb.hex_id: origin_hex = saved.origin
	_replay_marker_action(&"bomb_throw", origin_hex, bomb.hex_id, bomb.owner)

## Counter entry points create a source-independent finite replay from captured coordinates; next turn cancels it normally.
func _replay_marker_action(action: StringName, origin_hex: int, target_hex: int, owner: int) -> void:
	_clear_action_replays()
	var replay := preload("res://scripts/board/action_replay.gd").new()
	replay.setup(self, {"action": action, "origin": origin_hex, "target": target_hex,
		"owner": owner, "unit": null, "turn": Match.turn_number - 1, "path": [], "marker": true})
	add_child(replay)
	action_replays.append(replay)

## _on_cell_pressed() shares active-friendly unit picking between idle selection and an unpaid-preview switch.
## Excludes the current source when switching and honors an explicit clicked Bash identity before collecting eligible units.
func _offer_unit_selection(hex_id: int, excluded_unit: int = -1, only_unit: int = -1) -> bool:
	var units: Array[int] = []
	for occupant in Match.occupants(hex_id):
		if only_unit >= 0 and occupant.id != only_unit: continue
		if occupant.kind != TargetRef.Kind.UNIT or occupant.id == excluded_unit: continue
		var unit := Match.get_unit(occupant.id)
		if unit != null and unit.active and unit.player == Match.active_player: units.append(occupant.id)
	if units.is_empty(): return false
	_selection_click_accepted = true
	if units.size() == 1: unit_selected.emit(units[0])
	else: _show_unit_choices(units)
	return true

## Removes action/deployment highlights after an unrelated click without swallowing valid UI choices.
## _unhandled_input() schedules this only for clicks not handled by HUD controls;
## HexCell's later physics picking can still claim a legal board target before this check.
## An idle selected unit also clears here, allowing parchment-only selection to dismiss on click-away.
func _clear_focus_after_unmatched_click(expected: PhraseExecution, waiting_for_tile: bool) -> void:
	if _selection_click_accepted: return
	if expected != null and selection == expected and selection.status in [PhraseExecution.Status.SUBJECT, PhraseExecution.Status.TARGET, PhraseExecution.Status.AMOUNT]:
		selection.cancel()
	elif waiting_for_tile and not selectable_hexes.is_empty():
		show_hex_choices([])
		selection_abandoned.emit()
	elif expected == null and selected_unit_id >= 0:
		selection_abandoned.emit()

## Execute a standalone phrase (does not pay its enclosing effect's cost).
## Used by prototype controls and test scenes to start direct phrase selection.
func select_phrase(phrase: Effect.Phrase, source: TargetRef) -> void:
	if Match.rules_runner.busy(): return
	_cancel_current()
	effect_execution = EffectExecution.new(null, source)
	var next := PhraseExecution.new()
	_attach_selection(next)
	next.begin(phrase, effect_execution)

## Run an effect's event check, cost, and consequence.
## Creates the activation and connects phrase_started to this board's chooser.
func select_effect(effect: Effect, source: TargetRef, trigger: EffectEvent = null) -> void:
	if Match.rules_runner.busy(): return
	_cancel_current()
	effect_execution = EffectExecution.new(effect, source, trigger)
	effect_execution.phrase_started.connect(_attach_selection)
	effect_execution.finished.connect(_on_effect_finished)
	effect_execution.start()

## Observes a runner-owned activation without replacing or cancelling another execution.
## RulesRunner.execution_started also restores parents after cost-trigger pauses.
## Captured trigger executions reuse their acknowledged top-left cue; resumed executions never replay it.
func observe_execution(execution: EffectExecution) -> void:
	_present_trigger(execution)
	if selection != null and selection.changed.is_connected(_on_selection_changed):
		selection.changed.disconnect(_on_selection_changed)
	selection = null
	effect_execution = execution
	if not execution.phrase_started.is_connected(_attach_selection): execution.phrase_started.connect(_attach_selection)
	if not execution.confirmation_requested.is_connected(_on_selection_changed): execution.confirmation_requested.connect(_on_selection_changed)
	var completion := _on_managed_finished.bind(execution)
	if not execution.finished.is_connected(completion): execution.finished.connect(completion)
	_on_selection_changed()

## Resolved action presentation calls this for a recipient-bound, finite cosmetic clip, including Shield/Mshield and Stun.
## Unit identity chooses the recipient's actual figure/Bash side; no effect or cost is executed by the burst.
func _show_target_feedback(target: TargetRef, clip: String, duration: float) -> void:
	if target == null or target.kind != TargetRef.Kind.UNIT or not target.has_hex(): return
	var unit := Match.get_unit(target.id)
	if unit == null: return
	var marker := preload("res://scripts/board/board_trigger.gd").new()
	marker.setup(self, unit, target.hex_id(), clip, duration)
	add_child(marker)
	marker._process(0.0)

## observe_execution() detects captured triggers at first activation, not individual consequence events or resumed phases.
## Weak execution identities prevent replay on cost-trigger resumes without retaining completed activations.
## Death triggers fall back to their own captured death tile after their source has left the board.
## Queue-head acknowledgement gates create the cue before activation, after causal attack/damage/death animation; resumed executions reuse it.
## Stores exact fired definitions per source through the next turn for matching board/hover highlights and icon-only dismissal.
## Reconnect fast replay suppresses historical cues; NetworkSession presents only the outstanding acknowledgement gate afterward.
func _present_trigger(execution: EffectExecution) -> void:
	if NetworkSession.fast_replay: return
	if not execution.captured_trigger or execution.source == null or execution.source.kind != TargetRef.Kind.UNIT: return
	for key in presented_triggers.keys():
		if presented_triggers[key].get_ref() == null: presented_triggers.erase(key)
	var key := execution.get_instance_id()
	if presented_triggers.has(key): return
	presented_triggers[key] = weakref(execution)
	var unit := Match.get_unit(execution.source.id)
	if unit == null: return
	var hex_id := unit.ihx
	if unit.t_state != Enum.t_state.DEPLOYED: hex_id = int(observed_life.get(unit.iun, {}).get("hex", hex_id))
	var event := execution.triggering_event
	if unit.t_state != Enum.t_state.DEPLOYED and event != null and event.action == &"die" \
			and event.subject != null and event.subject.same(execution.source) and event.target != null:
		hex_id = event.target.hex_id()
	if Match.get_hex(hex_id) == null: return
	var cue: Dictionary = trigger_cues.get(unit.iun, {})
	if cue.is_empty() or cue.unit != unit:
		cue = {"unit": unit, "until": Match.turn_number + 1, "effects": [], "marker": null}
		trigger_cues[unit.iun] = cue
	cue.until = Match.turn_number + 1
	cue.hex = hex_id
	if not cue.effects.has(execution.definition): cue.effects.append(execution.definition)
	if is_instance_valid(cue.marker): cue.marker.expires_turn = cue.until
	refresh_board()
	trigger_cues_changed.emit()
	_queue_trigger_feedback.call_deferred(unit, hex_id)

## Trigger presentation waits for causal visuals, so Slash and eventual Skull take priority over acknowledgement input.
## Waits for the finite action/damage/death/sign sequence, then starts one cue; dismissal while waiting prevents stale creation.
## Only cosmetics are queued; trigger rules, payment and followups remain synchronous/runner-owned.
func _queue_trigger_feedback(unit: UnitInfo, hex_id: int) -> void:
	if _phase_presentation_busy(): return
	if not is_inside_tree() or Match.get_unit(unit.iun) != unit or Match.get_hex(hex_id) == null: return
	if not trigger_cues.has(unit.iun) or trigger_cues[unit.iun].unit != unit: return
	if is_instance_valid(trigger_cues[unit.iun].marker): return
	var slash: Variant = life_feedback.get(unit.get_instance_id())
	if is_instance_valid(slash) and slash.is_inside_tree():
		slash.tree_exited.connect(func() -> void: _queue_trigger_feedback.call_deferred(unit, hex_id), CONNECT_ONE_SHOT)
		return
	var marker := preload("res://scripts/board/board_trigger.gd").new()
	marker.setup(self, unit, hex_id)
	marker.expires_turn = trigger_cues[unit.iun].until
	trigger_cues[unit.iun].marker = marker
	add_child(marker)
	marker._process(0.0)
	var waiting := Match.rules_runner.presentation_waiting
	if waiting != null and waiting.source != null and waiting.source.id == unit.iun:
		Match.rules_runner.presentation_ready = true
		trigger_cues_changed.emit()

## HexCell and hover text query exact fired definitions without modifying rule definitions or executions.
func highlighted_triggers(unit: UnitInfo) -> Array:
	if unit == null or not trigger_cues.has(unit.iun): return []
	var cue: Dictionary = trigger_cues[unit.iun]
	return cue.effects if cue.unit == unit and Match.turn_number <= int(cue.until) else []

## Board frame updates expire cues after the following turn and discard replaced source identities.
func _expire_trigger_cues() -> void:
	for identifier in trigger_cues.keys():
		var cue: Dictionary = trigger_cues[identifier]
		if Match.get_unit(identifier) != cue.unit or Match.turn_number > int(cue.until): _dismiss_trigger_cue(identifier)

## Icon clicks and expiry clear only presentation state; blink fades out and info refreshes through the existing hover transition.
func _dismiss_trigger_cue(identifier: int) -> void:
	if not trigger_cues.has(identifier): return
	var marker: Variant = trigger_cues[identifier].marker
	if is_instance_valid(marker): marker.dismissed = true
	trigger_cues.erase(identifier)
	refresh_board()
	trigger_cues_changed.emit()

## Godot routes clicks before board picking; the blink's stable animation bounds handle viewport/camera transforms, never unit bounds.
## Consuming the click preserves selections/targets while fading the cue and clearing its yellow text.
func _input(event: InputEvent) -> void:
	if Match.rules_runner.presentation_waiting != null:
		if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE:
			_acknowledge_next_local_player()
		elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			var sign: Variant = phase_sign_feedback.get_ref() if phase_sign_feedback != null else null
			if is_instance_valid(sign) and sign.contains_trigger_blink(event.position):
				_acknowledge_next_local_player()
				get_viewport().set_input_as_handled()
				return
			for cue in trigger_cues.values():
				var blink: Variant = cue.marker
				if is_instance_valid(blink) and not blink.dismissed and blink.contains_pointer(event.position):
					_acknowledge_next_local_player()
					break
		if event is InputEventMouseButton or event is InputEventKey: get_viewport().set_input_as_handled()
		return
	if not event is InputEventMouseButton or event.button_index != MOUSE_BUTTON_LEFT or not event.pressed: return
	for identifier in trigger_cues.keys():
		var marker: Variant = trigger_cues[identifier].marker
		if not is_instance_valid(marker) or marker.dismissed or marker.modulate.a <= 0.05: continue
		if marker.contains_pointer(event.position):
			_dismiss_trigger_cue(identifier)
			get_viewport().set_input_as_handled()
			return

## Clears only the finished managed UI; a nested execution may already have taken over.
## observe_execution connects this notification; token spending belongs solely to RulesRunner.
func _on_managed_finished(_success: bool, execution: EffectExecution) -> void:
	if effect_execution != execution: return
	selection = null
	effect_execution = null
	_on_selection_changed()

## Highlights legal destinations for the local deployment chooser.
## LocalMatchController supplies IDs from Match.can_deploy and handles hex_selected.
func show_hex_choices(hex_ids: Array[int]) -> void:
	selectable_hexes = hex_ids.duplicate()
	_on_selection_changed()

## Highlights one deployed unit's figure without changing the hex ownership frame.
## LocalMatchController calls this when the player selects a board figure or card.
func select_unit(unit_id: int) -> void:
	selected_unit_id = unit_id
	_on_selection_changed()

## Repaints cells after authoritative Match events and recalculates region ownership.
## Called on Match.state_changed and Match.action_event.
## Life observations update once per value change; repeated refreshes never replay damage feedback.
func refresh_board() -> void:
	_observe_life_changes()
	Match.refresh_control()
	_on_selection_changed()

## _process() discovers deployed units with positive Stun and creates one persistent sleeping marker per unit instance.
## Existing markers own their fade-out/recovery and frame progress, so ordinary repaints or further Stun never restart the loop.
## Weak references release finished markers and handle new matches without retaining old unit presentation.
## External Stun bypasses the pose gate; self-Stun waits for the complete sit-down before the first Z appears.
func _sync_sleeping_markers() -> void:
	for key in external_stun_units.keys():
		var recipient: UnitInfo = external_stun_units[key].get_ref()
		if recipient == null or Match.get_unit(recipient.iun) != recipient:
			external_stun_units.erase(key)
			continue
		var counter := Match.get_property(TargetRef.property(TargetRef.unit(recipient.iun), UnitInfo.STUN_COUNTER))
		if counter == null or counter.value <= 0: external_stun_units.erase(key)
	for key in sleeping_markers.keys():
		var existing: Node2D = sleeping_markers[key].get_ref()
		if existing == null or existing.is_queued_for_deletion(): sleeping_markers.erase(key)
	for unit: UnitInfo in Match.army:
		if unit == null or unit.t_state != Enum.t_state.DEPLOYED or sleeping_markers.has(unit.get_instance_id()): continue
		var stun := Match.get_property(TargetRef.property(TargetRef.unit(unit.iun), UnitInfo.STUN_COUNTER))
		if stun == null or stun.value < 1: continue
		if not _sleeping_feedback_ready(unit): continue
		var marker := preload("res://scripts/board/board_trigger.gd").new()
		marker.setup(self, unit, unit.ihx, "sleeping")
		add_child(marker)
		sleeping_markers[unit.get_instance_id()] = weakref(marker)

## Sleeping creation reads the real actor pose, not a fixed delay; external Stun shows immediately even during another animation.
## Unmapped portraits have no sit sequence; existing sleeping loops retain their normal Stun-bound fade lifecycle.
## Validates stored displacement references before assigning a typed node; freed presenters never prevent later Bash-exit sleeping feedback.
func _sleeping_feedback_ready(unit: UnitInfo) -> bool:
	if external_stun_units.has(unit.get_instance_id()): return true
	if walking.has(unit.iun): return false
	if displacement_presenters.has(unit.iun):
		if not is_instance_valid(displacement_presenters[unit.iun]):
			displacement_presenters.erase(unit.iun)
		else:
			var displacement: Node2D = displacement_presenters[unit.iun]
			if not displacement.is_queued_for_deletion() and displacement.landing_hidden: return false
	var cell := hex_grid.get_child(unit.ihx) as HexCell
	for figure in cell.unit_figures.get_children():
		if figure is BoardCharacter and figure.unit_id == unit.iun: return figure.is_seated_for_feedback()
	return true

## Action/state notifications compare exact unit identities and retain prior positions/defeat state.
## Damage queues impact settling -> new Slash -> optional Skull; repeated current/max/death notifications share one sequence.
## Snapshots are cosmetic only: authoritative damage, defeat and captured trigger membership remain runner-owned.
## Any deployed current/max increase starts a single shared heart pulse, independently of damage feedback and duplicate refresh notifications.
func _observe_life_changes() -> void:
	for key in life_feedback.keys():
		if not is_instance_valid(life_feedback[key]): life_feedback.erase(key)
	for unit: UnitInfo in Match.army:
		if unit == null: continue
		var previous: Dictionary = observed_life.get(unit.iun, {})
		var same_unit: bool = previous.get("unit") == unit
		var reduced: bool = same_unit and (unit.actual_life < int(previous.actual) or unit.max_life < int(previous.maximum))
		var increased: bool = same_unit and (unit.actual_life > int(previous.actual) or unit.max_life > int(previous.maximum))
		if increased and unit.t_state == Enum.t_state.DEPLOYED:
			heart_pulses[unit.get_instance_id()] = {"unit": weakref(unit), "elapsed": 0.0, "start_scale": _heart_pulse_scale(unit)}
		var died: bool = same_unit and previous.get("deployed", false) and unit.t_state == Enum.t_state.DEFEATED
		var previous_hex: int = int(previous.get("hex", unit.ihx)) if same_unit else unit.ihx
		observed_life[unit.iun] = {"unit": unit, "actual": unit.actual_life, "maximum": unit.max_life,
			"hex": unit.ihx if unit.t_state == Enum.t_state.DEPLOYED else previous_hex, "deployed": unit.t_state == Enum.t_state.DEPLOYED}
		var existing: Variant = life_feedback.get(unit.get_instance_id())
		if is_instance_valid(existing):
			if died: existing.mark_death()
			continue
		if not reduced and not died: continue
		var hex_id := unit.ihx if unit.t_state == Enum.t_state.DEPLOYED else previous_hex
		if Match.get_hex(hex_id) == null: continue
		var sequence := preload("res://scripts/board/damage_feedback.gd").new()
		sequence.setup(self, unit, hex_id, _attack_feedback_delay(hex_id), Vector2i(int(previous.actual), int(previous.maximum)))
		life_feedback[unit.get_instance_id()] = sequence
		add_child(sequence)

## Board frame processing advances finite heart growth feedback for exact unit instances, pruning reset/dead/off-board identities.
## A simultaneous life reduction holds the pulse until Slash reveals the new values; each visible pulse lasts one second.
func _advance_heart_pulses(delta: float) -> void:
	for key in heart_pulses.keys():
		var pulse: Dictionary = heart_pulses[key]
		var unit: UnitInfo = pulse.unit.get_ref()
		if unit == null or Match.get_unit(unit.iun) != unit or unit.t_state != Enum.t_state.DEPLOYED:
			heart_pulses.erase(key)
			continue
		var damage: Variant = life_feedback.get(key)
		if is_instance_valid(damage) and not damage.is_queued_for_deletion() and not damage.life_revealed: continue
		pulse.elapsed += delta
		if pulse.elapsed >= 1.0: heart_pulses.erase(key)

## Hex-cell formatting uses two soft expansion/contraction beats over one second, blending repeated gains from the visible scale.
## This only controls artwork size and never changes health, rules or the snapshot model.
func _heart_pulse_scale(unit: UnitInfo) -> float:
	var pulse: Dictionary = heart_pulses.get(unit.get_instance_id(), {})
	if pulse.is_empty(): return 1.0
	var progress := clampf(float(pulse.elapsed), 0.0, 1.0)
	return lerpf(float(pulse.start_scale), 1.0, progress) + 0.24 * pow(sin(progress * TAU), 2.0)

## Ordinary hex and Bash health rows request the same owner-colored heart, enlarged by current gain feedback.
func life_heart(unit: UnitInfo, size: int = 48) -> String:
	return GameIcons.bb(&"heart", unit.player, roundi(size * _heart_pulse_scale(unit)))

## HexCell, damage ghosts and hover cards share this presentation-only life value; rules always read UnitInfo directly.
## A queued damage sequence holds previous values until 250ms into Slash, then pulses only the actual/max number that changed.
func life_number(unit: UnitInfo, maximum: bool = false, font_size: int = 31) -> String:
	var values := Vector2i(unit.actual_life, unit.max_life)
	var index := 1 if maximum else 0
	var size := font_size
	var feedback: Variant = life_feedback.get(unit.get_instance_id())
	if is_instance_valid(feedback) and not feedback.is_queued_for_deletion():
		if not feedback.life_revealed:
			values = feedback.previous_life
		elif values[index] != feedback.previous_life[index]:
			var pulse := clampf((feedback.elapsed - feedback.delay - 0.25) / 0.45, 0.0, 1.0)
			size = roundi(font_size * (1.0 + 0.22 * sin(pulse * PI)))
	return "[font_size=%d]%d[/font_size]" % [size, values[index]]

## Damage queues wait for incoming attack/bomb travel and resolved lit-bomb explosions, then a short impact beat before showing Slash.
func _attack_feedback_delay(hex_id: int) -> float:
	var delay := 0.25
	for child in get_children():
		if child.get_script() == FIRE_VISUAL and child.target_hex == hex_id:
			delay = maxf(delay, FIRE_VISUAL.TRAVEL_SECONDS - child.elapsed + 0.25)
		elif child.get_script() == preload("res://scripts/board/bomb_blast.gd"):
			delay = maxf(delay, child.delay + child.TRAVEL - child.elapsed + 0.25)
		elif child.get_script() == preload("res://scripts/board/bomb_explosion.gd") and child.hex_id == hex_id:
			delay = maxf(delay, child.delay + child.DURATION - child.elapsed + 0.25)
	return delay

## Converts a displayed axial coordinate to its stable Match map index.
## _on_cell_pressed() uses it before emitting hex_selected.
func _hex_id_at(coordinate: Vector2i) -> int:
	for tile in Match.map:
		if tile.coordinate == coordinate: return tile.hex_id
	return -1

## Clears the finished selection before the controller records the spent action.
## effect_completed includes cost_paid and Action-free status so the controller spends only required tokens.
func _on_effect_finished(success: bool) -> void:
	var paid := effect_execution.cost_paid
	if selection != null and selection.changed.is_connected(_on_selection_changed):
		selection.changed.disconnect(_on_selection_changed)
	selection = null
	selectable_hexes.clear()
	_on_selection_changed()
	effect_completed.emit(success, paid, effect_execution.action_free)

func _cancel_current() -> void:
	if selection != null: selection.cancel()

func _attach_selection(next: PhraseExecution) -> void:
	if selection != null and selection.changed.is_connected(_on_selection_changed):
		selection.changed.disconnect(_on_selection_changed)
	selection = next
	selection.changed.connect(_on_selection_changed)
	_on_selection_changed()

## Redraws target, deployment, and confirmation affordances from current UI state.
## PhraseExecution.changed and show_hex_choices() call this; AMOUNT shows a bounded input for the retained counter rather than another target list.
## Courier's neutral amount choice names its later recipient step without falsely claiming that already-paid activity remains unpaid.
func _on_selection_changed() -> void:
	choice_menu.hide()
	choices = []
	unit_choice_ids.clear()
	var hexes: Array[int] = []
	var has_offboard := false
	if selection != null:
		for candidate in selection.candidates:
			if candidate.has_hex(): hexes.append(candidate.hex_id())
			else: has_offboard = true
	var choosing := selection != null and selection.status in [PhraseExecution.Status.SUBJECT, PhraseExecution.Status.TARGET]
	for cell: HexCell in hex_grid.get_children():
		var selected := cell.hex_info.hex_id in hexes if choosing else cell.hex_info.hex_id in selectable_hexes
		cell.refresh(selected, selected_unit_id)
	offboard_button.visible = choosing and has_offboard
	confirm_button.visible = (effect_execution != null and effect_execution.status == EffectExecution.Status.CONFIRMING) or (selection != null and selection.status == PhraseExecution.Status.CONFIRMING)
	amount_controls.visible = selection != null and selection.status == PhraseExecution.Status.AMOUNT
	if amount_controls.visible:
		amount_input.max_value = selection.amount_max
		amount_input.value = 1
	selection_label.text = ""
	if confirm_button.visible:
		selection_label.text = "Use this optional effect? Esc skips."
	elif choosing:
		var role := "subject" if selection.status == PhraseExecution.Status.SUBJECT else "target"
		selection_label.text = "Choose %s — click a highlighted hex. Esc cancels." % role
		if hexes.is_empty(): selection_label.text = "Choose %s using the button below. Esc cancels." % role
		if effect_execution != null and not effect_execution.can_cancel():
			selection_label.text = selection_label.text.replace(" Esc cancels.", "")
		if selection.status == PhraseExecution.Status.TARGET and selection.phrase.target is Selectors.CountersOf:
			selection_label.text = "Choose a unit and counter kind to transfer." if selection.phrase.verb.name == &"choose_counter" else "Choose the counter kind on the selected unit."
			_show_counter_choices.call_deferred(selection)
	elif amount_controls.visible:
		if selection.phrase.verb.name == &"choose_counter":
			selection_label.text = "Choose 1–%d counters, then choose their recipient." % selection.amount_max
		else: selection_label.text = "Choose X: 1–%d counters. No payment until all choices are confirmed." % selection.amount_max
	elif selection != null and selection.status == PhraseExecution.Status.FAILED:
		selection_label.text = "This action has no valid selection." if selection.error.is_empty() else selection.error

## The X button submits one integer to the same pending phrase; stale clicks and balance changes remain authoritative validation failures.
func _on_amount_chosen() -> void:
	_selection_click_accepted = true
	if selection != null: selection.choose_amount(int(amount_input.value))

## Unit selection has completed before this deferred counter-kind menu opens; stale callbacks cannot reopen a previous phrase's choices.
## Porcupine fixes a host first; Courier may offer several named hosts. Both pick one PROPERTY identity and keep amount/destination choices in the execution.
func _show_counter_choices(expected: PhraseExecution) -> void:
	if selection != expected or expected.status != PhraseExecution.Status.TARGET: return
	_show_choices(expected.candidates)

func _show_offboard_choices() -> void:
	if selection == null: return
	_show_choices(selection.candidates.filter(func(ref: TargetRef) -> bool: return not ref.has_hex()))

func _show_choices(options: Array[TargetRef]) -> void:
	unit_choice_ids.clear()
	choices = options
	choice_menu.clear()
	for candidate in choices: choice_menu.add_item(candidate.label())
	choice_menu.position = Vector2i(get_viewport().get_mouse_position()) if choice_menu.is_embedded() else DisplayServer.mouse_get_position()
	choice_menu.popup()

## Opens a small picker when a Bash leaves multiple units on one occupied hex.
## _on_cell_pressed() calls this so the player can select the intended figure.
func _show_unit_choices(unit_ids: Array[int]) -> void:
	choices.clear()
	unit_choice_ids = unit_ids.duplicate()
	choice_menu.clear()
	for unit_id in unit_choice_ids:
		var unit := Match.get_unit(unit_id)
		choice_menu.add_item(unit.name if unit != null else "Missing unit")
	choice_menu.position = Vector2i(get_viewport().get_mouse_position()) if choice_menu.is_embedded() else DisplayServer.mouse_get_position()
	choice_menu.popup()

## PopupMenu.index_pressed commits the selected identity after its pointer input has been claimed by the menu handler.
## PhraseExecution revalidates the choice; menu clicks never invoke outside-board cancellation or select all occupants.
func _on_choice_pressed(index: int) -> void:
	if selection != null and index >= 0 and index < choices.size():
		_selection_click_accepted = true
		var chosen := choices[index]
		selection.choose(chosen)
	elif index >= 0 and index < unit_choice_ids.size():
		_selection_click_accepted = true
		unit_selected.emit(unit_choice_ids[index])
		unit_choice_ids.clear()

## PopupMenu.window_input handles Escape but treats popup pointer presses as inside the chooser.
## Forwarding these clicks to _unhandled_input would cancel a pending phrase before index_pressed commits on release.
func _on_choice_window_input(event: InputEvent) -> void:
	if event.is_action_pressed("board_cancel"):
		_unhandled_input(event)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_selection_click_accepted = true

## Handles Escape and schedules outside-board cancellation only after HUD controls receive input.
## Godot/cell popup input calls this; action buttons consume their press before their release
## switches the preview. Deferring unhandled clicks lets HexCell physics picking claim targets.
## Idle clicks on pending Bow/Fire or placed bomb artwork replay their cosmetic action and consume the click before hex picking.
## Existing target/deployment choices retain priority over this marker interaction.
## Idle selected units still schedule the deferred click-away check; unit picking can claim the click before it runs.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("board_cancel") and effect_execution != null:
		effect_execution.cancel()
		get_viewport().set_input_as_handled()
		return
	if not event is InputEventMouseButton or event.button_index != MOUSE_BUTTON_LEFT or not event.pressed: return
	var waiting_for_target := selection != null and selection.status in [PhraseExecution.Status.SUBJECT, PhraseExecution.Status.TARGET, PhraseExecution.Status.AMOUNT]
	var waiting_for_tile := not selectable_hexes.is_empty()
	if not waiting_for_target and not waiting_for_tile:
		for child in get_children():
			if child.get_script() != FIRE_VISUAL or not (child.attack is BowAttack or child.attack is FireAttack): continue
			if Rect2(-42, -42, 84, 84).has_point(child.get_local_mouse_position()):
				if child.attack is BowAttack: replay_bow_counter(child.attack)
				else: replay_fire_counter(child.attack)
				get_viewport().set_input_as_handled()
				return
		for cell: HexCell in hex_grid.get_children():
			if not cell.bomb_sprite.visible: continue
			if not Rect2(-42, -42, 84, 84).has_point(cell.bomb_sprite.get_local_mouse_position() * cell.bomb_sprite.scale): continue
			var bomb := Match.bomb_at(cell.hex_info.hex_id)
			if bomb == null: continue
			replay_bomb_counter(bomb)
			get_viewport().set_input_as_handled()
			return
	if not waiting_for_target and not waiting_for_tile and selected_unit_id < 0: return
	_selection_click_accepted = false
	call_deferred("_clear_focus_after_unmatched_click", selection if waiting_for_target else null, waiting_for_tile)

## Scene teardown cancels only local previews; reconnect handoff must not submit a new online command.
func _exit_tree() -> void:
	if not NetworkSession.online: _cancel_current()

## Resolved bomb_light starts one cosmetic radial blast; matching Fire markers supply their remaining travel delay.
## The blast overlay owns only visibility/animation and captures pending area records without changing their combat schedule.
func _present_bomb_blast(hex_id: int) -> void:
	if Match.get_hex(hex_id) == null: return
	var delay := 0.0
	for child in get_children():
		if child.get_script() == FIRE_VISUAL and child.action_kind == &"fire" and child.aims_at_bomb and child.target_hex == hex_id:
			delay = maxf(delay, maxf(0.0, FIRE_VISUAL.TRAVEL_SECONDS - child.elapsed))
	var blast := preload("res://scripts/board/bomb_blast.gd").new()
	blast.setup(self, hex_id, delay)
	add_child(blast)
	blast._process(0.0)

## Runner queue-head gates request feedback before trigger activation; observation later sees the same execution and never duplicates it.
func _on_trigger_presentation_requested(execution: EffectExecution) -> void:
	if NetworkSession.fast_replay:
		Match.rules_runner.presentation_ready = true
		return
	_present_trigger(execution)
	trigger_cues_changed.emit()

## Board frame updates retry delayed trigger presentation after attack, movement, damage and death feedback completes.
func _sync_trigger_presentation() -> void:
	var waiting := Match.rules_runner.presentation_waiting
	if waiting == null or Match.rules_runner.presentation_ready or waiting.source == null: return
	var unit := Match.get_unit(waiting.source.id)
	if unit == null: return
	if trigger_cues.has(unit.iun):
		_queue_trigger_feedback(unit, int(trigger_cues[unit.iun].get("hex", unit.ihx)))

## Keeps the blink behind its complete causal animation chain, including a lethal Slash followed by Skull.
## A lit-bomb explosion and a returned unit's departing snapshot are finite causal feedback even after their rules records leave the board.
func _trigger_animation_busy() -> bool:
	for feedback in life_feedback.values():
		if is_instance_valid(feedback) and not feedback.is_queued_for_deletion(): return true
	if not walking.is_empty(): return true
	for presenter in displacement_presenters.values():
		if is_instance_valid(presenter) and presenter.landing_hidden: return true
	for child in get_children():
		if child.get_script() == preload("res://scripts/board/board_return.gd") and not child.is_queued_for_deletion(): return true
		if child.get_script() == preload("res://scripts/board/bomb_explosion.gd") and not child.is_queued_for_deletion(): return true
		if child.get_script() == FIRE_VISUAL and child.elapsed < FIRE_VISUAL.TRAVEL_SECONDS: return true
		if child.get_script() == preload("res://scripts/board/bomb_blast.gd") and child.elapsed < child.delay + child.TRAVEL: return true
	return false

## Hot-seat input submits the next missing identity; online Space/blink input submits only this client's authenticated seat.
func _acknowledge_next_local_player() -> void:
	if NetworkSession.online:
		acknowledge_trigger_for_player(NetworkSession.local_player)
		return
	for player in [1, 2]:
		if player not in Match.rules_runner.presentation_acknowledged:
			acknowledge_trigger_for_player(player)
			return

## Explicit player entry point preserves separate acknowledgements and fades the blink before releasing queued trigger work.
## Online input carries the local seat; the host checks the relay-authenticated sender before calling the runner.
func acknowledge_trigger_for_player(player: int) -> void:
	var runner := Match.rules_runner
	var waiting := runner.presentation_waiting
	if NetworkSession.routes_input():
		if waiting != null: NetworkSession.request_intent({"kind": "ack", "player": NetworkSession.local_player, "source": waiting.source.id})
		return
	if not runner.acknowledge_trigger(waiting, player): return
	trigger_cues_changed.emit()
	if runner.presentation_acknowledged.size() < 2: return
	var marker: Variant = trigger_cues.get(waiting.source.id, {}).get("marker")
	if is_instance_valid(marker):
		marker.tree_exited.connect(func() -> void: runner.release_trigger_presentation(waiting), CONNECT_ONE_SHOT)
		_dismiss_trigger_cue(waiting.source.id)
	else:
		runner.release_trigger_presentation.call_deferred(waiting)

## RulesRunner queries only finite action/impact/death/arrival feedback; ambient loops, pending counters and old-action replays never block phases.
## The sign's own entrance also settles before the next phase so brief phase labels remain synchronized with authoritative state.
## Bomb replicas remain persistent while any captured blast record is unresolved, including records already frozen out of the public queue.
## Empty replicas finish their shared fade before the frozen blast batch begins its individual occupied-hex animations.
## Reconnect fast replay bypasses only these cosmetic waits while rebuilding accepted history.
func _phase_presentation_busy() -> bool:
	if NetworkSession.fast_replay: return false
	if not heart_pulses.is_empty(): return true
	if _trigger_animation_busy(): return true
	for presenter in displacement_presenters.values():
		if is_instance_valid(presenter) and not presenter.is_queued_for_deletion(): return true
	for cell: HexCell in hex_grid.get_children():
		if cell.bomb_throw_elapsed >= 0.0: return true
		if cell.bash_exit_tween != null and cell.bash_exit_tween.is_running(): return true
		for figure in cell.unit_figures.get_children():
			if figure is BoardCharacter and figure._command_animating(): return true
	for child in get_children():
		if child.is_queued_for_deletion(): continue
		if child.get_script() == FIRE_VISUAL:
			var pending: Array = Match.pending_attacks
			if child.action_kind == &"bow": pending = Match.pending_bow_attacks
			elif child.action_kind == &"cannon": pending = Match.pending_cannon_attacks
			if child.attack == null or child.attack.resolved or not pending.has(child.attack): return true
		elif child.get_script() == preload("res://scripts/board/board_trigger.gd") and child.lifetime > 0.0: return true
		elif child.get_script() == preload("res://scripts/board/bomb_blast.gd"):
			if child.empty_fade_busy(): return true
			var pending := false
			for attack in child.attacks:
				if not attack.resolved: pending = true
			if not pending: return true
	var sign: Variant = phase_sign_feedback.get_ref() if phase_sign_feedback != null else null
	return is_instance_valid(sign) and sign.is_transitioning()

## Godot frame updates retry a retained runner continuation once all finite presentation completes; deferred drain avoids repaint reentrancy.
func _resume_phase_presentation() -> void:
	var runner := Match.rules_runner
	if not runner.continuation_waiting or runner.presentation_waiting != null or _phase_presentation_busy(): return
	runner.continuation_waiting = false
	runner.drain.call_deferred()
