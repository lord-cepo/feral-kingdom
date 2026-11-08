## FIFO cosmetic recipient clips and positive-value observations; definitions and authoritative rules remain untouched.
extends Node

var board: GuerraBoard
var pending: Array[Dictionary] = []
var active: Node
var observed: Dictionary = {}

## Board._ready installs this after its presentation listeners; state/action notifications compare committed values once.
func setup(owner_board: GuerraBoard) -> void:
	board = owner_board
	Match.state_changed.connect(observe)
	Match.action_event.connect(_on_action)
	observe()

## Action events cover counter/ability grants that do not emit state_changed; duplicate notifications see the same baseline.
func _on_action(_event: EffectEvent) -> void:
	observe()

## Captures displayed numeric parameters using the same bound ability and effective-action getters as gameplay previews.
## Stable effect identities distinguish two abilities of one family; life, modifiers and all current numeric action families are included.
func values(unit: UnitInfo) -> Dictionary:
	var result := {"life": unit.actual_life, "maximum": unit.max_life,
		"physical": unit.physical_modifier, "magical": unit.magical_modifier}
	var ctx := RuleContext.new(TargetRef.unit(unit.iun))
	ctx.subject = ctx.source
	for effect in unit.effects:
		if effect == null or not effect.consequence is Effect.ConsequencePhrase: continue
		var verb: Effect.Verb = effect.consequence.verb
		if verb.name not in [&"move", &"fly", &"bow", &"fire", &"cannon", &"gore", &"bomb_throw", &"mend", &"stun", &"shield", &"mshield", &"push", &"pull"]: continue
		var bound := verb.bound_to(ctx)
		var parameters: Array[int] = []
		var count := 1 if verb.name in [&"move", &"fly", &"fire", &"shield", &"mshield"] else 2
		for index in mini(count, bound.user_params.size()):
			if typeof(bound.user_params[index]) in [TYPE_INT, TYPE_FLOAT]: parameters.append(int(bound.user_params[index]))
		parameters = unit.effective_action_values(verb.name, parameters)
		for index in parameters.size(): result["%s:%d" % [effect.get_instance_id(), index]] = parameters[index]
		if verb.name == &"fire":
			result["%s:range" % effect.get_instance_id()] = EffectText.selector_range(effect.consequence.target) + unit.ability_bonus(verb).y
	return result

## A known parameter must increase on the same continuously deployed identity; initial load, deployment, decreases and replay are silent.
## One observation queues one upgrade per recipient even when several parameters rise together.
func observe() -> void:
	if NetworkSession.fast_replay: pending.clear()
	var next := {}
	for unit: UnitInfo in Match.army:
		if unit.t_state != Enum.t_state.DEPLOYED: continue
		var current := values(unit)
		var key := unit.get_instance_id()
		var previous: Dictionary = observed.get(key, {})
		if not NetworkSession.fast_replay:
			for parameter in current:
				if previous.has(parameter) and current[parameter] > previous[parameter]:
					enqueue(unit, "upgrade", 1.125)
					break
		next[key] = current
	observed = next

## Board recipient feedback and value observations retain the exact recipient until their finite clip can start.
func enqueue(unit: UnitInfo, clip: String, duration: float) -> void:
	pending.append({"unit": unit, "clip": clip, "duration": duration})

## Phase continuations and trigger acknowledgement presentation wait for queued clips as well as the playing clip.
func busy() -> bool:
	return not pending.is_empty() or (is_instance_valid(active) and not active.is_queued_for_deletion())

## Start only after pre-existing finite feedback settles; persistent sleeping, trigger and ambience loops are excluded by Board.
## Later queued recipient clips wait for this one to exit; removed or replaced recipients are discarded without substitution.
func _process(_delta: float) -> void:
	if is_instance_valid(active) and not active.is_queued_for_deletion(): return
	if pending.is_empty() or board._finite_presentation_busy(): return
	var entry: Dictionary = pending.pop_front()
	var unit: UnitInfo = entry.unit
	if NetworkSession.fast_replay or Match.get_unit(unit.iun) != unit or unit.t_state != Enum.t_state.DEPLOYED: return
	active = preload("res://scripts/board/board_trigger.gd").new()
	active.setup(board, unit, unit.ihx, entry.clip, entry.duration)
	board.add_child(active)
	active._process(0.0)
