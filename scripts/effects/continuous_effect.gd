## A reusable “have” definition that exports typed live contributions to selected recipients.
class_name ContinuousEffect
extends RefCounted

var recipients: Selector
var source_condition: Condition
var recipient_condition: Condition
var physical: int
var magical: int
var label: String
## Typed live outputs; legacy modifier fields remain a compatibility view.
var contributions: Array[Contribution] = []

## Defines an aura; Match evaluates it from deployed sources during recipient modifier reads.
## The selector and conditions are read-only definitions and hold no per-read state.
func _init(recipient_query: Selector, physical_bonus: int = 0, magical_bonus: int = 0,
		source_when: Condition = null, recipient_when: Condition = null, description: String = "") -> void:
	recipients = recipient_query
	physical = physical_bonus
	magical = magical_bonus
	source_condition = source_when
	recipient_condition = recipient_when
	label = description
	if physical_bonus != 0 or magical_bonus != 0:
		contributions.append(Contribution.modifiers(physical_bonus, magical_bonus))

## Creates a card-authored “have” rule: each matching recipient receives these live outputs.
## UnitInfo derives the values on demand; recipient identity is rebound for each query.
static func have(recipient_query: Selector, outputs: Array[Contribution],
		source_when: Condition = null, recipient_when: Condition = null, description: String = "") -> ContinuousEffect:
	var result := ContinuousEffect.new(recipient_query, 0, 0, source_when, recipient_when, description)
	result.contributions = outputs.duplicate()
	return result

## Creates a “while” rule applying its outputs to SELF while the condition is true.
## UnitInfo.state_modifiers() supplies SELF and evaluates this read-only definition.
static func while_self(condition: Condition, outputs: Array[Contribution], description: String = "") -> ContinuousEffect:
	return have(Selectors.Self.new(), outputs, condition, null, description)

## Returns this source's contribution for one stable unit ID, or zero when ineligible.
## UnitInfo can request one axis; unrelated outputs are filtered before predicates, so magical/Bow rewards cannot recurse into physical-threshold queries.
func evaluate(source_id: int, recipient_id: int, axis: int = -1) -> Vector2i:
	var relevant: Array[Contribution] = []
	for output in contributions:
		if output == null or output.kind != Contribution.Kind.MODIFIER: continue
		if axis == 0 and output.physical == 0: continue
		if axis == 1 and output.magical == 0: continue
		relevant.append(output)
	if relevant.is_empty() or not applies_to(source_id, recipient_id): return Vector2i.ZERO
	var result := Vector2i.ZERO
	for output in relevant: result += Vector2i(output.physical, output.magical)
	return result

## Returns whether this live source contributes to the requested recipient under current bindings.
## UnitInfo, action-value reads, and RulesRunner use this without mutating Match.
func applies_to(source_id: int, recipient_id: int) -> bool:
	var source_unit := Match.get_unit(source_id)
	var recipient_unit := Match.get_unit(recipient_id)
	if source_unit == null or recipient_unit == null: return false
	if source_unit.t_state != Enum.t_state.DEPLOYED or recipient_unit.t_state != Enum.t_state.DEPLOYED:
		return false
	var ctx := RuleContext.new(TargetRef.unit(source_id))
	ctx.recipient = TargetRef.unit(source_id)
	if source_condition != null and not source_condition.test(ctx): return false
	if not ctx.error.is_empty(): return false
	var resolved := TargetResolver.resolve(recipients, TargetRef.Kind.UNIT, ctx)
	if not resolved.error.is_empty() or not TargetResolver.contains(resolved.candidates, TargetRef.unit(recipient_id)):
		return false
	ctx.recipient = TargetRef.unit(recipient_id)
	if recipient_condition != null and not recipient_condition.test(ctx): return false
	return ctx.error.is_empty()
