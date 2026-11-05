class_name PhraseExecution
extends RuleContext

## Execution-owned pre-commit positions let Summoner retain a returned cost recipient's former hex without moving ordinary references.
var target_hexes: Dictionary = {}

signal changed
signal finished(success: bool)
enum Status { IDLE, CONFIRMING, SUBJECT, TARGET, COMMITTING, SUCCEEDED, FAILED, CANCELLED, AMOUNT }

var phrase: Effect.Phrase
var targets: Array[TargetRef] = []
var candidates: Array[TargetRef] = []
var selection_only := false
var outcomes: Array[Dictionary] = []
var status := Status.IDLE
var _parent: WeakRef
var amount_max := 0
var effect_execution: EffectExecution:
	get:
		return _parent.get_ref() if _parent != null else null

## Binds one phrase to its parent activation and presents optional confirmation or choices.
## EffectExecution._begin() calls this after the board attaches to phrase_started.
## Candidate generation is read-only; the verb mutates state only at commit.
func begin(definition: Effect.Phrase, parent: EffectExecution) -> void:
	if status != Status.IDLE: return
	phrase = definition
	if phrase == null or parent == null or parent.source == null or not parent.source.valid():
		_fail("A valid phrase and source are required.")
		return
	_parent = weakref(parent)
	source = parent.source
	triggering_event = parent.triggering_event
	completed_results = parent.results
	preview_numbers = selection_only
	error = phrase.validate(self)
	if not error.is_empty():
		_fail(error)
		return
	if phrase.optional:
		status = Status.CONFIRMING
		changed.emit()
	else:
		_refresh()

## Accepts or skips an optional phrase; called by the board's confirmation button.
## Skipping cancels this phrase without executing its verb.
## Online board input waits for host confirmation; replay enters with NetworkSession.applying.
func confirm(accepted: bool) -> void:
	if NetworkSession.routes_input():
		NetworkSession.request_intent({"kind": "confirm_phrase", "accepted": accepted})
		return
	if status != Status.CONFIRMING: return
	if accepted: _refresh()
	else: cancel()

## Builds legal actors through TargetResolver for refresh/commit; no action or payment runs.
func _resolve_subjects() -> Array[TargetRef]:
	var result := TargetResolver.resolve(phrase.subject, phrase.verb.subject_kind, self)
	error = result.error
	return result.candidates.filter(phrase.verb.accepts_subject)

## Builds legal recipients for the chosen actor; refresh/commit use this read-only query.
## Event numbers and ability-specific upgrades bind into an ephemeral verb, leaving the reusable phrase untouched.
func _resolve_targets() -> Array[TargetRef]:
	query_verb = phrase.verb
	var result := TargetResolver.resolve(phrase.target, phrase.verb.target_kind, self)
	error = result.error
	var bound := phrase.verb.bound_to(self)
	return result.candidates.filter(func(ref: TargetRef) -> bool: return bound.can_apply(subject, ref))

## Offers a subject/target choice or commits ALL; begin and accepted UI choices call this.
func _refresh() -> void:
	if subject == null:
		candidates = _resolve_subjects()
		if not error.is_empty() or candidates.is_empty():
			_fail(error)
			return
		if candidates.size() == 1: subject = candidates[0]
		else:
			status = Status.SUBJECT
			changed.emit()
			return
	candidates = _resolve_targets()
	if not error.is_empty() or candidates.is_empty():
		_fail(error)
		return
	status = Status.TARGET
	if phrase.target_mode == Effect.Phrase.TargetMode.ALL: _commit()
	else: changed.emit()

## Commits a currently offered subject or target after checking it remains legal.
## Board cell/menu handlers call this; false means it was not committed successfully.
## Online choices carry only stable target identity and wait for the host to recheck legality.
func choose(candidate: TargetRef) -> bool:
	if NetworkSession.routes_input(): return NetworkSession.request_intent({"kind": "choose", "ref": NetworkSession.encode_ref(candidate)})
	if status not in [Status.SUBJECT, Status.TARGET]: return false
	if not TargetResolver.contains(candidates, candidate): return false
	if status == Status.SUBJECT:
		var current := _resolve_subjects()
		if not error.is_empty() or not TargetResolver.contains(current, candidate):
			_fail(error)
			return false
		subject = candidate
		_refresh()
		return status != Status.FAILED
	targets = [candidate]
	return _commit()

## Rechecks the chosen actor and target against current Match; batch/cost preflight calls before mutation.
func _still_legal(target: TargetRef) -> bool:
	if effect_execution == null or not effect_execution.source.valid(): return false
	var actors := _resolve_subjects()
	if not error.is_empty() or not TargetResolver.contains(actors, subject): return false
	var current := _resolve_targets()
	return error.is_empty() and TargetResolver.contains(current, target)

## Numeric picker submits one positive integer for the retained counter identity; invalid/outdated amounts do not pay anything.
## Board's bounded amount control calls this, then _commit regenerates both candidates and the actual live balance.
func choose_amount(value: int) -> bool:
	# Online numeric choices use the same host-authorized counter payment path.
	if NetworkSession.routes_input(): return NetworkSession.request_intent({"kind": "amount", "amount": value})
	if status != Status.AMOUNT or value < 1 or value > amount_max: return false
	chosen_amount = value
	status = Status.TARGET
	return _commit()

## Freezes/revalidates identities, asks X for a variable decrement, then mutates once or records a cost preview; choose/ALL call this.
## Numeric choices and historical target hexes belong to this execution; cost previews retain them without paying or moving the recipient.
func _commit() -> bool:
	if status != Status.TARGET: return false
	if effect_execution == null or not effect_execution.source.valid():
		_fail("The effect source is no longer available.")
		return false
	var actors := _resolve_subjects()
	if not error.is_empty() or not TargetResolver.contains(actors, subject):
		_fail(error)
		return false
	var current := _resolve_targets()
	if not error.is_empty() or current.is_empty():
		_fail(error)
		return false
	if phrase.target_mode == Effect.Phrase.TargetMode.ALL: targets = current.duplicate()
	elif targets.size() != 1 or not TargetResolver.contains(current, targets[0]):
		_fail("The chosen target is no longer legal.")
		return false
	if phrase is Effect.CostPhrase and (targets.size() != 1 or not phrase.verb.atomic_cost):
		_fail("Costs currently require one target and an atomic cost verb.")
		return false
	if phrase.verb.name in [&"decrement", &"choose_counter"] and not phrase.verb.user_params.is_empty() \
			and phrase.verb.user_params[0] is RuleNumber and phrase.verb.user_params[0].basis == RuleNumber.SourceKind.CHOICE \
			and chosen_amount < 0:
		amount_max = Match.get_property(targets[0]).value
		if phrase.verb.amount_limit > 0: amount_max = mini(amount_max, phrase.verb.amount_limit)
		status = Status.AMOUNT
		candidates = []
		changed.emit()
		return true
	status = Status.COMMITTING
	target_hexes.clear()
	for target in targets:
		if target.kind == TargetRef.Kind.UNIT and target.has_hex(): target_hexes[target.id] = target.hex_id()
	candidates = []
	changed.emit()
	if selection_only:
		outcomes = [{"target": targets[0], "success": true}]
	else:
		Match.rules_runner.begin_boundary()
		outcomes = phrase.verb.bound_to(self).execute_many(subject, targets.duplicate(), _still_legal)
		Match.rules_runner.end_boundary()
	var success := false
	for outcome in outcomes: success = success or outcome.success
	status = Status.SUCCEEDED if success else Status.FAILED
	changed.emit()
	finished.emit(success)
	return success

## Cancels a pending confirmation or choice; COMMITTING and terminal states cannot be cancelled.
## Board cancel input and parent effect cancellation call this method.
## Online external cancellation is an intent; confirmed parent cancellation stays within its accepted execution.
func cancel() -> void:
	if NetworkSession.routes_input():
		NetworkSession.request_intent({"kind": "cancel_phrase"})
		return
	if effect_execution != null and not effect_execution.can_cancel() and not (phrase != null and phrase.optional): return
	if status in [Status.COMMITTING, Status.SUCCEEDED, Status.FAILED, Status.CANCELLED]: return
	status = Status.CANCELLED
	candidates = []
	changed.emit()
	finished.emit(false)

## Ends the pending phrase with its validation/legality error and notifies EffectExecution once.
func _fail(message: String) -> void:
	error = message
	status = Status.FAILED
	candidates = []
	changed.emit()
	finished.emit(false)
