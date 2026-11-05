## A concrete expiring action-value or modifier contribution attached to one recipient unit.
class_name TimedGrant
extends RefCounted

var id := 0
enum Kind { ACTION_VALUES, MODIFIERS }
var kind: Kind = Kind.ACTION_VALUES
var source: TargetRef
var action_family: StringName = &""
var parameters: Array[int] = []
var expires_player := 0
var expires_turn := -1

## Captures a grant through the current player's End step; Match removes it before the next Start.
## The caller supplies stable IDs and a copy of the action parameter deltas.
static func action_values(grant_id: int, granting_source: TargetRef, family: StringName,
		values: Array[int], player_id: int, turn_id: int) -> TimedGrant:
	var grant := TimedGrant.new()
	grant.id = grant_id
	grant.source = granting_source
	grant.action_family = family
	grant.parameters = values.duplicate()
	grant.expires_player = player_id
	grant.expires_turn = turn_id
	return grant

## Modifier verbs attach a physical/magical pair through the same captured End cleanup used by action grants.
static func modifiers(grant_id: int, granting_source: TargetRef, values: Array[int], player_id: int, turn_id: int) -> TimedGrant:
	var grant := action_values(grant_id, granting_source, &"modifiers", values, player_id, turn_id)
	grant.kind = Kind.MODIFIERS
	return grant

## Says whether this grant has reached its captured player's cleanup boundary.
## Match._next_turn calls it after End triggers and before advancing the player.
func expires_after(player_id: int, turn_id: int) -> bool:
	return expires_player == player_id and expires_turn == turn_id
