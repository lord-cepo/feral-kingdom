## Short board labels derived from effect definitions. Full targeting and timing stay in the hover card.
extends RefCounted

const ACTION_NAMES := {
	&"damage": "Damage", &"defeat_enemy": "Defeat enemy",
	&"deactivate": "Deactivate", &"self_stun": "Self-Stun", &"reset": "Reset",
	&"return_to_hand": "Return", &"return_two_bashing": "Double return",
	&"return_and_deploy": "Swap in", &"deploy_returned_hex": "Redeploy",
	&"disable": "Disable", &"revive": "Revive", &"copy_effect": "Copy effect",
	&"transfer_counter": "Transfer counters", &"choose_counter": "Choose counter",
	&"choose_counter_unit": "Choose unit", &"choose_upgrade_unit": "Choose unit",
	&"choose_bashing": "Choose basher", &"upgrade_ability": "Upgrade",
	&"next_turn_actions": "Lend action", &"spend_deployment": "Spend deploy",
	&"pay_life": "Pay life", &"sacrifice": "Sacrifice", &"set_flag": "Set passive",
	&"flee": "Flee",
	&"relocate": "Move onto hex",
}
const SEQUENCE_NAMES := {
	"grant_deployments/revive": "Deploy/Revive",
	"move/grant_modifiers": "Shielded walk",
	"disable/disable": "Double disable",
	"disable/grant_deployments": "Trade deploy",
	"choose_bashing/return_two_bashing": "Double return",
	"choose_upgrade_unit/upgrade_ability": "Upgrade",
	"choose_counter/transfer_counter": "Transfer counters",
	"up_life/shield": "Life / Shield",
	"shield/flee": "Shield / Flee",
}
const EVENT_NAMES := {
	&"bomb_defuse": "Defuse", &"bomb_hit": "Blast", &"gain_region": "Control",
	&"return_to_hand": "Return", &"life_increase": "Life", &"atk": "Attack",
	&"patk": "Physical", &"ratk": "Ranged",
}

## HexCell uses the same rows for ordinary and Bash hexes. When a fired cue would be hidden, show it first.
static func rows(unit: UnitInfo, limit: int, highlighted: Array = []) -> PackedStringArray:
	var labels := PackedStringArray()
	if limit <= 0: return labels
	for effect in unit.effects:
		if effect != null and not effect.implicit: labels.append(effect_label(effect, unit))
	for effect in unit.trigger_effects:
		if effect == null: continue
		var label := effect_label(effect, unit)
		if highlighted.has(effect):
			label = "[color=#ffd84a]%s[/color]" % label
			if labels.size() >= limit - 1:
				labels.insert(0, label)
				continue
		labels.append(label)
	for state in unit.state_effects:
		if state != null: labels.append(_state_label(state))
	for aura in unit.continuous_effects:
		if aura == null: continue
		for output in aura.contributions:
			if output != null: labels.append(_aura_label(output, unit))
	for prop in unit.props:
		if prop != null and prop.increment == Enum.p_increment.FLAG and prop.value != 0 and prop.name != &"wild":
			labels.append(_passive_label(prop.name))
	if unit.control_bonus != 0: labels.append("%+d Control" % unit.control_bonus)
	if labels.size() > limit and limit > 1:
		var hidden := labels.size() - limit + 1
		labels = labels.slice(0, limit - 1)
		labels.append("%d more" % hidden)
	return labels.slice(0, limit)

## Builds one label per activated or triggered effect from its verbs, selectors, and event pattern.
static func effect_label(effect: Effect, unit: UnitInfo) -> String:
	var label := "Ability"
	if effect.consequence is Effect.ConsequencePhrase:
		label = _phrase_label(effect.consequence, unit, effect.event != null)
		if effect.consequence.verb.name == &"grant_next_fire":
			var resource := _paid_counter(effect.cost)
			if not resource.is_empty(): label = resource + ": " + label
	elif effect.consequence is Effect.ConsequenceSequence:
		label = _sequence_label(effect.consequence, unit)
		if effect.cost is Effect.CostPhrase and effect.cost.verb.name == &"sacrifice":
			label = "Sacrifice:" + label
	if effect.event == null: return label
	var event := effect.event.observed_action
	if event.is_empty() and effect.event.observes_attack_declaration: event = &"atk"
	var icon_key := &"heart" if event == &"life_increase" else event
	var cue := GameIcons.bb(icon_key, unit.player, 30)
	if not cue.is_empty(): return cue + ":" + label
	if event.is_empty(): return label
	if label.contains(" ") and not (label.begins_with("+") or label.begins_with("-")): return label
	return "%s:%s" % [EVENT_NAMES.get(event, EffectText._plain(event)), label]

## Sticker grants name the counter consumed by their fixed payment, including a payment inside a bundle.
static func _paid_counter(cost: RefCounted) -> String:
	if cost is Effect.CostPhrase and cost.verb.name == &"decrement" and cost.target is Selectors.PropertyOf:
		return EffectText._plain(cost.target.key)
	if cost is Effect.CostBundle:
		for phrase in cost.phrases:
			var resource := _paid_counter(phrase)
			if not resource.is_empty(): return resource
	return ""

## Uses names for multi-step choices and combines paired modifiers or board symbols when both fit.
static func _sequence_label(sequence: Effect.ConsequenceSequence, unit: UnitInfo) -> String:
	var names := PackedStringArray()
	for phrase in sequence.phrases: names.append(phrase.verb.name)
	match "/".join(names):
		"change_counter/change_counter":
			var first := sequence.phrases[0]
			var second := sequence.phrases[1]
			if first.target is Selectors.PropertyOf and first.target.key == UnitInfo.PHYSICAL_COUNTER \
					and second.target is Selectors.PropertyOf and second.target.key == UnitInfo.MAGICAL_COUNTER:
				return EffectText._modifiers(first.verb.user_params[0], second.verb.user_params[0])
			return "Shift counters"
		"shield/mshield":
			return _phrase_label(sequence.phrases[0], unit, true) + "/" + _phrase_label(sequence.phrases[1], unit, true)
		"bomb_throw/flee":
			return _icon(&"bomb_throw", unit) + ":Flee"
		"stun/change_counter":
			return _icon(&"stun", unit) + ":Guard"
	return SEQUENCE_NAMES.get("/".join(names), "Linked effects")

## Formats named operations and their semantic values. Numeric arguments only appear beside an icon or a named resource.
static func _phrase_label(phrase: Effect.ConsequencePhrase, unit: UnitInfo, triggered: bool) -> String:
	var name := phrase.verb.name
	var params := phrase.verb.user_params
	match name:
		&"grant_next_fire":
			return "Pierce" if params[0] == &"pierce" else "Instant"
		&"up_life":
			if triggered: return EffectText.life_change(int(params[0]), int(params[1]), unit.player, 30)
			return "Up life"
		&"grant_deployments":
			return "%+d Deploy" % int(params[0])
		&"grant_modifiers":
			return "Guard " + EffectText._modifiers(params[0], params[1])
		&"grant_action_values":
			return _upgrade_label(params[0], params[1], unit)
		&"upgrade_bow", &"upgrade_cannon":
			return _upgrade_label(&"bow" if name == &"upgrade_bow" else &"cannon", params, unit)
		&"upgrade_fire":
			return _upgrade_label(&"fire", [1, 0], unit)
		&"add_counter":
			return _counter_label(params[0], params[1], triggered)
		&"change_counter", &"decrement":
			if phrase.target is Selectors.PropertyOf:
				var amount: Variant = params[0]
				if name == &"decrement" and amount is int: amount = -amount
				return _counter_label(phrase.target.key, amount, triggered)
			return "Adjust counter"
		&"bomb_defuse":
			return "Defuse " + _icon(name, unit)
		&"bomb_light":
			return "Light " + _icon(name, unit)
	if ACTION_NAMES.has(name): return ACTION_NAMES[name]
	if name in [&"move", &"fly", &"fire", &"bow", &"cannon", &"gore", &"bomb_throw", &"push", &"pull",
			&"push_bomb", &"pull_bomb", &"mend", &"stun", &"shield", &"mshield"]:
		return _numeric_label(phrase, unit, triggered)
	return "Special ability"

## Pairs live action values with their icon and range; triggered Shield/Mshield rows display a signed counter gain.
static func _numeric_label(phrase: Effect.ConsequencePhrase, unit: UnitInfo, triggered: bool) -> String:
	var name := phrase.verb.name
	var params := phrase.verb.user_params
	var values := EffectText._values(phrase, unit)
	var symbol := EffectText._qualifiers(phrase) + _icon(name, unit)
	if values.is_empty(): return symbol
	var amount: String = params[0].symbol if params[0] is RuleNumber else EffectText.action_value(values[0], int(params[0]))
	if triggered and name in [&"shield", &"mshield"]: amount = "+" + amount
	if name in [&"move", &"fly"]: return symbol + amount
	var radius := EffectText.selector_range(phrase.target)
	if name == &"fire" and radius >= 0:
		var reach := unit.effective_action_values(name, [0, radius + unit.ability_bonus(phrase.verb).y])[1]
		return amount + symbol + EffectText.action_value(reach, radius)
	if name in [&"shield", &"mshield"] and radius >= 0: return amount + symbol + str(radius)
	if triggered and radius < 0 and name == &"mend" and amount == "1": return symbol
	if values.size() > 1 and name != &"fire" and (values[1] > 0 or radius >= 0):
		return amount + symbol + EffectText.action_value(values[1], int(params[1]))
	return amount + symbol

## Counter operations use a resource name and distinguish symbolic, paid and fixed amounts.
static func _counter_label(key: Variant, amount: Variant, triggered: bool) -> String:
	if key is RuleBinding: return "Paid counter"
	var label := String(key).replace("_", " ").capitalize()
	match key:
		UnitInfo.TEMP_PHYSICAL_COUNTER: label = "Shield"
		UnitInfo.TEMP_MAGICAL_COUNTER: label = "Mshield"
	if triggered and amount is int and amount == 1 and key == &"Soul": return "Soul"
	return EffectText._signed_parameter(amount) + " " + label if not label.contains(" ") else label

## Numeric grants retain the shared signed damage/range notation, with a symbol identifying the upgraded family.
static func _upgrade_label(family: StringName, values: Array, unit: UnitInfo) -> String:
	var label := _icon(family, unit)
	if values.is_empty(): return label
	if values.size() == 1: return label + "%+d" % int(values[0])
	return "%+d%s%+d" % [int(values[0]), label, int(values[1])]

## State rules show their printed protection, with named labels for calculated values.
static func _state_label(state: StateModifier) -> String:
	if state is AdventurerRules.AdjacentFriends: return "Friend guard"
	if state is AdventurerRules.MaximumLife: return "Life guard"
	if state is StateModifier.DeploymentDifference: return "Deploy guard"
	if state.condition is Condition.Wounded: return "Wounded " + EffectText._modifiers(state.physical, state.magical)
	if state.condition is Condition.Shielded: return "Shielded " + EffectText._modifiers(state.physical, state.magical)
	if state.condition is Condition.Bashing or state.condition is Condition.BashingEnemy \
			or state.condition is Condition.BashingEnemyHero or state.condition is SynergyRules.BashingStunned:
		return "Bash " + EffectText._modifiers(state.physical, state.magical)
	return "Guard " + EffectText._modifiers(state.physical, state.magical)

## Continuous contributions include live regional strength; hover gives its recipient and condition.
static func _aura_label(output: Contribution, unit: UnitInfo) -> String:
	match output.kind:
		Contribution.Kind.MODIFIER: return "Aura " + EffectText._modifiers(output.physical, output.magical)
		Contribution.Kind.ACTION_VALUE: return "Aura " + _upgrade_label(output.action_family, output.parameters, unit)
		Contribution.Kind.PASSIVE: return _passive_label(output.property)
		Contribution.Kind.PLAYER_ACTIONS: return "%+d Action" % output.actions
		Contribution.Kind.CONTROL: return "%+d Control" % output.control
		Contribution.Kind.SUPPRESS_DEFEAT_TRIGGERS: return "Mute death"
		Contribution.Kind.EXTRA_DEATH_TRIGGER: return "Extra death"
		Contribution.Kind.SUPPRESS_DEPLOY_TRIGGERS: return "Mute deploy"
	return "Aura"

## Printed and granted flags share their short board names, with explicit names for longer restrictions.
static func _passive_label(key: StringName) -> String:
	match key:
		&"enemy_control_deploy": return "Enemy deploy"
		&"must_bash": return "Must Bash"
	var label := EffectText._plain(key)
	return label if label.get_slice_count(" ") <= 2 else "Passive"

## Board symbols use the owner's palette and share the hover icon vocabulary.
static func _icon(name: StringName, unit: UnitInfo) -> String:
	var icon := GameIcons.bb(name, unit.player, 30)
	if not icon.is_empty(): return icon
	icon = GameIcons.fallback_glyph(name)
	return icon if not icon.is_empty() else EffectText._plain(name)
