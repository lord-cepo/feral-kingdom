class_name BowAttack
extends RefCounted

var owner := 0
var source_id := -1
var origin_hex := -1
var target_hex := -1
var target_unit_id := -1
var amount := 0
var pierce := false
var instant := false
var resolved := false
var outcome: Dictionary = {}
