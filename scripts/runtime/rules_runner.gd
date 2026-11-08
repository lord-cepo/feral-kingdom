## Owns commands, captured triggers and resumable phase/combat work.
## Match publishes occurrences; Board observes executions and submits choices.
class_name RulesRunner
extends RefCounted

signal execution_started(execution: EffectExecution)
signal command_finished(success: bool, cost_paid: bool, action_free: bool)
signal idle
signal trigger_presentation_requested(execution: EffectExecution)

var active: EffectExecution
var work: Array = []
var dispatched_occurrences: Dictionary = {}
var diagnostics: Array[String] = []
var draining := false
var halted := false
var boundary_depth := 0
var boundary_work: Array = []
var command_owner := 0
var command_open := false
var command_result: EffectExecution
var operations := 0
const MAX_WORK_PER_COMMAND := 1024
## The graphical board enables acknowledgement gates; headless rule consumers leave presentation disabled.
var trigger_acknowledgements_enabled := false
var presentation_waiting: EffectExecution
var presentation_ready := false
var presentation_acknowledged: Array[int] = []
var acknowledged_triggers: Dictionary = {}
## Optional graphical-client query; headless consumers advance without presentation waits.
var presentation_busy_query: Callable
var continuation_waiting := false

## Reports pending ownership including a two-player trigger acknowledgement gate; competing commands and Pass stay blocked.
func busy() -> bool:
	return presentation_waiting != null or active != null or command_open or not work.is_empty() or boundary_depth > 0 or halted

## Opens a mutation boundary; combat/Match pair this with end_boundary after cleanup.
func begin_boundary() -> void:
	boundary_depth += 1

## Releases captured triggers only after the outer mutation and death handling finish.
func end_boundary() -> void:
	assert(boundary_depth > 0)
	boundary_depth -= 1
	if boundary_depth == 0:
		work = boundary_work + work
		boundary_work = []
		drain()

## Validates an occurrence, filters continuous defeat policy, and captures matching rules now.
## Consequences cannot change membership; Match.action_event calls this and defeat captures before removal.
## Limited triggers reserve their turn before enqueueing; death amplifiers create independent activations for actual death.
func capture_event(event: EffectEvent) -> void:
	if event == null or dispatched_occurrences.has(event.occurrence_id): return
	dispatched_occurrences[event.occurrence_id] = true
	var event_error := event.validation_error()
	if not event_error.is_empty():
		diagnostics.append(event_error)
		return
	if _suppresses_event_triggers(event): return
	var captured: Array = []
	for owner in [event.controller, 3 - event.controller]:
		for unit in Match.army:
			if unit == null or unit.player != owner or unit.t_state != Enum.t_state.DEPLOYED: continue
			for definition in unit.trigger_effects:
				if definition == null or definition.event == null: continue
				var ctx := RuleContext.new(TargetRef.unit(unit.iun), event)
				var validation: String = definition.event.validate(ctx)
				if not validation.is_empty():
					diagnostics.append(validation)
					continue
				if not definition.event.matches(ctx, event): continue
				var passes := definition.condition == null or definition.condition.test(ctx)
				if not ctx.error.is_empty():
					diagnostics.append(ctx.error)
					continue
				if not passes: continue
				var turn_key := definition.once_per_turn_key
				if not turn_key.is_empty():
					if unit.trigger_turns.get(turn_key, -1) == event.turn_number: continue
					unit.trigger_turns[turn_key] = event.turn_number
				for repeat in _death_activation_count(unit, event):
					var execution := EffectExecution.new(definition, ctx.source, event)
					execution.captured_trigger = true
					execution.managed = true
					captured.append(execution)
	if active != null: active.followups.append_array(captured)
	elif boundary_depth > 0: boundary_work.append_array(captured)
	else: work = captured + work
	drain()

## Capture evaluates friendly death-trigger amplifiers before removal; extra activations do not emit another Die or recursively amplify themselves.
func _death_activation_count(unit: UnitInfo, event: EffectEvent) -> int:
	var count := 1
	if event.action != &"die": return count
	for source in Match.army:
		if source == null or source.t_state != Enum.t_state.DEPLOYED: continue
		for aura in source.continuous_effects:
			if aura == null or not aura.applies_to(source.iun, unit.iun): continue
			for output in aura.contributions:
				if output != null and output.kind == Contribution.Kind.EXTRA_DEATH_TRIGGER: count += maxi(0, output.extra_triggers)
	return count

## Applies continuous suppression to a Die or Deploy cause, before capturing any watcher on either side.
## Match.defeat() calls capture_event before removal, so the continuous source snapshot is live.
func _suppresses_event_triggers(event: EffectEvent) -> bool:
	if event.action not in [&"die", &"deploy"] or event.subject == null or event.subject.kind != TargetRef.Kind.UNIT: return false
	for source in Match.army:
		if source == null or source.t_state != Enum.t_state.DEPLOYED: continue
		for aura in source.continuous_effects:
			if aura == null or not aura.applies_to(source.iun, event.subject.id): continue
			for output in aura.contributions:
				if output == null: continue
				if event.action == &"die" and output.kind == Contribution.Kind.SUPPRESS_DEFEAT_TRIGGERS: return true
				if event.action == &"deploy" and output.kind == Contribution.Kind.SUPPRESS_DEPLOY_TRIGGERS: return true
	return false

## Starts one player command, optionally presenting a target before any action cost.
## LocalMatchController calls this; busy/illegal commands leave current work untouched.
## Online calls route catalogue effect slots to the host before entering this same execution path.
func submit(effect: Effect, source: TargetRef, defer_cost_until_target: bool = false) -> bool:
	if NetworkSession.routes_input():
		var unit := Match.get_unit(source.id) if source != null and source.kind == TargetRef.Kind.UNIT else null
		return NetworkSession.request_intent({"kind": "effect", "unit": source.id, "slot": unit.effects.find(effect)}) if unit != null else false
	if busy() or Match.winner != 0 or Match.phase != Match.Phase.ACTION: return false
	if source == null or Match.owner_of(source) != Match.active_player: return false
	if not available(effect, source): return false
	command_open = true
	command_owner = Match.active_player
	operations = 0
	var execution := EffectExecution.new(effect, source)
	execution.managed = true
	execution.defer_cost_until_target = defer_cost_until_target
	command_result = execution
	work.append(execution)
	work.append(_finish_command)
	drain()
	return true

## Checks HUD availability without paying; Tireless remains usable while inactive.
## submit repeats these source/token checks before taking ownership.
func available(effect: Effect, source: TargetRef) -> bool:
	if effect == null or source == null or not source.has_hex(): return false
	if Match.players[Match.owner_of(source)].actions_remaining <= 0 and not effect.is_action_free(): return false
	var ctx := RuleContext.new(source)
	if effect.condition != null and not effect.condition.test(ctx): return false
	if effect.cost is Effect.CostPhrase:
		var cost := effect.cost as Effect.CostPhrase
		if cost.verb.name == &"self_stun" and not Match.get_unit(source.id).active: return false
	return ctx.error.is_empty()

## Match's no-action loss check queries legal commands without starting previews, paying costs, or capturing events.
## Explores complete payment choices with consequence bindings intact; previews neither pay costs nor publish their synthetic cost_N records.
func command_available(effect: Effect, source: TargetRef) -> bool:
	if not available(effect, source): return false
	var ctx := RuleContext.new(source)
	ctx.preview_numbers = true
	var payments: Array = []
	if effect.cost is Effect.CostPhrase: payments.append(effect.cost)
	elif effect.cost is Effect.CostBundle:
		if not effect.cost.validate().is_empty(): return false
		payments.append_array(effect.cost.phrases)
	return _cost_choices_available(payments, 0, ctx, {}, {}, effect.consequence)

## A full payment preview checks its first consequence with captured counter kinds/amounts and explicit cost-created zone recipients.
## The recursive shadow ledger calls this only after all chosen costs are payable; sequence previews still require their first mandatory step.
func _consequence_available(consequence: RefCounted, ctx: RuleContext, payments: Array) -> bool:
	# Returning a friend creates a legal hand candidate even when the hand is currently empty.
	if consequence is Effect.Phrase and consequence.verb.name == &"deploy_returned_hex": return true
	if consequence is Effect.Phrase and consequence.verb.name == &"revive":
		for index in payments.size():
			var payment: Effect.Phrase = payments[index]
			if payment.verb.name != &"disable": continue
			var selected: Array = ctx.completed_results.get("cost_%d" % index, {}).get("targets", [])
			if selected.size() != 1: continue
			var recipient := Match.get_unit(selected[0].id)
			if recipient.iun != ctx.source.id and recipient.type != Enum.type.HERO and recipient.max_life > 0: return true
	if consequence is Effect.Phrase: return not _legal_phrase_pairs(consequence, ctx).is_empty()
	if consequence is Effect.ConsequenceSequence:
		for phrase in consequence.phrases:
			if phrase.optional: continue
			return not _legal_phrase_pairs(phrase, ctx).is_empty()
		return not consequence.phrases.is_empty()
	return false

## Read-only actor/recipient pairs use the same conversion and verb legality boundary as PhraseExecution; no choice is committed.
func _legal_phrase_pairs(phrase: Effect.Phrase, ctx: RuleContext) -> Array:
	var pairs: Array = []
	if phrase == null or phrase.verb == null: return pairs
	var actors := TargetResolver.resolve(phrase.subject, phrase.verb.subject_kind, ctx)
	if not actors.error.is_empty(): return pairs
	for actor in actors.candidates:
		if not phrase.verb.accepts_subject(actor): continue
		ctx.subject = actor
		ctx.query_verb = phrase.verb
		var targets := TargetResolver.resolve(phrase.target, phrase.verb.target_kind, ctx)
		if not targets.error.is_empty(): continue
		for target in targets.candidates:
			if phrase.verb.bound_to(ctx).can_apply(actor, target): pairs.append([actor, target])
	ctx.subject = null
	return pairs

## Availability explores payment identities with copied shadow ledgers, rejecting cumulative resource reuse without touching Match.
## Shadow ledgers bind dependent unit/counter choices and preview-only cost_N results through consequence eligibility, without writing definitions/resources.
## Self-Stun, deployment balances and sacrifice reservations share the shadow ledger, matching CostPayment without changing Match.
func _cost_choices_available(payments: Array, index: int, ctx: RuleContext, counters: Dictionary, activity: Dictionary, consequence: RefCounted) -> bool:
	if index >= payments.size(): return _consequence_available(consequence, ctx, payments)
	var phrase: Effect.Phrase = payments[index]
	for pair in _legal_phrase_pairs(phrase, ctx):
		var target: TargetRef = pair[1]
		var next_counters := counters.duplicate()
		var next_activity := activity.duplicate()
		var verb := phrase.verb.bound_to(ctx)
		var host_id := target.host.id if target.kind == TargetRef.Kind.PROPERTY and target.host.kind == TargetRef.Kind.UNIT else target.id if target.kind == TargetRef.Kind.UNIT else -1
		if host_id >= 0 and next_counters.has("sacrificed:%d" % host_id): continue
		if phrase.verb.name == &"spend_deployment":
			var key := "deployments:%d" % target.id
			var remaining: int = next_counters.get(key, Match.players[target.id].deployments_remaining)
			if remaining < 1: continue
			next_counters[key] = remaining - 1
		elif phrase.verb.name in [&"disable", &"return_to_hand"]:
			next_counters["sacrificed:%d" % target.id] = true
		elif phrase.verb.name == &"sacrifice":
			var paid_life: Vector2i = next_counters.get("life:%d" % target.id, Vector2i(1, 1))
			if paid_life.x <= 0: continue
			next_counters["sacrificed:%d" % target.id] = true
		elif phrase.verb.name == &"decrement":
			var key := target.identity()
			var prop := Match.get_property(target)
			if prop == null: continue
			var remaining: int = next_counters.get(key, prop.value)
			var amount: int = verb.user_params[0]
			if remaining < amount: continue
			next_counters[key] = remaining - amount
		elif phrase.verb.name == &"pay_life":
			var unit := Match.get_unit(target.id)
			var key := "life:%d" % target.id
			var value: Vector2i = next_counters.get(key, Vector2i(unit.actual_life, unit.max_life))
			var actual: int = phrase.verb.user_params[0]
			var maximum: int = phrase.verb.user_params[1]
			if value.x <= 0 or value.x < actual or value.y < maximum: continue
			next_counters[key] = Vector2i(mini(value.x - actual, value.y - maximum), value.y - maximum)
		elif phrase.verb.name in [&"self_stun", &"deactivate"]:
			if next_activity.has(target.id): continue
			next_activity[target.id] = true
			if phrase.verb.name == &"self_stun":
				var stun := TargetRef.property(target, UnitInfo.STUN_COUNTER)
				next_counters[stun.identity()] = int(next_counters.get(stun.identity(), Match.get_property(stun).value)) + int(verb.user_params[1])
		var previous := ctx.completed_results
		ctx.completed_results = previous.duplicate()
		var amount := int(verb.user_params[0]) if verb.name in [&"decrement", &"choose_counter"] else -1
		if verb.name == &"sacrifice":
			var donor_life: Vector2i = next_counters.get("life:%d" % target.id, Vector2i(Match.get_unit(target.id).actual_life, 0))
			amount = donor_life.x
		var record := {"subject": pair[0], "targets": [target], "success": true, "amount": amount, "preview": true}
		ctx.completed_results["cost_choice_%d" % index] = record
		ctx.completed_results["cost_%d" % index] = record
		var payable := _cost_choices_available(payments, index + 1, ctx, next_counters, next_activity, consequence)
		ctx.completed_results = previous
		if payable: return true
	return false

## Drains ordered work until a retained execution waits for UI or the diagnostic limit trips.
## Boundary/choice completion and scheduling call this guarded loop.
## A captured trigger stays at the queue head until presentation is ready and both player identities acknowledge it.
## Queued continuations (including phase changes/token completion) wait for the graphical client's finite action animations.
func drain() -> void:
	if draining or boundary_depth > 0 or active != null or halted: return
	if presentation_waiting != null: return
	draining = true
	while not work.is_empty() and active == null and not halted:
		var next: Variant = work[0]
		if next is Callable and presentation_busy_query.is_valid() and presentation_busy_query.call():
			continuation_waiting = true
			break
		continuation_waiting = false
		if trigger_acknowledgements_enabled and next is EffectExecution and next.captured_trigger:
			var key: int = next.get_instance_id()
			if not acknowledged_triggers.has(key) or acknowledged_triggers[key].get_ref() != next:
				presentation_waiting = next
				presentation_ready = false
				presentation_acknowledged.clear()
				trigger_presentation_requested.emit(next)
				break
		operations += 1
		if operations > MAX_WORK_PER_COMMAND:
			halted = true
			diagnostics.append("Rules paused: excessive trigger chain; pending work retained.")
			break
		var item = work.pop_front()
		if item is EffectExecution:
			active = item
			active.finished.connect(_effect_finished.bind(active), CONNECT_ONE_SHOT)
			execution_started.emit(active)
			active.start()
		else: (item as Callable).call()
	draining = false
	if not busy():
		operations = 0
		Match.settle_sacrificed_heroes()
		idle.emit()

## Board/local input or a future authenticated network adapter submits one distinct player acknowledgement for this exact gate.
## Rejects stale gates, duplicate players and input before causal damage/death presentation has completed; never executes a trigger here.
func acknowledge_trigger(execution: EffectExecution, player: int) -> bool:
	if execution == null or execution != presentation_waiting or not presentation_ready or player not in [1, 2]: return false
	if player in presentation_acknowledged: return false
	presentation_acknowledged.append(player)
	return true

## Board calls after the acknowledged blink finishes fading; restores queued rules only when both player identities have acknowledged.
func release_trigger_presentation(execution: EffectExecution) -> void:
	if execution == null or execution != presentation_waiting or presentation_acknowledged.size() < 2: return
	acknowledged_triggers[execution.get_instance_id()] = weakref(execution)
	presentation_waiting = null
	presentation_ready = false
	presentation_acknowledged.clear()
	drain()

## Suspends a paid parent while its cost triggers resolve before the consequences.
## EffectExecution calls this once; the parent is retained by its continuation.
func after_cost(execution: EffectExecution) -> void:
	assert(active == execution)
	active = null
	work = execution.followups + [_resume.bind(execution)] + work
	execution.followups = []
	drain()

## Restores the parent and Board binding after cost followups finish.
func _resume(execution: EffectExecution) -> void:
	active = execution
	execution_started.emit(execution)
	execution.begin_consequences()

## Releases bundle followups before siblings; connected to each managed finished signal.
func _effect_finished(_success: bool, execution: EffectExecution) -> void:
	if not execution.error.is_empty(): diagnostics.append(execution.error)
	active = null
	work = execution.followups + work
	execution.followups = []
	drain()

## Pays one committed token after followups even if a live allowance disappeared; free commands ending the last available window still advance phases.
## submit queues this continuation with the original controller and execution.
func _finish_command() -> void:
	var result := command_result
	command_open = false
	command_result = null
	Match.settle_sacrificed_heroes()
	var success := result.status == EffectExecution.Status.SUCCEEDED
	var free := result.action_free
	if (success or result.cost_paid) and not free and Match.winner != 0:
		Match.players[command_owner].base_actions_remaining -= 1
		Match.state_changed.emit()
	elif (success or result.cost_paid) and not free: Match.finish_action(command_owner, true)
	elif success and free and Match.players[command_owner].actions_remaining == 0: Match.complete_action(command_owner, 0)
	command_finished.emit(success, result.cost_paid, free)

## Prepends explicit phase/combat continuations; Match calls this instead of recursive advancement.
func schedule(steps: Array) -> void:
	work = steps + work
	drain()

## Identifies triggered execution for action legality outside the standalone Action window.
## Actions still enforce geometry, recipient, source and activity requirements.
func is_triggered() -> bool:
	return active != null and active.captured_trigger

## Clears all ownership before Match initializes another match/test scenario.
## Cancels stale acknowledgement identities while preserving the graphical client's configured gate policy.
func reset() -> void:
	continuation_waiting = false
	presentation_waiting = null
	presentation_ready = false
	presentation_acknowledged.clear()
	acknowledged_triggers.clear()
	active = null
	work.clear()
	boundary_work.clear()
	dispatched_occurrences.clear()
	diagnostics.clear()
	draining = false
	halted = false
	boundary_depth = 0
	command_open = false
	command_result = null
	operations = 0
