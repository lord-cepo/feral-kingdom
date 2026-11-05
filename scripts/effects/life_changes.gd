## Authoritative positive life-change occurrences shared by healing, upgrades and Reset; UI never creates these events.
class_name LifeChanges
extends RefCounted

## Actions call this after mutation with prior values; positive components are captured independently, ignoring wounds and clamped non-gains.
static func publish(unit: UnitInfo, previous: Vector2i, source: TargetRef) -> void:
	var actual := maxi(0, unit.actual_life - previous.x)
	var maximum := maxi(0, unit.max_life - previous.y)
	if actual == 0 and maximum == 0: return
	Match.action_event.emit(EffectEvent.new(&"life_increase", TargetRef.unit(unit.iun), TargetRef.unit(unit.iun),
		{"actual": actual, "maximum": maximum, "cause": source}))
