## Presentation-only descriptions of reusable rules; never resolves selectors or starts executions.
## LocalMatchController uses unit_lines() for board, Bash-side, and tray hover cards.
class_name EffectText
extends RefCounted

const ACTIONS := {
	&"move": "🥾", &"fly": "🪽", &"bow": "🏹", &"fire": "🔥",
	&"cannon": "🧨", &"gore": "🐏", &"shield": "🛡️",
	&"mshield": "🛡️", &"push": "🫸", &"pull": "🫷",
	&"push_bomb": "🫸💣", &"pull_bomb": "🫷💣", &"stun": "🚫",
	&"mend": "❤️", &"revive": "revive", &"bash": "⚔️",
	&"bomb_throw": "💣", &"bomb_defuse": "defuse 💣",
	&"bomb_light": "light 💣", &"damage": "damage", &"hit": "hit", &"wound": "wound",
	&"atk": "an attack", &"patk": "a physical attack", &"ratk": "a ranged attack",
}

## HexCell's compact action labels and LocalMatchController's menu labels read authored range through projections.
## Returns the selector's printed distance/range, or -1 when unavailable; never resolves targets or applies upgrades.
## Intersections retain their left spatial selector, so Upgrade's additional eligibility filters do not hide its radius.
static func selector_range(selector: Selector) -> int:
	if selector is DistanceSelector: return (selector as DistanceSelector).distance
	if selector is Selectors.ProjectionSelector:
		return selector_range((selector as Selectors.ProjectionSelector).input)
	if selector is Selectors.BowTargets:
		return (selector as Selectors.BowTargets).printed_range
	if selector is Selectors.Group and not selector.union: return selector_range(selector.left)
	return -1

## Returns compact BBCode actions and concise structured triggers/states/auras/passives for hover cards.
## Hover cards show dynamic adventurer formulas and recipient-owned next-Fire stickers alongside authored rules.
## Optional presentation-only fired definitions highlight their exact trigger lines without changing shared effects.
## Resource-conversion actions with bundled payments follow triggers, so Warrior's Soul gain appears before its Soul spending rule.
static func unit_lines(unit: UnitInfo, highlighted: Array = []) -> PackedStringArray:
	var lines := PackedStringArray()
	var conversions := PackedStringArray()
	if unit == null: return lines
	for effect in unit.effects:
		if effect == null: continue
		var text := describe_effect(effect, unit)
		if effect.implicit: text += " [color=#94a3b8](default)[/color]"
		if effect.cost is Effect.CostBundle and effect.consequence is Effect.ConsequencePhrase and effect.consequence.verb.name == &"grant_deployments":
			conversions.append(text)
		else: lines.append(text)
	for effect in unit.trigger_effects:
		if effect != null:
			var text := describe_effect(effect, unit)
			if highlighted.has(effect): text = "[color=#ffd84a]%s[/color]" % text
			lines.append(text)
	lines.append_array(conversions)
	for state in unit.state_effects:
		if state == null: continue
		if state is AdventurerRules.AdjacentFriends or state is AdventurerRules.MaximumLife:
			lines.append(state.label)
			continue
		if state is StateModifier.DeploymentDifference:
			var difference := state.evaluate(RuleContext.new(TargetRef.unit(unit.iun))).x
			lines.append("+X/[color=#c084fc]+0[/color], X = %s minus %s (%+d)" % [_owner_color("deploy", unit.player), _owner_color("enemy deploy", 3 - unit.player), difference])
			continue
		var text := _modifiers(state.physical, state.magical)
		if state.condition != null: text = "while %s: %s" % [_condition(state.condition, "this unit", unit), text]
		lines.append(text)
	for aura in unit.continuous_effects:
		if aura != null: lines.append(_continuous(aura, unit))
	for prop in unit.props:
		if prop != null and prop.increment == Enum.p_increment.FLAG and prop.value != 0 and String(prop.name).to_lower() != "wild":
			lines.append(_passive_text(prop.name) + ".")
	if unit.control_bonus != 0: lines.append("%+d control." % unit.control_bonus)
	if not unit.next_fire_stickers.is_empty():
		var pending := PackedStringArray()
		for sticker in unit.next_fire_stickers: pending.append("Pierce" if sticker == &"pierce" else "Instant")
		lines.append("Next Fire: " + " and ".join(pending) + ".")
	return lines

## Hover and Copy menus describe deployment and movement restrictions without exposing their internal flag keys.
static func _passive_text(key: StringName) -> String:
	match key:
		&"enemy_control_deploy": return "May deploy in enemy-controlled regions"
		&"must_bash": return "Must Bash when able to Walk into an enemy"
	return _plain(key)

## UnitInfo.effect_options and property-choice menus name one copyable definition without exposing runtime keys or BBCode markup.
## Action, trigger, static and passive choices use the same rule descriptions as hover cards, while printed flags retain their readable name.
static func effect_option_text(option: EffectOption, unit: UnitInfo) -> String:
	var text := ""
	if option.definition is Effect: text = describe_effect(option.definition, unit)
	elif option.definition is StateModifier: text = option.definition.label
	elif option.definition is ContinuousEffect: text = _continuous(option.definition, unit)
	elif option.definition is Prop: text = _passive_text(option.definition.name)
	var image := RegEx.new()
	image.compile("\\[img[^\\]]*\\]([^\\[]+)\\[/img\\]")
	for result in image.search_all(text):
		text = text.replace(result.get_string(), " " + result.get_string(1).get_file().get_basename().replace("-", " ") + " ")
	var tags := RegEx.new()
	tags.compile("\\[[^\\]]*\\]")
	return tags.sub(text, "", true).strip_edges()

## Describes normal actions as hex-style symbols and complex effects as event/guard/cost/consequence clauses.
## Compact numeric actions omit default [AS]; written consequences and conversions show their payment before the colon.
## Captured attack-family guards join Hit/Wound wording directly instead of repeating a separate 'if contact' clause.
## A counter removed from an enemy and awarded to SELF is described as a transfer, retaining its authored resource/activity payment.
## Prior-Stun and region guards fold into their trigger text. Guards that only check required targets are implicit.
static func describe_effect(effect: Effect, unit: UnitInfo = null) -> String:
	if effect == null: return "Missing effect."
	var consequence := _steps(effect.consequence, unit, effect.event == null)
	var result := consequence
	if effect.event == null and effect.consequence is Effect.ConsequencePhrase and effect.consequence.verb.name == &"add_counter" \
			and effect.consequence.verb.user_params[0] is RuleBinding and effect.cost is Effect.CostBundle:
		for payment: Effect.CostPhrase in effect.cost.phrases:
			if payment.verb.name == &"decrement" and payment.target is Selectors.CountersOf:
				return "[lb]%s[rb] transfer one counter from %s to this unit" % [String(effect.cost_label) if not effect.cost_label.is_empty() else "AS", _selector(payment.target.input, unit)]
	if effect.event != null and effect.event.observed_action in [&"move", &"shifted"] and effect.consequence is Effect.ConsequencePhrase \
			and effect.consequence.verb.name == &"grant_modifiers" and effect.event.subject is QuerySelector \
			and effect.event.subject.relative_owner == Enum.YOU and effect.consequence.target is Selectors.Reference \
			and effect.consequence.target.anchor == Selectors.Anchor.EVENT_SUBJECT and effect.condition == null \
			and effect.cost == null and effect.policy != Effect.Policy.OPTIONAL:
		var values: Array = effect.consequence.verb.user_params
		return "friend is shifted: it has %s until enemy End" % _modifiers(values[0], values[1]) if effect.event.observed_action == &"shifted" else "moved friends have %s until End" % _modifiers(values[0], values[1])
	if effect.event == null and effect.consequence is Effect.ConsequenceSequence and effect.consequence.phrases.size() == 2 \
			and effect.consequence.phrases[0].verb.name == &"disable" and effect.consequence.phrases[1].verb.name == &"grant_deployments":
		return _payment_text(effect.cost, unit, effect.cost_label, not effect.is_action_free()) + " " \
			+ _phrase(effect.consequence.phrases[0], unit) + ": " + _phrase(effect.consequence.phrases[1], unit)
	if effect.event != null:
		var optional := effect.policy == Effect.Policy.OPTIONAL or (effect.policy == Effect.Policy.DEFAULT and effect.cost != null)
		var event_text := _event(effect.event, unit)
		if effect.condition is SynergyRules.AlreadyStunned: event_text = "another friend Stuns any stunned unit"
		if effect.condition is AdventurerRules.OwnRegion and effect.event.observed_action == &"gain_region":
			event_text = "enemy gains control of this unit's region"
			consequence = _steps(effect.consequence, unit, true)
		if effect.condition is SynergyRules.AttackKind and effect.event.observed_action in [&"hit", &"wound"]:
			event_text += " with " + _action(effect.condition.family, unit)
		if effect.condition is HeroCatalogue.NearbySacrifice: event_text = "friend is sacrificed within 2"
		if _nonwounding_hit(effect): event_text = event_text.replace(" hits ", " hits without wounding ")
		if effect.event.observed_action == &"life_increase" and effect.condition is Condition.EventPositive:
			var actor := _query(effect.event.subject, unit, true) if effect.event.subject is QuerySelector else _selector(effect.event.subject, unit)
			event_text = "%s %s life increases by X" % [actor, effect.condition.key]
		result = "%s: %s%s" % [event_text, "you may " if optional else "", consequence]
	elif effect.policy == Effect.Policy.OPTIONAL:
		result = "you may " + consequence
	var family_contact := effect.condition is SynergyRules.AttackKind and effect.event != null and effect.event.observed_action in [&"hit", &"wound"]
	var two_bash_choices: bool = effect.condition is AdventurerRules.TwoBashing and effect.consequence is Effect.ConsequenceSequence \
		and effect.consequence.phrases.size() == 2 and effect.consequence.phrases[0].verb.name == &"choose_bashing"
	if effect.condition != null and not effect.cost is Effect.CostBundle and not effect.condition is Condition.EventPositive \
			and not effect.condition is HeroCatalogue.NearbySacrifice and not effect.condition is SynergyRules.AlreadyStunned \
			and not effect.condition is AdventurerRules.OwnRegion and not family_contact and not two_bash_choices \
			and not _nonwounding_hit(effect) and not _required_target_guard(effect.condition, effect.consequence):
		result = "if %s: %s" % [_condition(effect.condition, "this unit", unit), result]
	var is_compact := effect.consequence is Effect.Phrase and not compact_action(effect.consequence, unit).is_empty()
	if effect.cost != null and (effect.event != null or not _default_activity_cost(effect.cost) or effect.is_action_free() or not is_compact):
		var payment := _payment_text(effect.cost, unit, effect.cost_label, effect.event == null and not effect.is_action_free())
		result = payment + ": " + result if effect.event == null else result + "; " + payment
	elif effect.event == null and effect.cost == null and not effect.is_action_free():
		result = "[lb]A[rb]: " + result
	if _uses_paid_sacrifice_life(effect): result += ", X is the target's current life"
	if not effect.once_per_turn_key.is_empty(): result += " (once per turn)"
	return result

## Suppresses only guards that check the same mandatory target selectors already named by the consequence.
static func _required_target_guard(guard: Condition, consequence: RefCounted) -> bool:
	if guard is Condition.All:
		return not guard.conditions.is_empty() and guard.conditions.all(
			func(part: Condition) -> bool: return _required_target_guard(part, consequence))
	if not guard is Condition.Matches or guard.mode != Condition.Matches.Mode.ANY: return false
	var phrases: Array = consequence.phrases if consequence is Effect.ConsequenceSequence else [consequence]
	for phrase in phrases:
		if phrase is Effect.ConsequencePhrase and not phrase.optional and phrase.target == guard.selector: return true
	return false

## Names the source of X when a counter consequence reads the paid amount of a Sacrifice in its bundle.
static func _uses_paid_sacrifice_life(effect: Effect) -> bool:
	if not effect.cost is Effect.CostBundle or not effect.consequence is Effect.ConsequencePhrase: return false
	var verb: Effect.Verb = effect.consequence.verb
	if verb == null or verb.name != &"add_counter" or verb.user_params.size() < 2: return false
	var amount: Variant = verb.user_params[1]
	if not amount is RuleNumber or amount.basis != RuleNumber.SourceKind.PAID_AMOUNT: return false
	for index in effect.cost.phrases.size():
		if amount.result_name == StringName("cost_%d" % index):
			return effect.cost.phrases[index].verb.name == &"sacrifice"
	return false

## Red Mage/Pyromancer use an explicit captured wounded=false guard; presentation joins it to Hit without exposing history field names.
static func _nonwounding_hit(effect: Effect) -> bool:
	return effect.event != null and effect.event.observed_action == &"hit" \
		and effect.condition is Condition.EventFact and effect.condition.key == &"wounded" and effect.condition.expected == false

## Formats independent A (action) and S (self-Stun) payments; legacy C/AC labels migrate to A/AS without changing runtime costs.
## Counter payments name their host; Sacrifice's built-in friendly restriction is implicit in concise radius wording.
static func _payment_text(cost: RefCounted, unit: UnitInfo, label: StringName = &"", consume_action: bool = true) -> String:
	var phrases: Array = cost.phrases if cost is Effect.CostBundle else [cost]
	if phrases.size() == 3 and phrases[0].verb.name == &"choose_counter_unit" \
			and phrases[1].verb.name == &"decrement" and phrases[1].target is Selectors.CountersOf \
			and phrases[2].verb.name == &"self_stun" and phrases[1].verb.user_params[0] is RuleNumber:
		var host: String = _query(phrases[0].target, unit, true) if phrases[0].target is QuerySelector else _selector(phrases[0].target, unit)
		return "[lb]%s[rb] -%s counters on %s" % ["AS" if consume_action else "S", phrases[1].verb.user_params[0].symbol, host]
	var rows := PackedStringArray()
	var activity := false
	var stun_amount := 1
	for phrase: Effect.CostPhrase in phrases:
		if phrase.verb.name == &"self_stun":
			activity = true
			stun_amount = int(phrase.verb.user_params[1]) if phrase.verb.user_params.size() > 1 else 1
			continue
		if phrase.verb.name == &"pay_life": rows.append(life_change(-int(phrase.verb.user_params[0]), -int(phrase.verb.user_params[1]), unit.player if unit != null else 1))
		elif phrase.verb.name == &"decrement" and phrase.target is Selectors.PropertyOf:
			var amount: Variant = phrase.verb.user_params[0]
			var row := "%s %s" % [amount.symbol if amount is RuleNumber else str(amount), String(phrase.target.key).to_lower()]
			if amount is RuleNumber: row = "−" + row
			if not _is_self(phrase.target.input): row += " on " + _selector(phrase.target.input, unit)
			rows.append(row)
		elif phrase.verb.name == &"decrement" and phrase.target is Selectors.CountersOf:
			var host: Selector = phrase.target.input
			rows.append("-1 counter" + ("" if _is_self(host) else " on " + _selector(host, unit)))
		elif phrase.verb.name == &"sacrifice" and selector_range(phrase.target) >= 0:
			rows.append("sacrifice within %d" % selector_range(phrase.target))
		else: rows.append(_phrase(phrase, unit))
	var marker := String(label).replace("AC", "AS").replace("C", "A")
	if not consume_action: marker = marker.trim_prefix("A")
	if marker.is_empty(): marker = ("A" if consume_action else "") + ((str(stun_amount) if stun_amount > 1 else "") + "S" if activity else "")
	if marker.is_empty(): return " and ".join(rows)
	return "[lb]%s[rb]%s" % [marker, (" " + " and ".join(rows)) if not rows.is_empty() else ""]

## Recognizes the standard SELF activity cost so ordinary action rows can omit familiar payment rules.
## describe_effect() still prints custom payments and triggered activity costs; no cost is altered or paid here.
static func _default_activity_cost(cost: RefCounted) -> bool:
	return cost is Effect.CostPhrase and cost.verb != null and cost.verb.name == &"self_stun" \
		and _is_self(cost.subject) and _is_self(cost.target) and (cost.verb.user_params.size() < 2 or int(cost.verb.user_params[1]) == 1)

## Returns the hex-info amount/sticker/icon/range form for simple SELF actions, or empty for complex target rules.
## Normal hover actions use this; triggers keep explicit participants and compound selectors keep their restrictions.
## Icon images come from GameIcons; exact-ability Fire range grants and family bonuses match execution.
## Friendly Shield/Mshield, hostile Push/Pull and other-than-SELF Mend use shared amount-icon-range shorthand.
## Explicit enemy-only Fire projections keep their owner restriction without spelling out the HEX projection.
static func compact_action(phrase: Effect.Phrase, unit: UnitInfo = null) -> String:
	if phrase == null or phrase.verb == null or not _is_self(phrase.subject) \
			or phrase.target_mode != Effect.Phrase.TargetMode.CHOOSE_ONE: return ""
	if phrase.verb.user_params.any(func(value: Variant) -> bool: return value is RuleNumber): return ""
	var name := phrase.verb.name
	var values := _values(phrase, unit)
	var markers := _qualifiers(phrase)
	if name == &"fire" and phrase.target is Selectors.HexOf and phrase.target.input is QuerySelector:
		return "%s%s%s to %s" % [values[0], markers, _action(name, unit), _query(phrase.target.input, unit, true)]
	if name in [&"shield", &"mshield"] and _is_self(phrase.target) and not values.is_empty():
		var shield := "%d%s%s" % [values[0], markers, _action(name, unit)]
		return "[color=#c084fc]%s[/color]" % shield if name == &"mshield" else shield
	var radius := _compact_radius(phrase.target, name)
	if radius < 0: return ""
	if name == &"reset": return "reset %d" % radius
	if name in [&"shield", &"mshield"] and not values.is_empty():
		return "%d%s%s %d" % [values[0], markers, _action(name, unit), radius]
	if name in [&"move", &"fly"] and not values.is_empty():
		if radius != int(phrase.verb.user_params[0]): return ""
		return "%s%s%s" % [markers, _action(name, unit), action_value(values[0], int(phrase.verb.user_params[0]))]
	if name == &"fire" and not values.is_empty():
		var printed_radius := radius
		if unit != null: radius = unit.effective_action_values(name, [0, radius + unit.ability_bonus(phrase.verb).y])[1]
		return "%s%s%s%s" % [action_value(values[0], int(phrase.verb.user_params[0])), markers, _action(name, unit), action_value(radius, printed_radius)]
	if name in [&"bow", &"cannon", &"bomb_throw", &"gore", &"mend", &"stun", &"push", &"pull", &"push_bomb", &"pull_bomb"] and values.size() >= 2:
		if radius != int(phrase.verb.user_params[1]): return ""
		return "%s%s%s%s" % [action_value(values[0], int(phrase.verb.user_params[0])), markers, _action(name, unit), action_value(values[1], int(phrase.verb.user_params[1]))]
	if name == &"bomb_defuse": return "%s%s%d" % [markers, _action(name, unit), radius]
	return ""

## Recognizes radius targets and the normal Mend/Stun ownership filters without hiding additional restrictions.
## compact_action() accepts each action family's default ownership; special names, flags and unit types retain explicit target text.
static func _compact_radius(query: Selector, action: StringName) -> int:
	if query is DistanceSelector:
		var spatial := query as DistanceSelector
		if spatial.include_inside and spatial.direction == Enum.direction.FROM \
				and spatial.center in [Selectors.Anchor.SELF, Selectors.Anchor.SUBJECT]: return spatial.distance
	if query is Selectors.BowTargets: return query.printed_range
	if query is Selectors.UnitsOn: return _compact_radius(query.input, action)
	if query is Selectors.Group and not query.union and query.right is QuerySelector:
		var filter := query.right as QuerySelector
		var expected_owner := Enum.YOU if action in [&"mend", &"shield", &"mshield"] else Enum.OPP
		if action in [&"mend", &"stun", &"shield", &"mshield", &"push", &"pull"] and filter.kind == TargetRef.Kind.UNIT \
				and filter.name_contains.is_empty() and filter.required_flag.is_empty() \
				and filter.relative_owner == expected_owner and filter.owner == Enum.owner.ANY \
				and filter.type == Enum.type.ANY and filter.excluded_type == Enum.type.ANY and filter.state in [-1, Enum.t_state.DEPLOYED] and filter.region == Enum.region.ANY \
				and filter.side == Enum.side.ANY and filter.control == Enum.control.ANY:
			return _compact_radius(query.left, action)
	return -1

## Walks atomic payment bundles and ordered consequences without evaluating or storing activation state.
## describe_effect() requests compact actions; adjacent mandatory SELF physical/magic changes share one displayed pair.
## Only their presentation is grouped: execution order, events, separate choices, and payment bundles are unchanged.
## Two automatic Shield/Mshield grants to the same identity share one target clause joined by 'and'.
## Choose-recipient/choose-ability Upgrade sequences print damage/range, the PixelLab upgrade arrow and radius while preserving choice steps.
## Courier's counter choice and Shaman's two Bash choices describe their complete operation once, while executions retain separate identities.
## A standalone counter consequence can omit its recipient when both actor and counter host are SELF.
static func _steps(definition: RefCounted, unit: UnitInfo, compact: bool = false) -> String:
	if definition is Effect.Phrase: return _phrase(definition, unit, compact, definition is Effect.ConsequencePhrase)
	if definition is Effect.ConsequenceSequence and definition.phrases.size() == 2:
		var first: Effect.ConsequencePhrase = definition.phrases[0]
		var second: Effect.ConsequencePhrase = definition.phrases[1]
		if first.verb.name == &"choose_counter" and second.verb.name == &"transfer_counter" and first.target is Selectors.CountersOf:
			return "transfer up to %d counters between two units within %d from this unit" % [first.verb.amount_limit, selector_range(first.target.input)]
		if first.verb.name == &"choose_bashing" and second.verb.name == &"return_two_bashing": return "return two bashing units"
	if definition is Effect.ConsequenceSequence and definition.phrases.size() == 2:
		var first: Effect.ConsequencePhrase = definition.phrases[0]
		var second: Effect.ConsequencePhrase = definition.phrases[1]
		if first.verb.name == &"shield" and second.verb.name == &"mshield" and _is_self(first.target) and _is_self(second.target) \
				and first.target_mode == Effect.Phrase.TargetMode.ALL and second.target_mode == Effect.Phrase.TargetMode.ALL \
				and not first.optional and not second.optional:
			return "%d %s and %d %s to this unit" % [first.verb.user_params[0], _action(&"shield", unit), second.verb.user_params[0], _action(&"mshield", unit)]
	if definition is Effect.ConsequenceSequence and definition.phrases.size() == 2 \
			and definition.phrases[0].verb.name == &"choose_upgrade_unit" and definition.phrases[1].verb.name == &"upgrade_ability":
		var values: Array = definition.phrases[1].verb.user_params
		var recipient: String = _query(definition.phrases[0].target, unit, true) if definition.phrases[0].target is QuerySelector else _selector(definition.phrases[0].target, unit)
		var radius := selector_range(definition.phrases[0].target)
		return "%d/%d %s %d" % [int(values[0]), int(values[1]), GameIcons.bb(&"upgrade"), radius] if radius >= 0 else "%d/%d %s to %s" % [int(values[0]), int(values[1]), GameIcons.bb(&"upgrade"), recipient]
	var rows := PackedStringArray()
	if definition is Effect.ConsequenceSequence or definition is Effect.CostBundle:
		var index := 0
		while index < definition.phrases.size():
			if definition is Effect.ConsequenceSequence and index + 1 < definition.phrases.size():
				var pair := _paired_modifiers(definition.phrases[index], definition.phrases[index + 1])
				if not pair.is_empty():
					rows.append(pair)
					index += 2
					continue
			rows.append(_phrase(definition.phrases[index], unit, compact))
			index += 1
		return (" and " if definition is Effect.CostBundle else "; then ").join(rows)
	return "no consequence" if definition == null else "Unrecognized consequence"

## Returns one physical/magic pair for two adjacent, mandatory, unqualified counter changes on SELF, or empty otherwise.
## _steps() groups grants with neutral physical and purple magical text; printed effects are not already-applied upgrades.
static func _paired_modifiers(first: Effect.ConsequencePhrase, second: Effect.ConsequencePhrase) -> String:
	var keys: Array[StringName] = []
	var deltas: Array[String] = []
	for phrase: Effect.ConsequencePhrase in [first, second]:
		if phrase == null or phrase.verb == null or phrase.verb.name != &"change_counter" \
				or phrase.verb.user_params.is_empty() or phrase.optional or not _is_self(phrase.subject) \
				or not _qualifiers(phrase).is_empty() or not phrase.target is Selectors.PropertyOf: return ""
		var property := phrase.target as Selectors.PropertyOf
		if not _is_self(property.input) or property.key not in [UnitInfo.PHYSICAL_COUNTER, UnitInfo.MAGICAL_COUNTER]: return ""
		keys.append(property.key)
		deltas.append(_signed_parameter(phrase.verb.user_params[0]))
	if keys[0] == keys[1] or first.target_mode != second.target_mode: return ""
	var physical_index := 0 if keys[0] == UnitInfo.PHYSICAL_COUNTER else 1
	return "%s/[color=#c084fc]%s[/color] to itself" % [deltas[physical_index], deltas[1 - physical_index]]

## Formats symbol-only operations with explicit participants for nontrivial effects; normal actions can use compact_action().
## _steps() preserves targets, optionality and lifetimes; life changes put the heart between signed current/max deltas without upgrade colors.
## Uses shared PixelLab icons for action and life-upgrade clauses; descriptions always show an unlit bomb.
## Deployment resource grants use the compact signed wording requested for player-resource consequences.
## Reset, Copy and one-shot next-turn action grants retain their distinct card keywords rather than hiding their semantics in generic counter text.
## Trigger references print it/target, SELF prints itself, and Flee delegates movement details to its glossary; historical Bomb targets remain explicit.
## Formats authored verbs, including execution-bound counter kinds and Shaman's distinct participant choices, without resolving them.
## _steps enables implicit SELF wording only for a standalone counter consequence, so payments and other recipients remain explicit.
static func _phrase(phrase: Effect.Phrase, unit: UnitInfo, compact: bool = false, implicit_counter_self: bool = false) -> String:
	if phrase == null or phrase.verb == null: return "Incomplete phrase"
	if compact:
		var short_text := compact_action(phrase, unit)
		if not short_text.is_empty(): return ("you may " if phrase.optional else "") + short_text
	var name := phrase.verb.name
	var params := phrase.verb.user_params
	var values := _values(phrase, unit)
	var target_unit := unit if _is_self(phrase.subject) else null
	var target := _selector(phrase.target, target_unit, name)
	if phrase.target is QuerySelector: target = _query(phrase.target, target_unit, phrase.target_mode != Effect.Phrase.TargetMode.ALL)
	if _is_self(phrase.target) and _is_self(phrase.subject): target = "itself"
	if phrase.target is Selectors.HexOf and _is_self(phrase.target.input) and _is_self(phrase.subject): target = "itself"
	if name == &"up_life" and phrase.target is Selectors.Reference and phrase.target.anchor == Selectors.Anchor.EVENT_TARGET: target = "it"
	if phrase.verb.target_kind == TargetRef.Kind.UNIT and phrase.target != null and phrase.target.output_kind() == TargetRef.Kind.HEX:
		if phrase.target is DistanceSelector and phrase.target.distance == 1 and not phrase.target.include_inside:
			target = "adjacent unit"
		else: target = "units on " + target
	if not _singular(phrase.target) and phrase.target_mode == Effect.Phrase.TargetMode.ALL: target = "all " + target
	var action := _action(name, unit)
	var markers := _qualifiers(phrase)
	match name:
		&"add_counter":
			var recipient := "" if implicit_counter_self and target == "itself" else " to " + target
			if params[0] is RuleBinding: action = "+1 of the paid counter kind" + recipient
			elif params[0] == UnitInfo.STUN_COUNTER: action = "+%d %s" % [int(params[1]), _action(&"stun", unit)] + recipient
			elif params[0] == UnitInfo.TEMP_MAGICAL_COUNTER: action = "%d %s" % [int(params[1]), _action(&"mshield", unit)] + recipient
			else:
				var amount := _signed_parameter(params[1])
				var counter := _plain(params[0])
				if params[0] == UnitInfo.EMBER_COUNTER and (params[1] is RuleNumber or absi(int(params[1])) != 1):
					counter += "s"
				action = "%s %s" % [amount, counter] + recipient
		&"choose_bashing": action = "choose a bashing unit"
		&"return_two_bashing": action = "choose a different bashing unit; return both chosen units"
		&"spend_deployment": action = "−1 deploy"
		&"defeat_enemy": action = "defeat an enemy"
		&"upgrade_fire": action = "+1 Fire damage to itself"
		&"grant_next_fire": action = "%s for %s's next Fire" % ["Pierce" if params[0] == &"pierce" else "Instant", target]
		&"deploy_returned_hex": action = "deploy friend on target"
		&"choose_counter":
			var hosts := _selector(phrase.target.input, unit) if phrase.target is Selectors.CountersOf else target
			action = "choose up to %d counters of one kind from %s" % [phrase.verb.amount_limit, hosts]
		&"transfer_counter": action = "transfer the chosen counters to " + target
		&"sacrifice": action = "sacrifice " + target
		&"disable": action = "disable " + target.replace("undeployed ", "").replace("non-hero ", "")
		&"choose_upgrade_unit", &"choose_counter_unit": action = "choose " + target
		&"upgrade_ability": action = "%d/%d %s to one ability of the chosen unit" % [int(params[0]), int(params[1]), GameIcons.bb(&"upgrade")]
		&"flee": action = "Flee"
		&"reset": action = "Reset " + target
		&"return_to_hand": action = "return " + target
		&"return_and_deploy": action = "return %s, then deploy this unit there at full health" % target
		&"revive": action = "revive"
		&"copy_effect": action = "copy one effect from target"
		&"next_turn_actions": action = "%+d action for %s next turn" % [int(params[0]), "enemy" if phrase.target is QuerySelector and phrase.target.relative_owner == Enum.OPP else "you"]
		&"grant_deployments": action = "%+d deploy" % int(params[0])
		&"self_stun":
			var amount := int(params[1]) if params.size() > 1 else 1
			action = "%d self-Stun" % amount if _is_self(phrase.target) else "%d Stun to %s" % [amount, target]
		&"change_counter", &"decrement":
			if phrase.target is AdventurerRules.ExistingCounters:
				return "%+d existing counter on %s" % [int(params[0]), _selector(phrase.target.input, unit)]
			if not params.is_empty() and params[0] is RuleNumber:
				if name == &"change_counter" and phrase.target is Selectors.PropertyOf and phrase.target.key == &"Soul" and _is_self(phrase.target.input):
					return "+%s souls" % params[0].symbol
				action = "%s%s to %s" % ["−" if name == &"decrement" else "+", params[0].symbol, target]
				return action
			var delta := _numeric(params[0]) if not params.is_empty() else 0
			if name == &"decrement": delta = -delta
			action = "change %s by %+d" % [target, delta]
			if phrase.target is Selectors.PropertyOf:
				var property := phrase.target as Selectors.PropertyOf
				var host := "itself" if _is_self(property.input) and _is_self(phrase.subject) else _selector(property.input, unit)
				if not _singular(property.input): host = ("all " if phrase.target_mode == Effect.Phrase.TargetMode.ALL else "any of ") + host
				var recipient := "" if implicit_counter_self and host == "itself" else " to " + host
				action = "%+d %s" % [delta, _property(property.key)] + recipient
				if property.key == &"Soul" and host == "itself": action = "%+d soul" % delta
				if property.key in [UnitInfo.PHYSICAL_COUNTER, UnitInfo.TEMP_PHYSICAL_COUNTER]:
					action = "%+d" % delta + recipient
				elif property.key in [UnitInfo.MAGICAL_COUNTER, UnitInfo.TEMP_MAGICAL_COUNTER]:
					action = "[color=#c084fc]%+d[/color]" % delta + recipient
				elif property.key in [UnitInfo.BOW_DAMAGE_COUNTER, UnitInfo.BOW_RANGE_COUNTER]:
					var upgrade: Array[int] = [0, 0]
					upgrade[0 if property.key == UnitInfo.BOW_DAMAGE_COUNTER else 1] = delta
					action = _action_grant(&"bow", upgrade) + recipient
				if property.key in [UnitInfo.TEMP_PHYSICAL_COUNTER, UnitInfo.TEMP_MAGICAL_COUNTER]: action = "temporary " + action
		&"set_flag": action = "set %s %s" % [target, "on" if not params.is_empty() and bool(params[0]) else "off"]
		&"upgrade_bow": action = "%s to %s" % [_action_grant(&"bow", params), target]
		&"upgrade_cannon": action = "%s to %s" % [_action_grant(&"cannon", params), target]
		&"grant_action_values":
			if params.size() >= 2:
				action = "%s to %s until End" % [_action_grant(params[0], params[1]), target]
		&"grant_modifiers": action = "%s to %s until %sEnd" % [_modifiers(params[0], params[1]), target, "enemy " if params.size() > 2 and params[2] else ""]
		&"up_life":
			if params.size() >= 2: action = "%s to %s" % [life_change(int(params[0]), int(params[1]), unit.player if unit != null else 1), target]
		&"move":
			if params[0] is RuleNumber: action = "Walk " + params[0].symbol
			elif phrase.target is FrontierCatalogue.RetreatHexes: action = "Walk 1 away from it"
			else: action = markers + action + " to " + target
		_:
			if name in [&"fire", &"bow", &"cannon", &"bomb_throw", &"gore", &"mend", &"stun", &"shield", &"mshield", &"damage"] and not values.is_empty():
				action = "%s%s%s" % [action_value(values[0], _numeric(params[0])), markers, action]
			elif name in [&"push", &"pull", &"push_bomb", &"pull_bomb"] and not values.is_empty():
				action = "%d%s%s" % [values[0], markers, action]
			else: action = markers + action
			action += " to " + target
	if not params.is_empty() and params[0] is RuleNumber and name in [&"bow", &"fire", &"cannon", &"stun"]:
		action = "%s%s%s%d" % [params[0].symbol, markers, _action(name, unit), phrase.target.printed_range] if phrase.target is Selectors.BowTargets else "%s%s%s to %s" % [params[0].symbol, markers, _action(name, unit), target]
	if name == &"mshield": action = "[color=#c084fc]%s[/color]" % action
	if name == &"bomb_throw" and phrase.target is Selectors.EventHex and phrase.target.key == &"origin_hex":
		action = "%d%s%s on its previous hex" % [values[0], markers, _action(name, unit)]
	if not _is_self(phrase.subject): action = "%s: %s" % [_selector(phrase.subject, unit), action]
	if phrase.optional: action = "you may " + action
	return action

## Hover clauses and action buttons share signed current-heart-maximum life-change notation, with no magenta upgrade styling.
## Both numbers are always explicit, including zero; this describes an effect, not the unit's current modified health display.
static func life_change(actual_delta: int, maximum_delta: int, owner: int = 1, size: int = 32) -> String:
	return "%+d%s%+d" % [actual_delta, GameIcons.bb(&"heart", owner, size), maximum_delta]

## Numeric previews use zero for symbolic event values; descriptions retain their printed symbol separately and runtime bindings capture the actual event amount.
static func _numeric(value: Variant) -> int:
	return 0 if value is RuleNumber else int(value)

## Modifier phrases print signed numeric or X/Y event components through one shared notation.
static func _signed_parameter(value: Variant) -> String:
	return "+" + value.symbol if value is RuleNumber else "%+d" % int(value)

## Reads numeric action arity rather than treating timing booleans as magnitudes; applies live bonuses only to SELF actors.
## _phrase() uses these same UnitInfo derivations as action legality/previews, while trigger operations retain their fixed grants.
static func _values(phrase: Effect.Phrase, unit: UnitInfo) -> Array[int]:
	var name := phrase.verb.name
	var params := phrase.verb.user_params
	var values: Array[int] = []
	if name == &"fire" and not params.is_empty():
		values.append(_numeric(params[0]))
		values.append(0) # Fire's actual reach is described from each spatial selector, not from a Boolean verb parameter.
	elif name in [&"move", &"fly", &"bomb_defuse", &"shield", &"mshield", &"damage"]:
		if not params.is_empty(): values.append(_numeric(params[0]))
	elif name in [&"bow", &"cannon", &"bomb_throw", &"gore", &"mend", &"stun", &"push", &"pull", &"push_bomb", &"pull_bomb"]:
		for index in mini(2, params.size()): values.append(_numeric(params[index]))
	if unit != null and _is_self(phrase.subject) and not values.is_empty():
		var bonus := unit.ability_bonus(phrase.verb)
		values[0] += bonus.x
		if values.size() > 1 and name != &"fire": values[1] += bonus.y
	if unit != null and _is_self(phrase.subject) and name in [&"move", &"fly", &"fire", &"cannon", &"bow"] and not values.is_empty():
		return unit.effective_action_values(name, values)
	return values

## Describes selectors in their native domain, including references, projections, filters, direction, and exact/radius geometry.
## Phrase targets pass their action family for supported live ranges; event/condition/aura criteria remain printed rules.
## Names selectors structurally; specialized adventurer destinations preserve their enemy/Bash restrictions in hover text.
static func _selector(query: Selector, unit: UnitInfo, family: StringName = &"") -> String:
	if query == null: return "missing target"
	if query is AdventurerRules.BashingUnits: return "bashing units"
	if query is AdventurerRules.EnemyDestinations: return "enemy-occupied hexes within 2"
	if query is AdventurerRules.ExistingCounters: return "an already-present counter type on an adjacent friend (including zero; cannot create a new type)"
	if query is Selectors.Reference: return _anchor(query.anchor)
	if query is Selectors.EventHex: return "its previous hex" if query.key == &"origin_hex" else "the recorded hex"
	if query is QuerySelector: return _query(query, unit)
	if query is DistanceSelector:
		var spatial := query as DistanceSelector
		var radius: int = spatial.distance
		if unit != null:
			if family in [&"move", &"fly"]: radius = unit.effective_action_values(family, [radius])[0]
			elif family in [&"fire", &"cannon"]: radius = unit.effective_action_values(family, [0, radius])[1]
		var text := "hexes %s %d hexes from %s" % ["within" if spatial.include_inside else "exactly", radius, _anchor(spatial.center)]
		if spatial.direction != Enum.direction.FROM:
			text += " %s %s" % ["toward" if spatial.direction == Enum.direction.TOWARDS else "away from", _anchor(spatial.reference)]
		return text
	if query is Selectors.BowTargets:
		var radius: int = query.printed_range
		if unit != null: radius = maxi(0, radius + unit.effective_bow_bonus().y)
		return "hexes within %d hexes of this unit" % radius
	if query is Selectors.FleeDestinations: return "a legal movement destination"
	if query is Selectors.EffectsOf: return "effects of " + _selector(query.input, unit)
	if query is Selectors.CountersOf: return "positive counters on " + _selector(query.input, unit)
	if query is Selectors.PropertyOf: return "%s of %s" % [_property(query.key), _selector(query.input, unit)]
	if query is Selectors.UnitsOn:
		if query.input is DistanceSelector and query.input.distance == 1 and not query.input.include_inside \
				and query.input.direction == Enum.direction.FROM and query.input.center == Selectors.Anchor.SELF: return "adjacent units"
		return "units on " + _selector(query.input, unit, family)
	if query is Selectors.HexOf: return ("the hex of " if _singular(query.input) else "hexes occupied by ") + _selector(query.input, unit)
	if query is Selectors.Group:
		if not query.union and query.left is Selectors.UnitsOn and query.left.input is DistanceSelector \
				and query.left.input.distance == 1 and not query.left.input.include_inside and query.right is QuerySelector:
			return "adjacent " + _query(query.right, unit, true)
		return "(%s %s %s)" % [_selector(query.left, unit, family), "or" if query.union else "matching", _selector(query.right, unit, family)]
	if query is Selectors.Completed:
		if String(query.phase).begins_with("cost_choice_"): return "the chosen unit"
		return "the %s of the completed %s step" % [_escape(query.role), _escape(query.phase)]
	if query is Selectors.Literal:
		var refs := PackedStringArray()
		for ref in query.refs: refs.append(_reference(ref))
		return ", ".join(refs) if not refs.is_empty() else "no targets"
	return "Unrecognized selector"

## Names query criteria with singular 'any' wording for trigger participants and plural wording for sets/auras.
## _selector(), _phrase(), and _event() preserve all filters and source-owner colors even with no current candidates.
## Hero support queries explicitly retain both the other-than-SELF restriction and the troop-only filter.
static func _query(query: QuerySelector, unit: UnitInfo, singular: bool = false) -> String:
	if query is FrontierCatalogue.OtherFriends or query is SynergyCatalogue.OtherFriends:
		return "another friend" if singular else "other friends"
	if query is FrontierCatalogue.ProjectileUnits:
		if query.relative_owner == Enum.YOU: return "friend with Projectiles" if singular else "friends with Projectiles"
		return "unit with Projectiles" if singular else "units with Projectiles"
	if query is FrontierCatalogue.BashFriends: return "friend in a Bash" if singular else "friends in Bash"
	if query is HeroCatalogue.OtherFriends:
		return "friendly troop" if query.type == Enum.type.TROOP else "friend"
	var noun := "unit" if singular else "units"
	if query.kind == TargetRef.Kind.HEX: noun = "hex" if singular else "hexes"
	elif query.kind == TargetRef.Kind.PLAYER: noun = "player" if singular else "players"
	if query.kind == TargetRef.Kind.UNIT and query.type != Enum.type.ANY:
		noun = {Enum.type.HERO: "hero", Enum.type.TROOP: "troop", Enum.type.TEMPLE: "temple"}.get(query.type, "unit")
		if not singular: noun = "heroes" if query.type == Enum.type.HERO else noun + "s"
	if not query.name_contains.is_empty(): noun = query.name_contains.capitalize() + " " + noun
	if not query.required_flag.is_empty(): noun = String(query.required_flag) + " " + noun
	if query.state >= 0 and not (query.state == Enum.t_state.DEPLOYED and query.relative_owner in [Enum.YOU, Enum.OPP]):
		noun = "%s %s" % [_enum_word(Enum.t_state, query.state), noun]
	if query.relative_owner != Enum.ANY:
		var friendly := query.relative_owner == Enum.YOU
		if query.kind == TargetRef.Kind.PLAYER: noun = "you" if friendly else "enemy"
		elif query.kind == TargetRef.Kind.UNIT and query.type == Enum.type.ANY and not query.name_contains.is_empty() and query.required_flag.is_empty():
			noun = "%s %s" % [query.name_contains.to_lower(), ("friend" if singular else "friends") if friendly else ("enemy" if singular else "enemies")]
			if query.state >= 0 and query.state != Enum.t_state.DEPLOYED: noun = _enum_word(Enum.t_state, query.state) + " " + noun
		elif query.kind == TargetRef.Kind.UNIT and query.type == Enum.type.ANY and query.name_contains.is_empty() and query.required_flag.is_empty():
			noun = ("friend" if singular else "friends") if friendly else ("enemy" if singular else "enemies")
			if query.state >= 0 and query.state != Enum.t_state.DEPLOYED: noun = _enum_word(Enum.t_state, query.state) + " " + noun
		else: noun = "%s %s" % ["friendly" if friendly else "enemy", noun]
		var owner := (unit.player if friendly else 3 - unit.player) if unit != null else 0
		noun = _owner_color(noun, owner) if friendly else "[color=#ef7770]%s[/color]" % noun
	if singular and query.relative_owner == Enum.ANY: noun = "any " + noun
	if query.excluded_type == Enum.type.HERO: noun = "non-hero " + noun
	if query.owner != Enum.owner.ANY:
		match query.owner:
			Enum.owner.NONE: noun += " with no owner"
			Enum.owner.BOTH: noun += " belonging to both players"
			_: noun += " belonging to " + _owner_color("Player %d" % query.owner, query.owner)
	if query.region != Enum.region.ANY: noun += " in a %s region" % _enum_word(Enum.region, query.region)
	if query.side != Enum.side.ANY: noun += " on %s" % ("neither home side" if query.side == Enum.side.NONE else "Player %d's side" % query.side)
	if query.control != Enum.control.ANY: noun += " in %s" % ("a neutral region" if query.control == Enum.control.NONE else "a region controlled by Player %d" % query.control)
	return noun

## Builds concise trigger anchors such as 'this unit 🔥 to any hex' without repeating icon names or mandatory policy.
## describe_effect() keeps target-stage declarations explicit; ordinary resolved events use the implicit colon rule notation.
## Trigger action anchors use the same owner-aware PixelLab icons as their consequence descriptions.
## Death anchors use the shared skull image, matching the Die vocabulary in other rule descriptions.
## SELF action occurrences with an unrestricted target omit 'to any hex'; only constrained targets remain explicit.
## Hit/Wound describe contact, attack declarations use “attacks,” and fixed life changes use signed heart notation.
static func _event(event: Effect.EventPhrase, unit: UnitInfo) -> String:
	var actor := _selector(event.subject, unit)
	var target := _selector(event.target, unit)
	if event.subject is QuerySelector: actor = _query(event.subject, unit, true)
	if event.target is QuerySelector: target = _query(event.target, unit, true)
	var name := event.observed_action if not event.observed_action.is_empty() else (event.verb.name if event.verb != null else &"")
	var text := ""
	if event.observes_attack_declaration: return actor + " attacks"
	if name == &"life_increase" and event.detail_constraints.has("actual") and event.detail_constraints.has("maximum"):
		return "%s on %s" % [life_change(int(event.detail_constraints.actual), int(event.detail_constraints.maximum),
			unit.player if unit != null else 1), actor]
	if name in [&"hit", &"wound"] and event.target is QuerySelector and event.target.relative_owner == Enum.ANY \
			and event.target.owner == Enum.owner.ANY and event.target.type == Enum.type.ANY and event.target.state < 0 \
			and event.target.region == Enum.region.ANY and event.target.side == Enum.side.ANY and event.target.control == Enum.control.ANY \
			and event.target.name_contains.is_empty() and event.target.required_flag.is_empty() and event.target.excluded_type == Enum.type.ANY:
		return actor + (" hits" if name == &"hit" else " wounds")
	if _is_self(event.subject) and name in [&"fire", &"bow", &"cannon", &"move", &"fly", &"gore"] \
			and event.target is QuerySelector and event.target.relative_owner == Enum.ANY and event.target.owner == Enum.owner.ANY \
			and event.target.type == Enum.type.ANY and event.target.state < 0 and event.target.region == Enum.region.ANY \
			and event.target.excluded_type == Enum.type.ANY and event.target.side == Enum.side.ANY and event.target.control == Enum.control.ANY \
			and event.target.name_contains.is_empty() and event.target.required_flag.is_empty():
		return "this unit " + _action(name, unit)
	if name in [&"start", &"end"]:
		text = "at %s's %s" % [actor, _plain(name)]
		if event.subject is QuerySelector:
			if event.subject.relative_owner == Enum.YOU: text = "at your " + _plain(name)
			elif event.subject.relative_owner == Enum.OPP: text = "at your opponent's " + _plain(name)
	elif name == &"life_increase": text = actor + " +X" + _action(&"heart", unit) + "+Y (at least one is positive)"
	elif name == &"bomb_hit": text = target + " is hit by " + _action(&"bomb_throw", unit)
	elif name == &"disable": text = target + " is disabled"
	elif name == &"sacrifice": text = target + " is sacrificed"
	elif name == &"reset": text = target + " is Reset"
	elif name == &"die": text = actor + " " + _action(name, unit)
	elif name == &"return_to_hand": text = target + " returns"
	elif name == &"ember_added": text = "one or more Embers are put on " + target
	elif name == &"gain_region": text = actor + " gains control of this unit's region"
	elif name == &"bash" and event.detail_constraints.get("defender_fled", false):
		return "[color=#ef7770]enemy[/color] flees from this unit"
	elif name == &"bash": text = "%s %s %s" % [actor, _action(name, unit), target]
	elif name in [&"hit", &"wound"]: text = "%s %s %s" % [actor, "hits" if name == &"hit" else "wounds", target]
	elif name == &"deploy" and _is_self(event.subject): text = "this unit deploys"
	elif name == &"move" and _is_self(event.subject): text = "this unit " + _action(name, unit)
	else:
		var actions := PackedStringArray()
		if event.matches_any_action: actions.append("any action")
		elif event.observes_family or not name.is_empty(): actions.append(_action(name, unit))
		else:
			for observed in event.observed_actions: actions.append(_action(observed, unit))
		text = "%s %s to %s" % [actor, " or ".join(actions), target]
		if event.stage == &"target": text += " (declared)"
	if not event.detail_constraints.is_empty():
		var facts := PackedStringArray()
		for key in event.detail_constraints: facts.append("%s = %s" % [_plain(key), _escape(event.detail_constraints[key])])
		text += " (%s)" % ", ".join(facts)
	return text

## Formats observable predicates structurally, including recipient versus source scope and Boolean/quantified rules.
## Guards and continuous descriptions include geographic adventurer predicates without evaluating current eligibility.
## Hero ammo and Sacrifice guards expose their recipient/departure semantics in hover and exported rule text.
static func _condition(value: Condition, subject: String, unit: UnitInfo) -> String:
	if value is FrontierCatalogue.EnemySide: return subject + " is on the enemy side"
	if value is HeroCatalogue.Loaded: return subject + " has one or more projectiles"
	if value is HeroCatalogue.NearbySacrifice: return "another friendly unit was Sacrificed within 2 of this unit (at its departure hex)"
	if value is AdventurerRules.EnemyStarting: return subject + " is on enemy Starting"
	if value is AdventurerRules.OwnRegion: return "the gained region contains this unit"
	if value is AdventurerRules.TwoBashing: return "at least two units are bashing"
	if value is SynergyRules.PhysicalAtLeast: return "%s has physical modifier at least %d" % [subject, value.minimum]
	if value is SynergyRules.OnUnlitBomb: return subject + " is on an unlit bomb"
	if value is SynergyRules.BashingStunned: return subject + " is bashing an enemy with Stun"
	if value is SynergyRules.BashingDisplaced: return subject + " is bashing an enemy Pushed or Pulled this turn"
	if value is SynergyRules.AttackKind: return "the contact was caused by " + _plain(value.family)
	if value is SynergyRules.AlreadyStunned: return "the hostile Stun target already had Stun before this action"
	if value is Condition.EventPositive: return "the %s life increase is positive" % value.key
	if value is Condition.CounterAtLeast: return "%s has at least %d %s" % [subject, value.amount, _plain(value.key)]
	if value == null: return "always"
	if value is Condition.Wounded: return subject + " is wounded"
	if value is Condition.BashingEnemyHero: return subject + " is " + _action(&"bash", unit) + " an enemy hero"
	if value is Condition.BashingEnemy: return subject + " is " + _action(&"bash", unit)
	if value is Condition.Bashing: return subject + " is " + _action(&"bash", unit)
	if value is Condition.Active: return subject + (" is active" if value.expected else " is inactive")
	if value is Condition.Deployed: return subject + " is deployed"
	if value is Condition.Shielded: return subject + " has temporary physical or magical protection"
	if value is Condition.Not: return "not (%s)" % _condition(value.condition, subject, unit)
	if value is Condition.All or value is Condition.AnyOf:
		var parts := PackedStringArray()
		for part in value.conditions: parts.append(_condition(part, subject, unit))
		if parts.is_empty(): return "no condition can be satisfied"
		return "(" + (" and " if value is Condition.All else " or ").join(parts) + ")"
	if value is Condition.Matches:
		var selection := _selector(value.selector, unit)
		match value.mode:
			Condition.Matches.Mode.NONE: return "none of (%s) exist" % selection
			Condition.Matches.Mode.ALL: return "every one of (%s) matches (%s), with at least one present" % [selection, _selector(value.predicate, unit)]
		return "at least one of (%s) exists" % selection
	if value is Condition.Compare:
		var symbols := ["=", "<", "≤", ">", "≥"]
		return "%s %s %d" % [_selector(value.selector, unit), symbols[value.operation], value.value]
	if value is Condition.EventFact: return "the event's %s is %s" % [_plain(value.key), _escape(value.expected)]
	return "Unrecognized condition"

## Describes aura outputs and recipients with only nontrivial source/recipient conditions; deployed scope is implicit.
## unit_lines() still reads definition fields rather than handwritten labels and preserves each recipient's condition.
## Modifier auras put the eligible recipients before 'have'; recipient predicates are relative clauses rather than trailing 'if'.
static func _continuous(aura: ContinuousEffect, unit: UnitInfo) -> String:
	var outputs := PackedStringArray()
	for output in aura.contributions:
		if output == null: continue
		match output.kind:
			Contribution.Kind.MODIFIER: outputs.append(_modifiers(output.physical, output.magical))
			Contribution.Kind.PASSIVE: outputs.append(_plain(output.property))
			Contribution.Kind.ACTION_VALUE: outputs.append(_action_grant(output.action_family, output.parameters))
			Contribution.Kind.SUPPRESS_DEFEAT_TRIGGERS: outputs.append("suppression of triggers caused by the recipient's defeat")
			Contribution.Kind.EXTRA_DEATH_TRIGGER: return "%s %s triggers one additional time" % [_owner_color("friendly units", unit.player if unit != null else 1), _action(&"die", unit)]
			Contribution.Kind.PLAYER_ACTIONS: outputs.append("%+d player actions" % output.actions)
			Contribution.Kind.SUPPRESS_DEPLOY_TRIGGERS: return "%s deployment does not trigger any ability" % _aura_targets(aura.recipients, unit).replace("adjacent units", "adjacent unit")
			_: outputs.append("Unrecognized contribution")
	var text := "%s to %s" % [" and ".join(outputs), _selector(aura.recipients, unit)]
	var modifier_only := aura.contributions.all(func(output: Contribution) -> bool: return output.kind == Contribution.Kind.MODIFIER)
	var recipients := _aura_targets(aura.recipients, unit)
	if recipients == "adjacent friend": recipients = "adjacent friends"
	if aura.recipient_condition is Condition.Bashing: recipients = recipients.replace("adjacent ", "adjacent bashing ")
	if modifier_only:
		if aura.recipient_condition is HeroCatalogue.Loaded: recipients += " with one or more projectiles"
		elif aura.recipient_condition is SynergyRules.OnUnlitBomb: recipients += " over bombs"
		elif aura.recipient_condition is SynergyRules.PhysicalAtLeast: recipients += " with +%d or more physical" % aura.recipient_condition.minimum
		elif aura.recipient_condition != null and not aura.recipient_condition is Condition.Bashing: recipients += " that " + _condition(aura.recipient_condition, "they", unit)
		text = recipients + " have " + " and ".join(outputs)
	elif aura.recipient_condition is SynergyRules.PhysicalAtLeast:
		text = recipients + " with +%d or more physical have " % aura.recipient_condition.minimum + " and ".join(outputs)
	elif aura.source_condition == null and aura.recipient_condition == null:
		text = recipients + " have " + " and ".join(outputs)
	if aura.contributions.size() == 1 and aura.contributions[0].kind == Contribution.Kind.PLAYER_ACTIONS:
		text = "%+d action%s for your player" % [aura.contributions[0].actions, "" if aura.contributions[0].actions == 1 else "s"]
	if aura.source_condition != null:
		if modifier_only: text = " and ".join(outputs) + " to " + recipients
		text = "while %s: %s" % [_condition(aura.source_condition, "this unit", unit), text]
	if aura.recipient_condition != null and not modifier_only and not aura.recipient_condition is SynergyRules.PhysicalAtLeast: text += " if " + _condition(aura.recipient_condition, "the recipient", unit)
	return text

## Continuous rules describe sets in the plural; spatial action choices keep their separate singular target wording.
static func _aura_targets(query: Selector, unit: UnitInfo) -> String:
	if query is Selectors.Group and not query.union and query.left is Selectors.UnitsOn \
			and query.left.input is DistanceSelector and query.left.input.distance == 1 and not query.left.input.include_inside \
			and query.right is QuerySelector:
		return "adjacent " + _query(query.right, unit, false)
	return _selector(query, unit)

## Live action labels use magenta only when an effective M/N differs from its printed value; printed grants remain neutral.
## Hover, board labels and menu callers share this presentation-only comparison without storing or mutating upgrades.
static func action_value(current: int, printed: int) -> String:
	return "[color=#ef70df]%d[/color]" % current if current != printed else str(current)

## Printed modifier rules keep physical neutral and magic purple; magenta is reserved for applied action-value changes.
## State rules, continuous grants, and counter descriptions share this without changing counters or reading live totals.
static func _modifiers(physical: Variant, magical: Variant) -> String:
	return "%s/[color=#c084fc]%s[/color]" % [_signed_parameter(physical), _signed_parameter(magical)]

## Formats signed upgrades around the action icon: +N icon +M, keeping zero and negative components explicit.
## Printed grant amounts are neutral; actual applied M/N changes receive magenta in the live action-value display.
## One-value movement/defuse grants keep their range to the right.
static func _action_grant(family: StringName, parameters: Array) -> String:
	var values := PackedStringArray()
	for value in parameters: values.append("%+d" % int(value))
	var icon := _action(family)
	if values.is_empty(): return icon
	var text := values[0] + icon
	if values.size() > 1: text += ",".join(values.slice(1))
	elif family in [&"move", &"fly", &"bomb_defuse"]: text = icon + values[0]
	return text

## Returns only attack F/P markers; activity/action exemptions are represented by independent A/S cost prefixes, never a T sticker.
## compact_action() and detailed trigger phrases share this without spelling out icon or sticker names.
static func _qualifiers(phrase: Effect.Phrase) -> String:
	var name := phrase.verb.name
	var params := phrase.verb.user_params
	var instant := phrase.has_sticker(ActionSticker.Kind.INSTANT)
	var pierce := phrase.has_sticker(ActionSticker.Kind.PIERCE)
	var action_free := phrase.action_free or phrase.has_sticker(ActionSticker.Kind.ACTION_FREE)
	if name in [&"fire", &"bow", &"cannon", &"bomb_throw"]:
		var timing_index := 1 if name == &"fire" else 2
		if name != &"bomb_throw" and params.size() > timing_index: instant = instant or bool(params[timing_index])
		var pierce_index := 2 if name in [&"fire", &"bomb_throw"] else 3
		if params.size() > pierce_index: pierce = pierce or bool(params[pierce_index])
	var token_index := -1
	match name:
		&"move", &"fly", &"bomb_defuse", &"self_stun": token_index = 0 if name == &"self_stun" else 1
		&"fire", &"bomb_throw": token_index = 3
		&"bow", &"cannon": token_index = 4
		&"gore", &"mend", &"stun": token_index = 2
		&"push", &"pull", &"push_bomb", &"pull_bomb": token_index = 3
	if token_index >= 0 and params.size() > token_index: action_free = action_free or bool(params[token_index])
	var labels := PackedStringArray()
	if instant: labels.append("F")
	if pierce: labels.append("P")
	return "".join(labels)

## Identifies fixed single bindings so descriptions do not imply group selection for SELF/property anchors.
## _phrase() uses this only for wording; it does not bypass any runner-owned target choice.
static func _singular(query: Selector) -> bool:
	if query is Selectors.EventHex: return true
	if query is Selectors.Reference: return true
	if query is Selectors.PropertyOf or query is Selectors.HexOf: return _singular(query.input)
	if query is Selectors.Literal: return query.refs.size() == 1
	return false

## Recognizes SELF structurally; no current candidate resolution is needed to decide which card's bonuses to display.
## _values() and actor formatting call this before using UnitInfo's derived action values.
static func _is_self(query: Selector) -> bool:
	return query is Selectors.Reference and query.anchor == Selectors.Anchor.SELF

## Gives each contextual reference a distinct player-facing name, preserving event and recipient identity.
## Spatial and reference selector descriptions share this vocabulary.
static func _anchor(anchor: Selectors.Anchor) -> String:
	match anchor:
		Selectors.Anchor.SELF: return "this unit"
		Selectors.Anchor.SUBJECT: return "the acting unit"
		Selectors.Anchor.EVENT_SUBJECT: return "it"
		Selectors.Anchor.EVENT_TARGET: return "target"
		Selectors.Anchor.RECIPIENT: return "the recipient"
	return "an unbound reference"

## Describes fixed references by card/player/tile identity without invoking action legality or changing Match.
## Literal selectors use this for inspection, including off-board cards and property hosts.
static func _reference(ref: TargetRef) -> String:
	if ref == null: return "missing reference"
	match ref.kind:
		TargetRef.Kind.UNIT:
			var unit := Match.get_unit(ref.id)
			return _escape(unit.name) if unit != null else "missing unit"
		TargetRef.Kind.PLAYER: return "Player %d" % ref.id
		TargetRef.Kind.HEX:
			var tile := Match.get_hex(ref.id)
			return "hex %s" % tile.coordinate if tile != null else "missing hex"
		TargetRef.Kind.PROPERTY: return "%s of %s" % [_property(ref.property_key), _reference(ref.host)]
	return "the match"

## Names stable property keys concisely; unqualified modifiers are persistent counters, temporary protection stays explicit.
## Counter actions, PropertyOf selectors, and comparisons use this instead of handwritten card labels.
static func _property(key: StringName) -> String:
	match key:
		UnitInfo.PHYSICAL_COUNTER: return "physical"
		UnitInfo.MAGICAL_COUNTER: return "[color=#c084fc]magic[/color]"
		UnitInfo.TEMP_PHYSICAL_COUNTER: return "temporary physical protection"
		UnitInfo.TEMP_MAGICAL_COUNTER: return "[color=#c084fc]temporary magic protection[/color]"
		UnitInfo.STUN_COUNTER: return "Stun counter"
	return _plain(key)

## Looks up PixelLab inline images, including Push/Pull prefixes for bomb displacement, with owner-colored hearts; other verbs retain the existing glyph/name fallback.
## Phrase/event/action-grant descriptions use this action-level vocabulary, never a card-specific string table.
static func _action(name: StringName, unit: UnitInfo = null) -> String:
	if name == &"revive": return "revive"
	var icon := GameIcons.bb(name, unit.player if unit != null else 1)
	if not icon.is_empty():
		if name == &"bomb_defuse": return "defuse " + icon
		if name == &"bomb_light": return "light " + icon
		if name == &"push_bomb": return GameIcons.bb(&"push") + icon
		if name == &"pull_bomb": return GameIcons.bb(&"pull") + icon
		return icon
	return ACTIONS.get(name, _plain(name))

## Returns the enum's named criterion for query text rather than exposing numeric enum values.
## _query() uses this for existing region/lifetime enums.
static func _enum_word(values: Dictionary, index: int) -> String:
	for key in values:
		if int(values[key]) == index: return String(key).to_lower().replace("_", " ")
	return "unknown"

## Applies fixed player colors to relation words in generated BBCode, matching left/right hover cards.
## _query() calls this for ownership filters; unknown source ownership remains neutral.
static func _owner_color(text: String, owner: int) -> String:
	if owner not in [1, 2]: return text
	return "[color=%s]%s[/color]" % ["#ef7770" if owner == 1 else "#6da9ee", text]

## Turns authored identifiers into readable escaped words without interpreting them as a rule language.
## Fallback action/property names and event fact labels use this helper.
static func _plain(value: Variant) -> String:
	return _escape(String(value).replace("_", " ").replace("-", " ").capitalize())

## Escapes authored values before inserting them into a generated BBCode label.
## Names and event facts may contain brackets; formatting must never interpret those as markup.
static func _escape(value: Variant) -> String:
	return str(value).replace("[", "[lb]")
