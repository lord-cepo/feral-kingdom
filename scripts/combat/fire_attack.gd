## One committed Fire. Damage, owner and coordinates are captured at declaration.
class_name FireAttack
extends RefCounted

var source_id: int
var owner: int
var origin_hex: int
var target_hex: int
var target_unit_id := -1
var amount: int
var pierce: bool
var instant: bool
var declared_turn: int
var resolved := false
var outcome: Dictionary = {}

func details() -> Dictionary:
	return {
		"amount": amount, "pierce": pierce, "instant": instant,
		"origin_hex": origin_hex, "target_hex": target_hex,
		"target_unit_id": target_unit_id, "declared_turn": declared_turn}
