## Typed completed-result binding for a later phrase; reusable verbs never hold a chosen donor, counter key or amount.
class_name RuleBinding
extends RefCounted

enum Field { HOST_ID, PROPERTY_KEY, AMOUNT, UNIT_ID, HEX_ID }
var result_name: StringName
var field: Field

## Courier's transfer definition names a completed counter-choice step and one explicit value to read from it.
func _init(step: StringName, value: Field) -> void:
	result_name = step
	field = value

## Verb.bound_to reads frozen PROPERTY/UNIT choices or Summoner's pre-commit hex; missing results never substitute a live candidate.
func evaluate(ctx: RuleContext) -> Variant:
	if field in [Field.UNIT_ID, Field.HEX_ID]:
		if ctx == null: return -1
		var selected: Array = ctx.completed_results.get(result_name, {}).get("targets", [])
		if selected.size() != 1 or selected[0].kind != TargetRef.Kind.UNIT: return -1
		if field == Field.HEX_ID: return int(ctx.completed_results[result_name].get("target_hexes", {}).get(selected[0].id, -1))
		return selected[0].id
	if ctx == null: return 0 if field == Field.AMOUNT else -1 if field == Field.HOST_ID else &""
	var result: Dictionary = ctx.completed_results.get(result_name, {})
	if field == Field.AMOUNT: return int(result.get("amount", 0))
	var targets: Array = result.get("targets", [])
	if targets.size() != 1 or targets[0].kind != TargetRef.Kind.PROPERTY:
		return -1 if field == Field.HOST_ID else &""
	return targets[0].host.id if field == Field.HOST_ID else targets[0].property_key
