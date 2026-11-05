class_name Player
extends RefCounted

var props: Array[Prop] = []
var name: String = ""
var id: int = 0
## Current format allowances and remaining values, initialized by Match.start_local_match().
var action_allowance: int = 1
## Spending is tracked separately from live allowance, so Bash entry/exit cannot refill a previously spent bonus action.
var base_actions_remaining: int = 1
var actions_remaining: int:
	get: return maxi(0, base_actions_remaining + SynergyRules.player_action_bonus(id))
	set(value): base_actions_remaining = value - SynergyRules.player_action_bonus(id)
var deployment_allowance: int = 3
var deployments_remaining: int = 3
var has_deployed: bool = false
## First hero deployed from the full catalogue; other hero alternatives stay unavailable while this identity may still Return/redeploy.
var selected_hero_id: int = -1
## Pending one-shot action grants are consumed at this player's next Start, separately from the recurring format allowance.
var next_turn_actions: int = 0
