class_name CannonAttack
extends RefCounted

var owner := 0
var source_id := -1
var target_hex := -1
var amount := 0
var pierce := false
var instant := false
var explosion := false
## Captured Bomb center for the board's lit marker; ordinary Cannon shots retain -1.
var bomb_hex := -1
var chain_owner := 0
var resolved := false
var outcome: Dictionary = {}
