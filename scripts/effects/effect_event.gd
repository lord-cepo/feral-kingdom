class_name EffectEvent
extends RefCounted

var _action: StringName
var action: StringName:
	get: return _action
var _subject: TargetRef
var subject: TargetRef:
	get: return _copy_ref(_subject)
var _target: TargetRef
var target: TargetRef:
	get: return _copy_ref(_target)
var _data: Dictionary
var data: Dictionary:
	get: return _copy_details(_data)
var _stage: StringName
var stage: StringName:
	get: return _stage
## Unique per committed occurrence; RulesRunner uses this to ignore duplicate delivery.
var _occurrence_id: int
var occurrence_id: int:
	get: return _occurrence_id
var _turn_number: int
var turn_number: int:
	get: return _turn_number
var _phase: int
var phase: int:
	get: return _phase
var _controller: int
var controller: int:
	get: return _controller

static var _next_occurrence_id := 1

## Captures event identities, actor ownership, and the current Match boundary.
## Match, Action, and CombatResolver create these at action/resolution boundaries;
## details are deep-copied so later caller edits do not rewrite event history.
func _init(action_name: StringName, actor: TargetRef, recipient: TargetRef, details: Dictionary = {},
		event_stage: StringName = &"resolved", event_controller: int = 0) -> void:
	_action = action_name
	_subject = _copy_ref(actor)
	_target = _copy_ref(recipient)
	_data = _copy_details(details)
	_stage = event_stage
	_occurrence_id = _next_occurrence_id
	_next_occurrence_id += 1
	_turn_number = Match.turn_number
	_phase = Match.phase
	_controller = event_controller if event_controller in [1, 2] else _controller_for(actor)

## Resolves the event controller from its actor so opponent-controlled trigger actions
## retain the right ownership while Match.active_player remains the response-turn player.
static func _controller_for(actor: TargetRef) -> int:
	if actor == null: return Match.active_player
	if actor.kind == TargetRef.Kind.UNIT: return Match.owner_of(actor)
	if actor.kind == TargetRef.Kind.PLAYER and actor.id in [1, 2]: return actor.id
	return Match.active_player

## Rejects malformed occurrence records before RulesRunner scans trigger definitions.
## RulesRunner.capture_event() calls this once per occurrence; participant identities
## may describe units that have just left play, so they are not resolved to live objects.
func validation_error() -> String:
	if _action.is_empty(): return "An event must name its action."
	if _stage not in [&"target", &"resolved"]: return "An event stage must be target or resolved."
	if _subject == null or _target == null: return "An event must capture both participants."
	if _controller not in [1, 2]: return "An event controller must be player 1 or 2."
	return ""

## Reports whether this occurrence represents a successful, non-cancelled event.
## EventPhrase.matches() excludes cancelled resolutions while allowing successful misses.
func succeeded() -> bool:
	if _data.has("success") and not bool(_data["success"]): return false
	return not bool(_data.get("canceled", false)) and not bool(_data.get("cancelled", false))

## Copies a stable entity/property identity so the event cannot retain mutable host data.
## The constructor and public participant getters use this; Match remains authoritative.
static func _copy_ref(ref: TargetRef) -> TargetRef:
	if ref == null: return null
	match ref.kind:
		TargetRef.Kind.UNIT: return TargetRef.unit(ref.id)
		TargetRef.Kind.HEX: return TargetRef.hex(ref.id)
		TargetRef.Kind.PLAYER: return TargetRef.player(ref.id)
		TargetRef.Kind.MATCH: return TargetRef.match_host()
		TargetRef.Kind.PROPERTY: return TargetRef.property(_copy_ref(ref.host), ref.property_key)
	return null

## Copies nested historical containers and reference identities on capture and public reads.
## The constructor/data getter use this because Dictionary.duplicate does not clone Objects.
static func _copy_details(value: Variant) -> Variant:
	if value is TargetRef: return _copy_ref(value)
	if value is Dictionary:
		var result: Dictionary = {}
		for key in value: result[key] = _copy_details(value[key])
		return result
	if value is Array:
		var result: Array = []
		for item in value: result.append(_copy_details(item))
		return result
	if value is Object:
		push_error("Event history must contain values or TargetRef identities, not live objects.")
		return null
	return value
