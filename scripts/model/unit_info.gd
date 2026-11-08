class_name UnitInfo
extends RefCounted

# from unit_catalogue
var uuid: String = "" 
var name: String = ""
var effects: Array[Effect] = []
## Event definitions are separate from player-activated effects and never appear in action menus.
var trigger_effects: Array[Effect] = []
var type: Enum.type = Enum.type.TROOP

# from match
var player: int = 0
var active: bool = true
var props: Array[Prop] = []
var max_life: int = 0
var actual_life: int = 0
## Printed control added to this unit's current life when counting its region.
var control_bonus: int = 0
## Geographical region types where this card may be deployed.
var deploy_regions: Array[int] = [Enum.region.STARTING, Enum.region.INTERMEDIATE, Enum.region.FRONT]
const PHYSICAL_COUNTER: StringName = &"physical"
const MAGICAL_COUNTER: StringName = &"magical"
const TEMP_PHYSICAL_COUNTER: StringName = &"temp_physical"
const TEMP_MAGICAL_COUNTER: StringName = &"temp_magical"
const STUN_COUNTER: StringName = &"stun"
const BOW_DAMAGE_COUNTER: StringName = &"bow_damage"
const BOW_RANGE_COUNTER: StringName = &"bow_range"
const CANNON_DAMAGE_COUNTER: StringName = &"cannon_damage"
const CANNON_RANGE_COUNTER: StringName = &"cannon_range"
const CONTROL_COUNTER: StringName = &"control"
const EMBER_COUNTER: StringName = &"ember"
const PROJECTILE_COUNTER: StringName = &"projectile"
var state_effects: Array[StateModifier] = []
## Reusable auras supplied while this deployed unit is the source.
var continuous_effects: Array[ContinuousEffect] = []
## Concrete action-value grants expire during Match cleanup; they are not counters or auras.
var timed_grants: Array[TimedGrant] = []
## Merchant grants remain on this recipient until its next declared Fire or Reset, including through Return.
var next_fire_stickers: Array[StringName] = []
## Compatibility reads for older UI/snapshot callers; values live in named Bow counter properties.
var bow_damage_bonus: int:
	get: return _counter_value(BOW_DAMAGE_COUNTER)
var bow_range_bonus: int:
	get: return _counter_value(BOW_RANGE_COUNTER)
var modifier: Vector2i:
	get:
		return counter_modifiers() + state_modifiers()
var physical_modifier: int:
	get:
		return counter_modifiers().x + state_modifiers(0).x
var magical_modifier: int:
	get:
		return counter_modifiers().y + state_modifiers(1).y
var ihx: int = -1
var iun: int = -1
var t_state := Enum.t_state.UNDEPLOYED
## Printed values are captured once at match initialization; mutable copies retain provenance for save/load and Reset.
var printed_state: Dictionary = {}
var max_life_changes: Array[Dictionary] = []
var ability_upgrades: Array[Dictionary] = []
var deployment_enemy_side := false
## RulesRunner records limited trigger captures here; Reset and Return preserve the turn ledger.
var trigger_turns: Dictionary = {}
var copied_effects: Array[Dictionary] = []
## Historical forced movement survives Reset; Banner Bearer compares its turn instead of granting a mutable flag.
var last_displaced_turn := -1

## Creates the four modifier counters and the unit's numeric Stun counter.
## CardCatalogue calls UnitInfo.new() before applying printed values/effects.
func _init() -> void:
	for key in [PHYSICAL_COUNTER, MAGICAL_COUNTER, TEMP_PHYSICAL_COUNTER, TEMP_MAGICAL_COUNTER, STUN_COUNTER]:
		var counter := Prop.new()
		counter.name = key
		counter.increment = Enum.p_increment.COUNTER
		counter.target = Enum.p_target.UNIT
		props.append(counter)

## Match initialization captures immutable authored arrays and cloned printed properties after adding default movement.
## Reset restores these values on the same stable unit identity; captured executions keep their original definitions.
func capture_printed_state() -> void:
	if not printed_state.is_empty(): return
	printed_state = {"life": max_life, "control": control_bonus, "regions": deploy_regions.duplicate(), "enemy_side": deployment_enemy_side, "props": _clone_props(props)}
	for category in [&"effects", &"trigger_effects", &"state_effects", &"continuous_effects"]:
		printed_state[category] = get(category).duplicate()

## Reset's verb restores health, printed effects/passives and properties while preserving owner, location, card state and activity.
## No return-to-hand/death event is invented; counters and temporary/copied grants are discarded.
## Maximum-life provenance is cleared with the changes it described.
func reset_printed_state() -> void:
	if printed_state.is_empty(): return
	next_fire_stickers.clear()
	max_life = printed_state.life
	actual_life = max_life
	control_bonus = printed_state.control
	deploy_regions.assign(printed_state.regions)
	deployment_enemy_side = bool(printed_state.get("enemy_side", false))
	props = _clone_props(printed_state.props)
	for category in [&"effects", &"trigger_effects", &"state_effects", &"continuous_effects"]:
		get(category).assign(printed_state[category])
	timed_grants.clear()
	copied_effects.clear()
	max_life_changes.clear()
	ability_upgrades.clear()

## Exact-ability upgrades remain recipient-bound; preview, legality and execution query the same immutable effect/verb identity.
func ability_bonus(verb: Effect.Verb) -> Vector2i:
	var result := Vector2i.ZERO
	for grant in ability_upgrades:
		var effect: Effect = grant.effect
		if effect.consequence is Effect.ConsequencePhrase and effect.consequence.verb == verb:
			result += Vector2i(int(grant.damage), int(grant.range))
	return result

## Upgrade's PROPERTY-targeted action records the selected reusable ability and its responsible source for persistence and hover provenance.
func add_ability_upgrade(effect: Effect, damage: int, range: int, source: TargetRef) -> void:
	var actor := Match.get_unit(source.id) if source != null and source.kind == TargetRef.Kind.UNIT else null
	ability_upgrades.append({"effect": effect, "damage": damage, "range": range, "source": actor.name if actor != null else "Effect"})

## Life-changing verbs retain actual applied deltas and source names for hover summaries, even if the source later dies or resets.
func record_max_life_change(subject: TargetRef, delta: int) -> void:
	if delta == 0: return
	var source_unit := Match.get_unit(subject.id) if subject != null and subject.kind == TargetRef.Kind.UNIT else null
	max_life_changes.append({"amount": delta, "source": source_unit.name if source_unit != null else "Effect", "owner": source_unit.player if source_unit != null else 0})

## Hover summaries list printed maximum and retained effect sources; old saves without provenance use an honest unattributed remainder.
func max_life_breakdown() -> PackedStringArray:
	var baseline: int = printed_state.get("life", max_life)
	var rows := PackedStringArray(["%d printed maximum" % baseline])
	var accounted := baseline
	for change in max_life_changes:
		var amount := int(change.get("amount", 0))
		accounted += amount
		rows.append("%+d %s" % [amount, change.get("source", "Effect")])
	if accounted != max_life: rows.append("%+d earlier effect (source unavailable)" % (max_life - accounted))
	return rows

## Printed-state capture/reset clone numeric properties without retaining mutable counter instances.
func _clone_props(values: Array[Prop]) -> Array[Prop]:
	var result: Array[Prop] = []
	for value in values:
		var copy := Prop.new()
		copy.name = value.name
		copy.value = value.value
		copy.increment = value.increment
		copy.target = value.target
		result.append(copy)
	return result

## EffectsOf and Match property lookup expose immutable definitions as stable selectable properties, including copied definitions and printed passive flags.
## Name groups are not abilities: obsolete Wild flags are excluded; real passives retain origin metadata for snapshot reconstruction.
func effect_options() -> Array[EffectOption]:
	var result: Array[EffectOption] = []
	for category in [&"effects", &"trigger_effects", &"state_effects", &"continuous_effects", &"props"]:
		var definitions: Array = get(category)
		for index in definitions.size():
			var definition: RefCounted = definitions[index]
			if category == &"props" and (definition.increment != Enum.p_increment.FLAG or definition.value == 0 or String(definition.name).to_lower() == "wild"): continue
			var option := EffectOption.new()
			option.category = category
			option.definition = definition
			option.name = StringName("effect:%s:%d" % [category, definition.get_instance_id()])
			option.origin_unit = iun
			option.origin_index = index
			for copy in copied_effects:
				if copy.definition == definition:
					option.origin_unit = copy.unit
					option.origin_index = copy.index
			option.caption = EffectText.effect_option_text(option, self)
			result.append(option)
	return result

## Copy's verb appends the selected reusable definition to this unit; SELF is rebound by each future execution, never stored on definitions.
## Origin is retained even when copying another copy; Reset removes all such appended effects and snapshots reconstruct them from printed sources.
## Missing printed resource counters are created at zero so a copied Soul-dependent effect is usable without copying any accumulated counter value.
func add_effect_copy(option: EffectOption) -> void:
	var origin := Match.get_unit(option.origin_unit)
	if origin != null:
		for prop: Prop in origin.printed_state.get("props", []):
			if prop.increment != Enum.p_increment.COUNTER or props.any(func(existing: Prop) -> bool: return existing.name == prop.name): continue
			var resource := Prop.new()
			resource.name = prop.name
			resource.increment = Enum.p_increment.COUNTER
			resource.target = Enum.p_target.UNIT
			props.append(resource)
	var definition := option.definition
	if option.category == &"props":
		var value := Prop.new()
		value.name = definition.name
		value.value = definition.value
		value.increment = definition.increment
		value.target = definition.target
		if props.any(func(prop: Prop) -> bool: return prop.name == value.name): return
		definition = value
	get(option.category).append(definition)
	copied_effects.append({"unit": option.origin_unit, "category": option.category, "index": option.origin_index, "definition": definition})

## Adds Guerra's implicit Walk 1 when this non-temple has no ordinary Walk/Move or Fly action.
## Match.start_local_match() calls this after roster validation; triggered movement does not replace a normal action.
func ensure_implicit_walk() -> void:
	if type == Enum.type.TEMPLE: return
	for effect in effects:
		if effect == null or effect.event != null: continue
		if _consequence_has_movement(effect.consequence): return
	var walk := Collection.movement(1)
	walk.implicit = true
	effects.append(walk)

## Checks one ordinary consequence definition for an authored movement action.
## ensure_implicit_walk() uses this to distinguish an explicit Move 0/Fly from no movement rule.
func _consequence_has_movement(consequence: RefCounted) -> bool:
	if consequence is Effect.ConsequencePhrase:
		var phrase := consequence as Effect.ConsequencePhrase
		return phrase.verb != null and phrase.verb.name in [&"move", &"fly"]
	if consequence is Effect.ConsequenceSequence:
		var sequence := consequence as Effect.ConsequenceSequence
		for phrase in sequence.phrases:
			if phrase != null and phrase.verb != null and phrase.verb.name in [&"move", &"fly"]:
				return true
	return false

## Returns stored physical and magical counters, including temporary shields.
## Called by modifier getters; this is a read-only calculation.
func counter_modifiers() -> Vector2i:
	return Vector2i(
		_counter_value(PHYSICAL_COUNTER) + _counter_value(TEMP_PHYSICAL_COUNTER),
		_counter_value(MAGICAL_COUNTER) + _counter_value(TEMP_MAGICAL_COUNTER))

func consume_temporary_magic() -> void:
	for prop in props:
		if prop != null and prop.name == TEMP_MAGICAL_COUNTER and prop.increment == Enum.p_increment.COUNTER:
			prop.value = 0

## Clears temporary physical protection after Bow/Gore contact, preserving permanent counters.
## CombatResolver calls this only when physical contact succeeds; Titanium blocks do not consume it.
func consume_temporary_physical() -> void:
	for prop in props:
		if prop != null and prop.name == TEMP_PHYSICAL_COUNTER and prop.increment == Enum.p_increment.COUNTER:
			prop.value = 0

func has_flag(key: StringName) -> bool:
	for prop in props:
		if prop != null and prop.name == key and prop.increment == Enum.p_increment.FLAG:
			return prop.value != 0
	return false

## Reads printed/stored and currently granted passive flags as one derived value.
## CombatResolver calls this at action resolution; continuous grants vanish with their source or condition.
func has_effective_flag(key: StringName) -> bool:
	if has_flag(key): return true
	if t_state != Enum.t_state.DEPLOYED or Match.get_unit(iun) != self: return false
	for source in Match.army:
		if source == null or source.t_state != Enum.t_state.DEPLOYED: continue
		for aura in source.continuous_effects:
			if aura == null or not aura.applies_to(source.iun, iun): continue
			for output in aura.contributions:
				if output != null and output.kind == Contribution.Kind.PASSIVE and output.property == key: return true
	return false

## Returns live continuous Bow damage/range adjustments for this deployed recipient.
## Board previews and CombatResolver declaration use this same read-only derivation.
func effective_bow_bonus() -> Vector2i:
	var values := effective_action_values(&"bow", [0, 0])
	return Vector2i(values[0], values[1])

## Adds stored Bow/Cannon/Fire counters, next-Fire Embers, timed grants and live continuous values to printed parameters.
## Action legality, target queries, and resolvers call this with the same family and parameter order.
## Typed modifier grants are excluded here; state_modifiers() derives those independently.
func effective_action_values(action_family: StringName, printed: Array[int]) -> Array[int]:
	var result := printed.duplicate()
	if action_family == &"fire" and not result.is_empty(): result[0] += _counter_value(EMBER_COUNTER) + _counter_value(&"fire_damage")
	if action_family == &"bow" and result.size() >= 2:
		result[0] += bow_damage_bonus
		result[1] += bow_range_bonus
	elif action_family == &"cannon" and result.size() >= 2:
		result[0] += action_counter(CANNON_DAMAGE_COUNTER)
		result[1] += action_counter(CANNON_RANGE_COUNTER)
	if t_state != Enum.t_state.DEPLOYED or Match.get_unit(iun) != self: return result
	for grant in timed_grants:
		if grant == null or grant.kind != TimedGrant.Kind.ACTION_VALUES or grant.action_family != action_family: continue
		for index in mini(result.size(), grant.parameters.size()): result[index] += grant.parameters[index]
	for source in Match.army:
		if source == null or source.t_state != Enum.t_state.DEPLOYED: continue
		for aura in source.continuous_effects:
			if aura == null or not aura.applies_to(source.iun, iun): continue
			for output in aura.contributions:
				if output == null or output.kind != Contribution.Kind.ACTION_VALUE or output.action_family != action_family: continue
				for index in mini(result.size(), output.parameters.size()): result[index] += output.parameters[index]
	return result

## Adds signed permanent Bow counters, creating the named counter properties only when first used.
## Action.upgrade_bow() calls this for Reed Archer; Match snapshots persist the properties through `props`.
func add_bow_counters(damage: int, bow_range: int) -> void:
	if damage != 0: _change_action_counter(BOW_DAMAGE_COUNTER, damage)
	if bow_range != 0: _change_action_counter(BOW_RANGE_COUNTER, bow_range)

## Mara's permanent Cannon grants use stored recipient-bound counters, created only when first awarded; Reset removes acquired counters.
func add_cannon_counters(damage: int, cannon_range: int) -> void:
	if damage != 0: _change_action_counter(CANNON_DAMAGE_COUNTER, damage)
	if cannon_range != 0: _change_action_counter(CANNON_RANGE_COUNTER, cannon_range)

## Returns a supported stored Bow/Cannon action counter, or zero when this card has not acquired it.
## Effective Bow/Cannon reads this during previews and combat capture; the method is read-only.
func action_counter(key: StringName) -> int:
	if key not in [BOW_DAMAGE_COUNTER, BOW_RANGE_COUNTER, CANNON_DAMAGE_COUNTER, CANNON_RANGE_COUNTER]: return 0
	return _counter_value(key)

## Creates or increments a numeric unit counter without changing property identity after creation.
## Bow/Cannon upgrades and resource awards share this identity path; positive Ember awards publish one canonical recipient event.
func _change_action_counter(key: StringName, delta: int) -> void:
	var property := _counter_property(key)
	if property == null:
		for existing in props:
			if existing != null and existing.name == key: return
		property = Prop.new()
		property.name = key
		property.increment = Enum.p_increment.COUNTER
		property.target = Enum.p_target.UNIT
		props.append(property)
	property.value += delta
	publish_ember_gain(key, delta)

## Counter mutations call after one complete delta; Alchemist observes a deployed recipient once for any positive Ember amount.
## Zero, removals, roster construction, and off-board grants do not capture this board trigger.
func publish_ember_gain(key: StringName, delta: int) -> void:
	if key != EMBER_COUNTER or delta <= 0 or Match.get_unit(iun) != self or t_state != Enum.t_state.DEPLOYED: return
	var ref := TargetRef.unit(iun)
	Match.action_event.emit(EffectEvent.new(&"ember_added", ref, ref, {"amount": delta, "key": key}))

## Finds one unambiguous counter by stable key; missing or duplicate keys return null.
## _change_action_counter uses it before creating a property, preserving the property's identity.
func _counter_property(key: StringName) -> Prop:
	var found: Prop
	for prop in props:
		if prop == null or prop.name != key: continue
		if found != null: return null
		found = prop
	return found if found != null and found.increment == Enum.p_increment.COUNTER else null

func _counter_value(key: StringName) -> int:
	var found: Prop
	for prop in props:
		if prop != null and prop.name == key:
			if found != null: return 0 # Duplicate keys are invalid, as in Match.get_property.
			found = prop
	return found.value if found != null and found.increment == Enum.p_increment.COUNTER else 0

## Sums attached rules and eligible deployed-source auras without storing their bonuses.
## Combat/stat callers read live Match state; no fake activation, counter write, or event is created.
## Optional axis restricts aura dependencies: physical-only threshold reads must not evaluate magical-only or Bow grants and recurse into themselves.
## Recipient-bound timed modifier grants participate through their captured End and survive departure of their granting source.
func state_modifiers(axis: int = -1) -> Vector2i:
	var result := Vector2i.ZERO
	if t_state != Enum.t_state.DEPLOYED or Match.get_unit(iun) != self:
		return result
	var ctx := RuleContext.new(TargetRef.unit(iun))
	ctx.subject = ctx.source
	for grant in timed_grants:
		if grant != null and grant.kind == TimedGrant.Kind.MODIFIERS and grant.parameters.size() == 2:
			result += Vector2i(grant.parameters[0], grant.parameters[1])
	for contribution in state_effects:
		if contribution != null: result += contribution.evaluate(ctx)
	for source_id in Match.army.size():
		var source := Match.get_unit(source_id)
		if source == null or source.t_state != Enum.t_state.DEPLOYED: continue
		for aura in source.continuous_effects:
			if aura != null: result += aura.evaluate(source_id, iun, axis)
	result.x += ControlResolver.physical_bonus(self)
	return result

## Hover modifier metadata queries this read-only breakdown using the same counters, state rules, auras and control as modifier getters.
## Counter totals have no historical source attribution; live contributions retain their actual source unit name, including copied-state origins.
## Hover modifier breakdowns identify stored amounts and captured friendly/enemy End independently of live aura eligibility.
func modifier_breakdown(magical: bool = false) -> PackedStringArray:
	var rows := PackedStringArray()
	var axis := 1 if magical else 0
	var permanent := _counter_value(MAGICAL_COUNTER if magical else PHYSICAL_COUNTER)
	var temporary := _counter_value(TEMP_MAGICAL_COUNTER if magical else TEMP_PHYSICAL_COUNTER)
	if permanent != 0: rows.append("%+d permanent counters" % permanent)
	if temporary != 0: rows.append("%+d temporary protection" % temporary)
	for grant in timed_grants:
		if grant != null and grant.kind == TimedGrant.Kind.MODIFIERS and grant.parameters.size() == 2 and grant.parameters[axis] != 0:
			rows.append("%+d until %sEnd" % [grant.parameters[axis], "your " if grant.expires_player == player else "enemy "])
	if t_state == Enum.t_state.DEPLOYED and Match.get_unit(iun) == self:
		var control := 0 if magical else ControlResolver.physical_bonus(self)
		if control != 0: rows.append("%+d control" % control)
		var ctx := RuleContext.new(TargetRef.unit(iun))
		ctx.subject = ctx.source
		for state in state_effects:
			if state == null: continue
			var value := state.evaluate(ctx)[axis]
			if value == 0: continue
			var source_name := name
			for copied in copied_effects:
				if copied.get("definition") == state:
					var original := Match.get_unit(int(copied.get("unit", -1)))
					if original != null: source_name = original.name
			rows.append("%+d %s" % [value, source_name])
		for source: UnitInfo in Match.army:
			if source == null or source.t_state != Enum.t_state.DEPLOYED: continue
			for aura in source.continuous_effects:
				if aura == null: continue
				var value := aura.evaluate(source.iun, iun)[axis]
				if value != 0: rows.append("%+d %s" % [value, source.name])
	if rows.is_empty(): rows.append("No modifiers")
	return rows

## Starts the indexed card effect using this unit as SELF.
## Unused by the local command UI: it submits through RulesRunner; direct callers own action-token accounting.
func eval(ieff: int) -> EffectExecution:
	return effects[ieff].eval(TargetRef.unit(iun))
