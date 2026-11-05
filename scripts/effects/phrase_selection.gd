## Compatibility controller for selecting a single phrase without paying a cost.
class_name PhraseSelection
extends PhraseExecution

var _owned_execution: EffectExecution

func begin_standalone(definition: Effect.Phrase, source: TargetRef) -> void:
	_owned_execution = EffectExecution.new(null, source)
	begin(definition, _owned_execution)
