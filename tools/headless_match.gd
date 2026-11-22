extends Node

const Harness = preload("res://scripts/runtime/headless_match.gd")
const SnapshotStore = preload("res://scripts/runtime/match_snapshot.gd")
const FORMAT := 3
const ACTIONS := 1
const DEPLOYMENTS := 8
const LIMIT := 4000


## Godot loads this scene without a board. Defer until all autoloads have entered the tree.
func _ready() -> void:
	_run.call_deferred()


## Parses the record/replay CLI, runs the harness, then exits with a useful process status.
func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2 or (args[0] != "--replay" and not args[0].is_valid_int()):
		_fail("Usage: -- SEED TRACE.json or -- --replay TRACE.json")
		return
	var replay := args[0] == "--replay"
	var expected: Dictionary = {}
	if replay:
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(args[1]))
		if not data is Dictionary or data.get("format") != FORMAT or not data.get("decisions") is Array:
			_fail("Invalid or unsupported trace.")
			return
		expected = data
	var seed_text := str(expected.get("seed", "")) if replay else args[0]
	if not seed_text.is_valid_int():
		_fail("Invalid trace seed.")
		return
	var harness := Harness.new()
	if not harness.start(CardCatalogue.starter_army(), ACTIONS, DEPLOYMENTS):
		_fail("Could not start the starter match.")
		return
	var trace := _play(harness, seed_text, expected)
	if trace.is_empty(): return
	if replay:
		if JSON.parse_string(JSON.stringify(trace)) != expected:
			_fail("Replay diverged at the final state or trace metadata.")
			return
	else:
		var file := FileAccess.open(args[1], FileAccess.WRITE)
		if file == null:
			_fail("Could not open the trace for writing.")
			return
		file.store_string(JSON.stringify(trace, "\t") + "\n")
		file.close()
	print("Headless match: %s, winner %d, %d decisions" % [trace.result, trace.winner, trace.decisions.size()])
	get_tree().quit(0 if trace.result == "finished" else 2)


## Plays one seeded match or consumes the recorded options, comparing live decisions as replay progresses.
## Returns a serializable result to _run(); a decision cap and a stalled runner are distinct from a rules victory.
func _play(harness: Harness, seed_text: String, expected: Dictionary) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_text.to_int()
	var decisions: Array[Dictionary] = []
	var recorded: Array = expected.get("decisions", [])
	var result := "limit"
	for index in LIMIT + 1:
		var current := harness.decision()
		if current.is_empty():
			result = "finished" if Match.winner != 0 else "stalled"
			break
		if index == LIMIT: break
		var options: Array = current.options
		var selected: Dictionary
		if expected.is_empty():
			selected = options[rng.randi_range(0, options.size() - 1)]
		else:
			if index >= recorded.size() or not recorded[index] is Dictionary or not recorded[index].get("option") is Dictionary:
				_fail("Missing or invalid replay decision %d." % index)
				return {}
			selected = recorded[index].option
		var entry := {
			"player": current.player,
			"turn": Match.turn_number,
			"phase": int(Match.phase),
			"options_hash": JSON.stringify(options).sha256_text(),
			"option": selected,
		}
		if not expected.is_empty() and JSON.parse_string(JSON.stringify(entry)) != recorded[index]:
			_fail("Replay mismatch at decision %d. Expected %s, got %s." % [
				index, JSON.stringify(recorded[index]), JSON.stringify(entry)])
			return {}
		if not harness.submit(current.player, selected):
			_fail("Rejected option at decision %d: %s." % [index, JSON.stringify(selected)])
			return {}
		decisions.append(entry)
	return {
		"format": FORMAT,
		"seed": seed_text,
		"actions": ACTIONS,
		"deployments": DEPLOYMENTS,
		"army": Match.army.map(func(unit: UnitInfo) -> Array: return [unit.player, unit.uuid]),
		"decisions": decisions,
		"result": result,
		"winner": Match.winner,
		"turn": Match.turn_number,
		"diagnostics": Match.rules_runner.diagnostics.duplicate(),
		"state_hash": JSON.stringify(SnapshotStore._capture_state()).sha256_text(),
	}


## Reports CLI, setup, or replay failures to the invoking process.
func _fail(message: String) -> void:
	printerr(message)
	get_tree().quit(1)
