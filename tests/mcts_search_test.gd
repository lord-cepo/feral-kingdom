extends Node

const Search = preload("res://scripts/runtime/mcts.gd")
var _root := {"player": 1, "options": [{"id": 0}, {"id": 1}, {"id": 2}, {"id": 3}]}
var _last := -1
var _tried: Array[int] = []


## Runs synthetic search positions without changing the Match autoload.
func _ready() -> void:
	var search := Search.new()
	var order: Array[int] = [2, 1, 0, 3]
	var narrow := search.search(_root, 1, _restore, _advance, _winner, Callable(), order)
	if narrow.explored != [2] or narrow.index != 2:
		push_error("The first simulation must follow the tactical ranking.")
		get_tree().quit(1)
		return
	_tried.clear()
	var wide := search.search(_root, 32, _restore, _advance, _winner, Callable(), order)
	if _tried.slice(0, 2) != [2, 1] or wide.explored.size() != 4 or wide.index != 3:
		push_error("Widening must admit every option and let the initially last-ranked winner prevail.")
		get_tree().quit(1)
		return
	var estimated := search.search(_root, 1, _restore, _advance, func() -> int: return 0,
		Callable(), order, Callable(), func() -> float: return -0.25, 0)
	if estimated.completed != 0 or estimated.estimated != 1 or estimated.visits[2] != 1:
		push_error("A truncated rollout should back up its estimate separately from terminal wins.")
		get_tree().quit(1)
		return
	get_tree().quit()


## Recreates the same synthetic root on every simulation.
func _restore() -> Dictionary:
	_last = -1
	return _root


## Records each root choice, then ends this one-decision game.
func _advance(option: Dictionary) -> Dictionary:
	_last = option.id
	_tried.append(_last)
	return {}


## Only the last-ranked option gives player one a win.
func _winner() -> int:
	return 1 if _last == 3 else 2
