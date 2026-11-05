class_name EffectExecution
extends RefCounted

signal phrase_started(execution: PhraseExecution)
signal finished(success: bool)
signal confirmation_requested
enum Status { IDLE, CONFIRMING, COST, CONSEQUENCE, SUCCEEDED, FAILED, CANCELLED }

var definition: Effect
var source: TargetRef
var triggering_event: EffectEvent
var status := Status.IDLE
var current: PhraseExecution
var results: Dictionary = {}
var error := ""
var cost_paid := false
var managed := false
var captured_trigger := false
var defer_cost_until_target := false
var followups: Array = []
var _cost_index := 0
var _cost_choices: Array[PhraseExecution] = []
var _consequence_index := -1
var _consequence_outcomes: Array[Dictionary] = []
var _deferred_choice: Dictionary = {}
var _previewing_consequence := false
## Reports the standalone action-token sticker to the local board controller.
## Read by GuerraBoard when emitting effect_completed; it never changes payment itself.
var action_free: bool:
	get:
		return definition != null and definition.is_action_free()

## Binds a reusable definition to one activation; callers retain it across UI pauses.
func _init(effect: Effect, source_ref: TargetRef, trigger: EffectEvent = null) -> void:
	definition = effect
	source = source_ref
	triggering_event = trigger

## Validates the definition and event, then previews a player target before payment when requested.
## Called by Effect.eval() or Board.select_effect(); phrase_started lets the board
## attach its chooser before begin() emits the first selection update.
## A paid cost is retained if the later consequence fails or is cancelled.
func start() -> void:
	if status != Status.IDLE: return
	if definition == null or source == null or not source.valid():
		_end(false, "A valid effect and source are required.")
		return
	if definition.cost != null and not (definition.cost is Effect.CostPhrase or definition.cost is Effect.CostBundle):
		_end(false, "Unsupported cost definition.")
		return
	for phrase in [definition.cost, definition.event]:
		if phrase == null: continue
		var check: String = phrase.validate()
		if not check.is_empty():
			_end(false, check)
			return
	if definition.consequence is Effect.ConsequenceSequence:
		var sequence_error := (definition.consequence as Effect.ConsequenceSequence).validate()
		if not sequence_error.is_empty():
			_end(false, sequence_error)
			return
	elif definition.consequence != null:
		if not definition.consequence is Effect.ConsequencePhrase:
			_end(false, "Consequence must be a phrase or consequence sequence.")
			return
		var consequence_error := (definition.consequence as Effect.ConsequencePhrase).validate()
		if not consequence_error.is_empty():
			_end(false, consequence_error)
			return
	if definition.event != null and not captured_trigger:
		var event_ctx := RuleContext.new(source, triggering_event)
		if not definition.event.matches(event_ctx, triggering_event):
			_end(false, "The triggering event does not match.")
			return
	var ctx := RuleContext.new(source, triggering_event)
	if not captured_trigger and definition.condition != null:
		if not definition.condition.test(ctx) or not ctx.error.is_empty():
			_end(false, ctx.error)
			return
	var optional := definition.policy == Effect.Policy.OPTIONAL or (captured_trigger and definition.policy == Effect.Policy.DEFAULT and definition.cost != null)
	if optional:
		status = Status.CONFIRMING
		confirmation_requested.emit()
	else: _begin_activation_flow()

## Accepts an optional activation before any payment; the Board confirmation button calls this.
## Online confirmations wait for host acceptance before changing execution state.
func confirm(accepted: bool) -> void:
	if NetworkSession.routes_input():
		NetworkSession.request_intent({"kind": "confirm_effect", "accepted": accepted})
		return
	if status != Status.CONFIRMING: return
	if accepted: _begin_activation_flow()
	else:
		status = Status.CANCELLED
		finished.emit(false)

## Starts a single cost or collects bundle choices without mutation.
## start/confirm call this only after validation and acceptance.
func _begin_payment() -> void:
	if definition.cost is Effect.CostBundle:
		_cost_index = 0
		_cost_choices.clear()
		_begin(definition.cost.phrases[0], Status.COST)
	elif definition.cost != null: _begin(definition.cost, Status.COST)
	else: begin_consequences()

## Starts one suspended UI phrase and binds its completion back to this runner.
## EffectExecution.start() and _on_phrase_finished() call this via phrase_started.
func _begin(phrase: Effect.Phrase, phase: Status) -> void:
	status = phase
	current = PhraseExecution.new()
	current.selection_only = (phase == Status.COST and definition.cost is Effect.CostBundle) or _previewing_consequence
	current.finished.connect(_on_phrase_finished)
	phrase_started.emit(current)
	current.begin(phrase, self)
	if phase == Status.COST and defer_cost_until_target and definition.cost is Effect.CostPhrase \
			and definition.cost.verb.name == &"self_stun" and current.status == PhraseExecution.Status.TARGET \
			and current.candidates.size() == 1:
		current.choose(current.candidates[0])
	elif phase == Status.CONSEQUENCE and not _deferred_choice.is_empty():
		_apply_deferred_choice()

## Previews one CHOOSE_ONE consequence before a player's action cost, otherwise follows normal payment order.
## start() and confirm() call this after definition checks or optional acceptance.
func _begin_activation_flow() -> void:
	if defer_cost_until_target and definition.cost != null \
			and definition.consequence is Effect.ConsequencePhrase \
			and definition.consequence.target_mode == Effect.Phrase.TargetMode.CHOOSE_ONE:
		_previewing_consequence = true
		_begin(definition.consequence, Status.CONSEQUENCE)
	else:
		_begin_payment()

## Replays the validated preview target after payment, checking its identity against current Match state.
## _begin() calls this after the actual consequence phrase regenerates legal candidates.
func _apply_deferred_choice() -> void:
	var chosen_subject: TargetRef = _deferred_choice.get("subject")
	var chosen_targets: Array = _deferred_choice.get("targets", [])
	_deferred_choice.clear()
	if current.status == PhraseExecution.Status.SUBJECT and chosen_subject != null:
		current.choose(chosen_subject)
	if current.status == PhraseExecution.Status.TARGET and chosen_targets.size() == 1:
		current.choose(chosen_targets[0])

## Starts a single consequence or the first step of an ordered sequence.
## Called after a paid cost or a matching event with no cost.
func begin_consequences() -> void:
	if definition.consequence == null:
		_end(true)
	elif definition.consequence is Effect.ConsequenceSequence:
		_consequence_index = 0
		_consequence_outcomes.clear()
		_begin((definition.consequence as Effect.ConsequenceSequence).phrases[0], Status.CONSEQUENCE)
	else:
		_begin(definition.consequence as Effect.ConsequencePhrase, Status.CONSEQUENCE)

## Records a completed phrase, preserves sequence progress, and starts the next step.
## PhraseExecution.finished is connected in _begin(); a failure ends the activation.
## Unpaid bundle identities/hex snapshots live in cost_choice_N; successful commit alone creates paid cost_N amounts and Summoner destination anchors.
func _on_phrase_finished(success: bool) -> void:
	var phase := status
	if success and phase == Status.CONSEQUENCE and _previewing_consequence:
		_deferred_choice = {"subject": current.subject, "targets": current.targets.duplicate()}
		_previewing_consequence = false
		_begin_payment()
		return
	var phrase_result := {
		"subject": current.subject, "targets": current.targets.duplicate(),
		"outcomes": current.outcomes.duplicate(true), "amount": current.chosen_amount, "target_hexes": current.target_hexes.duplicate(), "success": success}
	results["cost" if phase == Status.COST else "consequence"] = phrase_result
	if not success:
		var was_cancelled := current.status == PhraseExecution.Status.CANCELLED
		error = current.error
		status = Status.CANCELLED if was_cancelled else Status.FAILED
		finished.emit(false)
		return
	if phase == Status.COST:
		if definition.cost is Effect.CostBundle:
			results["cost_choice_%d" % _cost_index] = phrase_result
			_cost_choices.append(current)
			_cost_index += 1
			if _cost_index < definition.cost.phrases.size():
				_begin(definition.cost.phrases[_cost_index], Status.COST)
				return
			var payment_error := CostPayment.commit(_cost_choices)
			if not payment_error.is_empty():
				results["cost"] = {"success": false, "targets": [], "outcomes": []}
				_end(false, payment_error)
				return
			_record_paid_bundle()
		cost_paid = true
		if managed: Match.rules_runner.after_cost(self)
		else: begin_consequences()
	elif definition.consequence is Effect.ConsequenceSequence:
		var sequence := definition.consequence as Effect.ConsequenceSequence
		_consequence_outcomes.append(phrase_result.duplicate(true))
		results["step_%d" % _consequence_index] = phrase_result
		_consequence_index += 1
		if _consequence_index < sequence.phrases.size():
			_begin(sequence.phrases[_consequence_index], Status.CONSEQUENCE)
		else:
			results["consequence"] = {
				"subject": _consequence_outcomes.back().subject,
				"targets": _all_sequence_targets(),
				"outcomes": _all_sequence_outcomes(), "success": true}
			_end(true)
	else:
		_end(true)

## Records paid identities, historical hexes and numeric amounts after atomic commit; RuleBinding and RuleNumber read named cost_N results.
## _on_phrase_finished calls this for CostBundle; selection-only previews never count as payments.
func _record_paid_bundle() -> void:
	var paid_targets: Array[TargetRef] = []
	var paid_outcomes: Array[Dictionary] = []
	for index in _cost_choices.size():
		var choice := _cost_choices[index]
		var result := {"subject": choice.subject, "targets": choice.targets.duplicate(), "outcomes": choice.outcomes.duplicate(true), "amount": choice.chosen_amount, "target_hexes": choice.target_hexes.duplicate(), "success": true}
		results["cost_%d" % index] = result
		paid_targets.append_array(choice.targets)
		paid_outcomes.append_array(choice.outcomes)
	results["cost"] = {"subject": _cost_choices[0].subject, "targets": paid_targets, "outcomes": paid_outcomes, "success": true}

## Combines target references from completed sequence steps for the aggregate result.
## _on_phrase_finished() calls this when the final consequence phrase succeeds.
func _all_sequence_targets() -> Array[TargetRef]:
	var result: Array[TargetRef] = []
	for step in _consequence_outcomes: result.append_array(step.targets)
	return result

## Combines per-target outcomes in printed phrase order for the aggregate result.
## _on_phrase_finished() calls this when the final consequence phrase succeeds.
func _all_sequence_outcomes() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for step in _consequence_outcomes: result.append_array(step.outcomes)
	return result

## Cancels the current pending phrase; completed costs are not refunded.
## Called by the board's cancel input and propagated through PhraseExecution.
## Online external cancellation is replicated once, including its existing cost/no-refund behavior.
func cancel() -> void:
	if NetworkSession.routes_input():
		NetworkSession.request_intent({"kind": "cancel_effect"})
		return
	if not can_cancel(): return
	if status == Status.CONFIRMING:
		confirm(false)
	elif current != null: current.cancel()

## Prevents skipping mandatory triggered choices; optional/player executions retain cancellation.
## Board and PhraseExecution consult this before accepting Escape/cancel.
func can_cancel() -> bool:
	if not managed or not captured_trigger: return true
	if current != null and current.phrase != null and current.phrase.optional: return true
	return definition.policy == Effect.Policy.OPTIONAL or (definition.policy == Effect.Policy.DEFAULT and definition.cost != null)

## Finishes one activation once; the runner releases its captured bundle followups.
func _end(success: bool, message: String = "") -> void:
	error = message
	status = Status.SUCCEEDED if success else Status.FAILED
	finished.emit(success)
