## Read-only predicate used by continuous state rules.
## StateModifier calls test() while deriving modifiers; implementations never mutate Match.
class_name Condition
extends RefCounted

## Evaluates this condition against the source bound to the read-only phrase context.
## UnitInfo.state_modifiers() supplies that context; no effect is started or paused.
func test(_ctx: RuleContext) -> bool:
	return false

## Matches a pending Bash involving the current recipient, with optional opponent/hero constraints.
## Bashing conditions call this during live state reads without changing encounters.
func _matches_bash(ctx: RuleContext, require_enemy: bool = false, require_enemy_hero: bool = false) -> bool:
	if ctx == null or ctx.recipient == null or ctx.recipient.kind != TargetRef.Kind.UNIT: return false
	var unit := Match.get_unit(ctx.recipient.id)
	if unit == null or unit.t_state != Enum.t_state.DEPLOYED: return false
	for bash in Match.bashes:
		if bash == null or bash.resolved: continue
		var other_id := bash.defender_id if bash.attacker_id == unit.iun else bash.attacker_id if bash.defender_id == unit.iun else -1
		var other := Match.get_unit(other_id)
		if other == null or other.t_state != Enum.t_state.DEPLOYED: continue
		if require_enemy and other.player == unit.player: continue
		if require_enemy_hero and (other.player == unit.player or other.type != Enum.type.HERO): continue
		return true
	return false

## True when the bound recipient is alive, deployed, and below printed maximum life.
## StateModifier defaults recipient to SELF; aura definitions can test each recipient independently.
class Wounded extends Condition:
	## Evaluates Wounded against supplied read-only bindings; state queries and trigger capture call this.
	func test(ctx: RuleContext) -> bool:
		if ctx == null or ctx.recipient == null: return false
		var recipient := ctx.recipient
		if recipient == null or recipient.kind != TargetRef.Kind.UNIT: return false
		var unit := Match.get_unit(recipient.id)
		return unit != null and unit.t_state == Enum.t_state.DEPLOYED \
			and unit.actual_life > 0 and unit.actual_life < unit.max_life

## True while the recipient participates in an unresolved Bash against an opposing unit.
## ContinuousEffect evaluates this during CombatResolver's modifier reads; it is read-only.
class BashingEnemy extends Condition:
	## Checks current Bash identities; no Bash is created, resolved, or removed by this query.
	func test(ctx: RuleContext) -> bool:
		return _matches_bash(ctx, true)

## True while the recipient participates in any unresolved Bash, regardless of ownership.
## UnitInfo evaluates this for continuous “while bashing” contributions.
class Bashing extends Condition:
	## Checks pending encounter identity without creating or resolving a Bash.
	func test(ctx: RuleContext) -> bool:
		return _matches_bash(ctx)

## True while the recipient is bashing an opposing Hero.
## Crown Breaker style continuous modifiers query this from UnitInfo.state_modifiers().
class BashingEnemyHero extends Condition:
	## Requires an opposing deployed Hero in the recipient's unresolved Bash.
	func test(ctx: RuleContext) -> bool:
		return _matches_bash(ctx, true, true)

## Tests whether the recipient is currently active, for “while active/inactive” rules.
class Active extends Condition:
	var expected: bool
	## Stores the requested state; the context supplies the current recipient at evaluation time.
	func _init(is_active: bool = true) -> void:
		expected = is_active
	## Reads live activity without changing the unit or its Stun counters.
	func test(ctx: RuleContext) -> bool:
		if ctx == null or ctx.recipient == null or ctx.recipient.kind != TargetRef.Kind.UNIT: return false
		var unit := Match.get_unit(ctx.recipient.id)
		return unit != null and unit.t_state == Enum.t_state.DEPLOYED and unit.active == expected

## Reusable resource threshold for normal actions whose explicit counter cost is bundled with activity.
class CounterAtLeast extends Condition:
	var key: StringName
	var amount: int
	## Authors bind a named unit counter and threshold; the source/recipient identity remains in the query context.
	func _init(counter: StringName, minimum: int) -> void:
		key = counter
		amount = minimum
	## Runner availability and activation validation read the same counter without payment or mutation.
	func test(ctx: RuleContext) -> bool:
		if ctx == null or ctx.source == null: return false
		var prop := Match.get_property(TargetRef.property(ctx.source, key))
		return prop != null and prop.increment == Enum.p_increment.COUNTER and prop.value >= amount

## Tests whether the recipient is deployed, for explicit source/recipient scope rules.
## Life-increase triggers can require one positive captured component without reading the unit's later health.
class EventPositive extends Condition:
	var key: StringName
	## Authors specify actual or maximum; capture evaluates the historical scalar once for the trigger occurrence.
	func _init(field: StringName) -> void:
		key = field
	## Only strictly positive event deltas qualify; reductions and clamped heals never satisfy the condition.
	func test(ctx: RuleContext) -> bool:
		return ctx != null and ctx.triggering_event != null and int(ctx.triggering_event.data.get(key, 0)) > 0

class Deployed extends Condition:
	## Reads the current unit lifetime state supplied by the continuous-rule context.
	func test(ctx: RuleContext) -> bool:
		if ctx == null or ctx.recipient == null or ctx.recipient.kind != TargetRef.Kind.UNIT: return false
		var unit := Match.get_unit(ctx.recipient.id)
		return unit != null and unit.t_state == Enum.t_state.DEPLOYED

## Tests for stored temporary physical or magical protection counters.
## “While shielded” rules use this instead of mistaking unrelated modifiers for Shields.
class Shielded extends Condition:
	## Reads temporary protection counters without consuming them or emitting contact events.
	func test(ctx: RuleContext) -> bool:
		if ctx == null or ctx.recipient == null or ctx.recipient.kind != TargetRef.Kind.UNIT: return false
		var unit := Match.get_unit(ctx.recipient.id)
		if unit == null or unit.t_state != Enum.t_state.DEPLOYED: return false
		return unit._counter_value(UnitInfo.TEMP_PHYSICAL_COUNTER) > 0 \
			or unit._counter_value(UnitInfo.TEMP_MAGICAL_COUNTER) > 0

## Combines predicates with logical AND and preserves the first false result.
## Card authors use it to build one source condition without mutating state.
class All extends Condition:
	var conditions: Array[Condition]
	## Binds reusable All operands; card authors supply these once, without runtime state.
	func _init(values: Array[Condition]) -> void:
		conditions = values.duplicate()
	## Evaluates All against supplied read-only bindings; state queries and trigger capture call this.
	func test(ctx: RuleContext) -> bool:
		if conditions.is_empty(): return false
		for condition in conditions:
			if condition == null or not condition.test(ctx): return false
		return true

## Combines predicates with logical OR; an empty list has no match.
## Use for card rules with alternative observable states.
class AnyOf extends Condition:
	var conditions: Array[Condition]
	## Binds reusable AnyOf operands; card authors supply these once, without runtime state.
	func _init(values: Array[Condition]) -> void:
		conditions = values.duplicate()
	## Evaluates AnyOf against supplied read-only bindings; state queries and trigger capture call this.
	func test(ctx: RuleContext) -> bool:
		for condition in conditions:
			if condition != null and condition.test(ctx): return true
		return false

## Negates one read-only condition; null is treated as an invalid false predicate.
## White Wolf style inactive-source rules can extend this without counter writes.
class Not extends Condition:
	var condition: Condition
	## Binds reusable Not operands; card authors supply these once, without runtime state.
	func _init(value: Condition) -> void:
		condition = value
	## Evaluates Not against supplied read-only bindings; state queries and trigger capture call this.
	func test(ctx: RuleContext) -> bool:
		if condition == null:
			ctx.error = "NOT requires a condition."
			return false
		var result := condition.test(ctx)
		return ctx.error.is_empty() and not result

## Tests selector membership as ANY, NONE or nonempty universal membership in a filter.
## StateModifier and triggered definitions use the same domain-checked resolution path.
class Matches extends Condition:
	enum Mode { ANY, NONE, ALL }
	var selector: Selector
	var predicate: Selector
	var mode: Mode
	## Copies query definitions only; each test supplies live or explicitly historical bindings.
	func _init(query: Selector, quantifier: Mode = Mode.ANY, filter: Selector = null) -> void:
		selector = query
		mode = quantifier
		predicate = filter
	## Resolves read-only candidates; empty ALL is false and errors cannot become true under NOT.
	func test(ctx: RuleContext) -> bool:
		if selector == null:
			ctx.error = "A selector condition requires a query."
			return false
		var kind := selector.output_kind(ctx)
		var result := TargetResolver.resolve(selector, kind, ctx)
		if not result.error.is_empty():
			ctx.error = result.error
			return false
		if mode == Mode.NONE: return result.candidates.is_empty()
		if mode == Mode.ANY: return not result.candidates.is_empty()
		if result.candidates.is_empty(): return false
		if predicate == null:
			ctx.error = "Nonempty ALL requires a predicate selector."
			return false
		if predicate.output_kind(ctx) != kind:
			ctx.error = "Condition ALL requires same-domain selectors."
			return false
		var matching := TargetResolver.resolve(predicate, kind, ctx)
		if not matching.error.is_empty():
			ctx.error = matching.error
			return false
		for candidate in result.candidates:
			if not TargetResolver.contains(matching.candidates, candidate): return false
		return true

## Reads a singular counter/flag and compares its numeric value without changing it.
## Effect availability and trigger conditions use explicit PropertyOf selectors.
class Compare extends Condition:
	enum Op { EQ, LT, LE, GT, GE }
	var selector: Selector
	var operation: Op
	var value: int
	## Binds a reusable property query, comparison and fixed threshold for card authors.
	func _init(query: Selector, op: Op, threshold: int) -> void:
		selector = query
		operation = op
		value = threshold
	## Requires one property; malformed/multi-property comparisons report a definition error.
	func test(ctx: RuleContext) -> bool:
		var result := TargetResolver.resolve(selector, TargetRef.Kind.PROPERTY, ctx)
		if not result.error.is_empty():
			ctx.error = result.error
			return false
		if result.candidates.is_empty(): return false
		if result.candidates.size() != 1:
			ctx.error = "Comparison requires exactly one property."
			return false
		var actual: int = Match.get_property(result.candidates[0]).value
		match operation:
			Op.EQ: return actual == value
			Op.LT: return actual < value
			Op.LE: return actual <= value
			Op.GT: return actual > value
			Op.GE: return actual >= value
		return false

## Compares explicitly captured history; missing fields never fall back to live state.
## Movement/death card definitions use this with EffectEvent.data keys.
class EventFact extends Condition:
	var key: StringName
	var expected: Variant
	## Binds the historical field and value; no event is retained by the definition.
	func _init(field: StringName, value: Variant) -> void:
		key = field
		expected = value
	## Reads the occurrence snapshot supplied by RulesRunner's capture context.
	func test(ctx: RuleContext) -> bool:
		if ctx.triggering_event == null:
			ctx.error = "Missing historical event fact: %s" % key
			return false
		var event_details := ctx.triggering_event.data
		var field_name := String(key)
		if not event_details.has(key) and not event_details.has(field_name):
			ctx.error = "Missing historical event fact: %s" % key
			return false
		return event_details.get(key, event_details.get(field_name)) == expected
