class_name Effect
extends RefCounted

var cost: RefCounted
enum Policy { DEFAULT, OPTIONAL, MANDATORY }
var policy := Policy.DEFAULT
var condition: Condition
## Stable printed key for a trigger that can be captured once per unit per turn.
var once_per_turn_key := ""
var event: EventPhrase
var consequence: RefCounted
## True for engine-supplied rules that are executable but omitted from printed board summaries.
var implicit := false
## Optional A/S/AS/nS presentation marker; costs remain defined and paid through cost objects, never this label.
var cost_label: StringName

## Combines optional cost/event with one consequence phrase or an ordered consequence sequence.
## CardCatalogue and Collection factories construct definitions; EffectExecution.start() validates them.
func _init(effect_cost: RefCounted = null, effect_event: EventPhrase = null, effect_consequence: RefCounted = null) -> void:
	cost = effect_cost
	event = effect_event
	consequence = effect_consequence

## Composes one reusable event pattern with its guard, optional cost, policy, and consequence.
## Card factories use this instead of adding card-specific signal callbacks.
static func on_event(pattern: EventPhrase, effect_consequence: RefCounted,
		guard: Condition = null, effect_cost: RefCounted = null,
		activation_policy: Policy = Policy.DEFAULT) -> Effect:
	var result := Effect.new(effect_cost, pattern, effect_consequence)
	result.condition = guard
	result.policy = activation_policy
	return result


## Starts one activation with this definition and the supplied source (SELF).
## Returns its live execution; costs, choices, and consequences are resolved there.
## UnitInfo.eval() and direct UI callers must still account for the player's action token.
func eval(source: TargetRef, trigger: EffectEvent = null) -> EffectExecution:
	var execution := EffectExecution.new(self, source, trigger)
	execution.start()
	return execution

## Reports standalone token policy for the whole effect; triggers never spend an implicit token.
## RulesRunner and EffectExecution use this rather than inspecting only one UI phrase.
func is_action_free() -> bool:
	if consequence is ConsequencePhrase: return consequence.action_free
	if consequence is ConsequenceSequence:
		for phrase in consequence.phrases:
			if not phrase.action_free: return false
		return not consequence.phrases.is_empty()
	return false

## Declares an explicit atomic bundle of supported, individually chosen payments.
## EffectExecution collects every choice before CostPayment preflights and commits once.
class CostBundle extends RefCounted:
	var phrases: Array[CostPhrase] = []
	## Copies reusable payment definitions; no chosen targets live on the bundle.
	func _init(steps: Array[CostPhrase]) -> void:
		phrases = steps.duplicate()
	## Rejects unsupported costs before selection; Return, Disable and deployments are accepted because CostPayment preflights their ledgers/departures.
	func validate() -> String:
		if phrases.is_empty(): return "A cost bundle must contain a payment."
		for phrase in phrases:
			if phrase == null: return "A cost bundle contains an empty payment."
			var error := phrase.validate()
			if not error.is_empty(): return error
			if phrase.optional or phrase.verb.name not in [&"self_stun", &"decrement", &"deactivate", &"pay_life", &"next_turn_actions", &"choose_counter_unit", &"sacrifice", &"disable", &"return_to_hand", &"spend_deployment"]:
				return "Cost bundles support only mandatory preflighted activity, counter, life, departure, deployment and next-turn-action payments."
		return ""

class Verb extends RefCounted:
	var name: StringName
	var function: Callable
	var legality: Callable
	var user_params: Array
	var subject_kind: TargetRef.Kind
	var target_kind: TargetRef.Kind
	var atomic_cost := false
	## Positive bound for execution-owned numeric choices; zero leaves the existing resource-balance bound unchanged.
	var amount_limit := 0
	var definition_origin: Verb

	func _init(action_name: StringName, action: Callable, check: Callable,
			subj_kind: TargetRef.Kind, trgt_kind: TargetRef.Kind, params: Array = []) -> void:
		name = action_name
		function = action
		legality = check
		subject_kind = subj_kind
		target_kind = trgt_kind
		user_params = params.duplicate()

	## Copies the named action definition and its parameter array before phrase-specific sticker application.
	## Phrase.add_sticker() uses this so one card's sticker cannot change another phrase's Verb.
	func copy() -> Verb:
		var result := Verb.new(name, function, legality, subject_kind, target_kind, user_params)
		result.atomic_cost = atomic_cost
		result.amount_limit = amount_limit
		return result

	## PhraseExecution/availability bind event numbers, completed counter choices and selected-ability upgrades into an ephemeral parameter copy.
	## Definition parameters remain unchanged; the recipient's own upgrade records apply only to this exact authored ability.
	func bound_to(ctx: RuleContext) -> Verb:
		var result := copy()
		result.definition_origin = definition_origin if definition_origin != null else self
		for index in result.user_params.size():
			if result.user_params[index] is RuleNumber or result.user_params[index] is RuleBinding:
				result.user_params[index] = result.user_params[index].evaluate(ctx)
		if ctx != null and ctx.subject != null and ctx.subject.kind == TargetRef.Kind.UNIT:
			var unit := Match.get_unit(ctx.subject.id)
			if unit != null:
				var bonus := unit.ability_bonus(result.definition_origin)
				if not result.user_params.is_empty() and typeof(result.user_params[0]) in [TYPE_INT, TYPE_FLOAT]: result.user_params[0] += bonus.x
				if name not in [&"fire", &"move", &"fly", &"shield", &"mshield"] and result.user_params.size() > 1 and typeof(result.user_params[1]) in [TYPE_INT, TYPE_FLOAT]: result.user_params[1] += bonus.y
		return result

	func accepts_subject(subject: TargetRef) -> bool:
		return subject != null and subject.kind == subject_kind and subject.valid()

	## Enforces bounded numeric choices before the named legality check; preview and commit use the same bound.
	func can_apply(subject: TargetRef, target: TargetRef) -> bool:
		if not accepts_subject(subject) or target == null or target.kind != target_kind or not target.valid(): return false
		if amount_limit > 0 and not user_params.is_empty() and int(user_params[0]) > amount_limit: return false
		return bool(legality.callv([subject, target] + user_params)) if legality.is_valid() else true

	func execute_many(subject: TargetRef, targets: Array[TargetRef], still_legal: Callable = Callable()) -> Array[Dictionary]:
		var outcomes: Array[Dictionary] = []
		for target in targets:
			var allowed := can_apply(subject, target)
			if allowed and still_legal.is_valid(): allowed = bool(still_legal.call(target))
			var success := bool(function.callv([subject, target] + user_params)) if allowed else false
			outcomes.append({"target": target, "success": success})
		return outcomes

	## Applies a supported typed sticker to this Verb's parameter copy.
	## Phrase.add_sticker() calls it only after copying the Verb; shared definitions remain unchanged.
	func apply_sticker(sticker_kind: ActionSticker.Kind) -> bool:
		var parameter_index := -1
		var value := true
		match sticker_kind:
			ActionSticker.Kind.INSTANT:
				match name:
					&"fire": parameter_index = 1
					&"bow", &"cannon": parameter_index = 2
					_: return false
			ActionSticker.Kind.PIERCE:
				match name:
					&"fire": parameter_index = 2
					&"bow", &"cannon": parameter_index = 3
					&"bomb_throw": parameter_index = 2
					_: return false
			ActionSticker.Kind.ACTION_FREE:
				match name:
					&"fire": parameter_index = 3
					&"bow", &"cannon": parameter_index = 4
					&"bomb_throw": parameter_index = 3
					&"defuse_bomb", &"move", &"fly", &"mend", &"stun", &"gore": parameter_index = 1 if name == &"defuse_bomb" else (2 if name in [&"mend", &"stun", &"gore"] else 1)
					&"push", &"pull", &"push_bomb", &"pull_bomb": parameter_index = 3
					_: return true # The Phrase still records A for verbs whose token policy is external.
			ActionSticker.Kind.TIRELESS:
				return true # Tireless changes the enclosing Effect's default cost, not the Verb.
		if parameter_index < 0 or parameter_index >= user_params.size(): return false
		user_params[parameter_index] = value
		return true

class Phrase extends RefCounted:
	enum TargetMode { CHOOSE_ONE, ALL }
	## Per-operation stickers; Tireless omits only default activity cost, Action-free only token cost.
	var tireless := false
	var action_free := false
	## Typed P/F/T/A definitions for authoring and card inspection; the Verb remains reusable.
	var stickers: Array[ActionSticker] = []
	var subject: Selector
	var verb: Verb
	var target: Selector
	var target_mode: TargetMode
	var optional := false

	func _init(subj: Selector, action: Verb, trgt: Selector, mode: TargetMode = TargetMode.CHOOSE_ONE) -> void:
		subject = subj
		verb = action
		target = trgt
		target_mode = mode

	## Adds one sticker definition once and updates the existing execution fields for compatibility.
	## Collection factories call this during card construction; it does not mutate the Verb.
	func add_sticker(sticker: ActionSticker) -> void:
		if sticker == null or verb == null or has_sticker(sticker.kind): return
		if sticker.kind in [ActionSticker.Kind.INSTANT, ActionSticker.Kind.PIERCE, ActionSticker.Kind.ACTION_FREE]:
			var configured_verb := verb.copy()
			if not configured_verb.apply_sticker(sticker.kind) \
					and sticker.kind in [ActionSticker.Kind.INSTANT, ActionSticker.Kind.PIERCE]: return
			verb = configured_verb
		stickers.append(sticker)
		match sticker.kind:
			ActionSticker.Kind.TIRELESS: tireless = true
			ActionSticker.Kind.ACTION_FREE: action_free = true

	## Checks this action's typed sticker list; card UI and action factories use it read-only.
	func has_sticker(sticker_kind: ActionSticker.Kind) -> bool:
		for sticker in stickers:
			if sticker != null and sticker.kind == sticker_kind: return true
		return false

	## Checks this definition and domain constraints before selection/payment; returns an error or empty string.
	func validate(ctx: RuleContext = null) -> String:
		if subject == null or target == null or verb == null: return "Phrase requires a subject, verb, and target."
		if not verb.function.is_valid(): return "Verb requires an action."
		for pair in [[subject, verb.subject_kind], [target, verb.target_kind]]:
			var selector: Selector = pair[0]
			var error := selector.validate(ctx)
			if not error.is_empty(): return error
			var native_kind := selector.output_kind(ctx)
			if native_kind >= 0 and not TargetResolver.compatible(native_kind, pair[1]):
				return "Phrase kind mismatch: use an explicit projection."
		return ""

class CostPhrase extends Phrase:
	## Checks this definition and domain constraints before selection/payment; returns an error or empty string.
	func validate(ctx: RuleContext = null) -> String:
		var error := super.validate(ctx)
		if not error.is_empty(): return error
		if target_mode != TargetMode.CHOOSE_ONE or not verb.atomic_cost:
			return "Costs require CHOOSE_ONE and an atomic cost verb."
		return ""

class EventPhrase extends Phrase:
	var stage: StringName = &"resolved"
	var observed_action: StringName = &""
	var observed_actions: Array[StringName] = []
	var matches_any_action := false
	var observes_family := false
	var detail_constraints: Dictionary = {}
	## Explicit cancellation observers (such as Flee) opt in; ordinary attack triggers still require successful occurrences.
	var observes_cancelled := false
	var observed_subject_kind: TargetRef.Kind = TargetRef.Kind.UNIT
	var observed_target_kind: TargetRef.Kind = TargetRef.Kind.UNIT
	const ACTION_FAMILIES := {
		&"atk": [&"fire", &"cannon", &"gore", &"bash", &"bow"],
		&"patk": [&"gore", &"bash", &"bow"],
		&"ratk": [&"fire", &"cannon"],
	}

	## Creates a pattern for one exact event action without inventing an executable Verb.
	## Card factories pass selectors for the captured subject/target and may constrain
	## copied event details; EffectExecution validates and matches before consequences.
	static func observe(action_name: StringName, subj: Selector, trgt: Selector,
			subj_kind: TargetRef.Kind = TargetRef.Kind.UNIT,
			trgt_kind: TargetRef.Kind = TargetRef.Kind.UNIT,
			event_stage: StringName = &"resolved",
			details: Dictionary = {}) -> EventPhrase:
		var result := EventPhrase.new(null, null, null)
		result.subject = subj
		result.target = trgt
		result.observed_action = action_name
		result.observed_actions = [action_name]
		result.observed_subject_kind = subj_kind
		result.observed_target_kind = trgt_kind
		result.stage = event_stage
		result.detail_constraints = details.duplicate(true)
		return result

	## Creates a pattern for any listed action, or any action when the list is empty.
	## Use this for shared card rules; event family and detail matching remain centralized.
	static func observe_any(actions: Array[StringName], subj: Selector, trgt: Selector,
			subj_kind: TargetRef.Kind = TargetRef.Kind.UNIT,
			trgt_kind: TargetRef.Kind = TargetRef.Kind.UNIT,
			event_stage: StringName = &"resolved",
			details: Dictionary = {}) -> EventPhrase:
		var result := observe(&"", subj, trgt, subj_kind, trgt_kind, event_stage, details)
		result.observed_actions = actions.duplicate()
		result.matches_any_action = actions.is_empty()
		return result

	## Creates a pattern for one named Guerra attack family: atk, patk, or ratk.
	## EventPhrase.matches() expands the family; it never infers membership from damage type.
	static func observe_family(family: StringName, subj: Selector, trgt: Selector,
			subj_kind: TargetRef.Kind = TargetRef.Kind.UNIT,
			trgt_kind: TargetRef.Kind = TargetRef.Kind.UNIT,
			event_stage: StringName = &"resolved",
			details: Dictionary = {}) -> EventPhrase:
		var result := observe(family, subj, trgt, subj_kind, trgt_kind, event_stage, details)
		result.observes_family = true
		return result

	## Validates the action filter, stage, selectors, domains, and detail constraints.
	## EffectExecution.start() runs this before paying costs or applying consequences.
	func validate(ctx: RuleContext = null) -> String:
		if observed_action.is_empty() and observed_actions.is_empty() and not matches_any_action:
			return super.validate(ctx)
		if subject == null or target == null: return "Event pattern requires subject and target selectors."
		if not matches_any_action and observed_actions.is_empty():
			return "Event pattern requires at least one action name."
		if stage not in [&"target", &"resolved"]: return "Event pattern stage must be target or resolved."
		if observes_family and not ACTION_FAMILIES.has(observed_action):
			return "Unsupported event family: %s." % observed_action
		for action_name in observed_actions:
			if action_name.is_empty(): return "Event pattern action names cannot be empty."
		if not observed_action.is_empty() and observed_action not in ACTION_FAMILIES and observed_action not in observed_actions:
			return "Event pattern action name cannot be empty."
		for pair in [[subject, observed_subject_kind], [target, observed_target_kind]]:
			var selector: Selector = pair[0]
			var error := selector.validate(ctx)
			if not error.is_empty(): return error
			var native_kind := selector.output_kind(ctx)
			if native_kind >= 0 and not TargetResolver.compatible(native_kind, pair[1]):
				return "Event pattern kind mismatch: use an explicit projection."
		return ""

	## Matches captured action/stage/details and participants; cancellation observers opt in explicitly for Flee-style rules.
	## Does not run the verb or check current action legality; an event may already have deactivated or moved its participants.
	func matches(ctx: RuleContext, trigger: EffectEvent) -> bool:
		var observed_pattern := not observed_action.is_empty() or not observed_actions.is_empty() or matches_any_action
		var action_name := observed_action if observed_pattern else (verb.name if verb != null else &"")
		var subject_kind := observed_subject_kind if observed_pattern else verb.subject_kind
		var target_kind := observed_target_kind if observed_pattern else verb.target_kind
		if trigger == null or trigger.stage != stage: return false
		if not trigger.succeeded() and not (observes_cancelled and bool(trigger.data.get("cancelled", false))): return false
		if not matches_any_action:
			var accepted := observed_actions
			if accepted.is_empty(): accepted = [action_name]
			var family := action_name if ACTION_FAMILIES.has(action_name) else &""
			if not family.is_empty():
				if trigger.action not in ACTION_FAMILIES[family]: return false
			elif trigger.action not in accepted: return false
		var event_details := trigger.data
		for key in detail_constraints:
			var field_name := String(key)
			if not event_details.has(key) and not event_details.has(field_name): return false
			var actual: Variant = event_details.get(key, event_details.get(field_name))
			if actual != detail_constraints[key]: return false
		var actors := TargetResolver.resolve(subject, subject_kind, ctx)
		if not actors.error.is_empty() or not TargetResolver.contains(actors.candidates, trigger.subject): return false
		ctx.subject = trigger.subject
		var targets := TargetResolver.resolve(target, target_kind, ctx)
		return targets.error.is_empty() and TargetResolver.contains(targets.candidates, trigger.target)

class ConsequencePhrase extends Phrase:
	pass

class ConsequenceSequence extends RefCounted:
	## Ordered consequence phrases. A sequence stops at its first failed/cancelled phrase.
	var phrases: Array[ConsequencePhrase] = []

	## Copies the ordered definitions so callers cannot mutate execution order accidentally.
	## Effect authors pass the result as Effect's consequence; EffectExecution advances it.
	func _init(steps: Array[ConsequencePhrase]) -> void:
		phrases = steps.duplicate()

	## Validates every step before any cost or consequence can mutate Match.
	## EffectExecution.start() calls this during activation preflight.
	func validate() -> String:
		if phrases.is_empty(): return "A consequence sequence requires at least one phrase."
		for phrase in phrases:
			if phrase == null: return "A consequence sequence cannot contain an empty phrase."
			var error := phrase.validate()
			if not error.is_empty(): return error
		return ""
