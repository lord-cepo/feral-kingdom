## Reusable numeric query bound to a phrase execution, never mutable activation state on a Verb definition.
class_name RuleNumber
extends RefCounted

var event_key: StringName
var symbol: String
enum SourceKind { EVENT, CHOICE, PAID_AMOUNT }
var basis := SourceKind.EVENT
var result_name: StringName

## Porcupine's decrement payment requests a positive amount after its counter PROPERTY identity has been chosen.
static func choice() -> RuleNumber:
	var result := RuleNumber.new(&"", "X")
	result.basis = SourceKind.CHOICE
	return result

## Consequences read the frozen amount of a paid cost, including after cost-trigger followups change live resources.
static func paid_amount(cost_index: int) -> RuleNumber:
	var result := RuleNumber.new(&"", "X")
	result.basis = SourceKind.PAID_AMOUNT
	result.result_name = StringName("cost_%d" % cost_index)
	return result

## Authors choose a captured positive life-increase field and a printed symbol; PhraseExecution binds its event later.
func _init(key: StringName, printed_symbol: String = "X") -> void:
	event_key = key
	symbol = printed_symbol

## Verb.bound_to reads event history, this phrase's choice, or a completed payment; previews use one for an unchosen positive X.
## Paid amounts never read a counter's later balance, so consequence X survives cost followups and overlapping activations.
func evaluate(ctx: RuleContext) -> int:
	if ctx == null: return 0
	if basis == SourceKind.CHOICE: return ctx.chosen_amount if ctx.chosen_amount > 0 else 1
	if basis == SourceKind.PAID_AMOUNT:
		return maxi(0, int(ctx.completed_results.get(result_name, {}).get("amount", 1 if ctx.preview_numbers else 0)))
	if ctx.triggering_event == null: return 0
	return maxi(0, int(ctx.triggering_event.data.get(event_key, 0)))
