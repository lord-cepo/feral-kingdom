## Read-only bindings consumed by selectors and conditions; owns no activation.
## PhraseExecution extends this view; state queries construct it directly.
class_name RuleContext
extends RefCounted

var source: TargetRef
var subject: TargetRef
## Recipient is the current unit whose effective state is being queried; it is distinct from aura SELF.
var recipient: TargetRef
var triggering_event: EffectEvent
var completed_results: Dictionary = {}
var error := ""
var query_verb: Effect.Verb
## One phrase's confirmed numeric choice; -1 means preview, and definitions never retain this value.
var chosen_amount := -1
## Availability and selection-only previews use a positive minimum before a variable payment has been selected; commits never invent paid amounts.
var preview_numbers := false

## Binds SELF and optional history for state reads and runner event matching.
## Recipient defaults to SELF; aura queries may rebind it without starting an effect or mutating Match.
func _init(source_ref: TargetRef = null, event: EffectEvent = null) -> void:
	source = source_ref
	recipient = source_ref
	triggering_event = event
