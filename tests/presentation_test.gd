## Starts the real game scene and exercises committed movement plus a new verb's automatic cosmetic replay.
extends Node

var checks := 0
var failures := 0

## Regression assertions report failures through both the Godot log and the scene's final exit status.
func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

## The test scene entry point checks the current Save/Reset HUD, previous-turn history, single-pass replay and no rules mutation.
## A previously unknown verb emits normal action events to prove discovery does not depend on an attack-name allowlist.
## Optional --capture saves the real rendered hover/replay view when launched with a graphical renderer.
## Waits for the finite action/phase barrier before inspecting previous-turn history; costs can schedule their consequences after sitting finishes.
func _ready() -> void:
	var game := preload("res://scenes/game.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	var board := game.get_node("Board") as GuerraBoard
	var controller := game.get_node("MatchSession") as LocalMatchController
	check(board != null and board.hex_grid.get_child_count() == Match.map.size(), "Real game creates all board cells")
	check(controller.save_snapshot_button != null and controller.reset_match_button != null and controller.hover_panel != null, "Real game creates its parchment HUD controls and hover host")
	check(board.get_node("Ambience").banners.size() == 2, "Both turn banner clips load")
	var unit := Match.army[0]
	unit.t_state = Enum.t_state.DEPLOYED
	unit.ihx = 0
	unit.active = true
	Match.state_changed.emit()
	var movement: Effect
	for effect: Effect in unit.effects:
		if effect.consequence.verb.name == &"move": movement = effect
	check(movement != null, "Hero receives rulebook implicit walking")
	check(Match.rules_runner.submit(movement, TargetRef.unit(unit.iun), true), "Managed walk opens target selection")
	var chooser := Match.rules_runner.active.current
	check(not chooser.candidates.is_empty(), "Walk has legal targets")
	if chooser.candidates.is_empty():
		get_tree().quit(1)
		return
	var destination := chooser.candidates[0]
	check(chooser.choose(destination), "Managed walk commits and advances the turn")
	await wait_until(func() -> bool: return board.action_history.has(unit.iun) and not Match.rules_runner.busy(), "Walk and phase animations finish")
	check(board.action_history.has(unit.iun), "Committed walk creates previous-turn history")
	controller._on_hex_hovered(unit.ihx)
	check(controller.hover_panel.visible, "Hover details appear for the moved troop")
	check(controller.hover_frame_style != null, "Hover wood frame loads and builds its nine-slice style")
	check(controller.hover_content.get_child_count() == 2, "Stun cost appears in a separate counter panel")
	check(board._offer_action_replay(unit.ihx), "Click on previous-turn walker starts replay")
	await get_tree().process_frame
	if board.action_replays.is_empty():
		get_tree().quit(1)
		return
	var replay: Node = board.action_replays[0]
	var before_hex := unit.ihx
	var before_turn := Match.turn_number
	replay._process(0.4)
	check(unit.ihx == before_hex and Match.turn_number == before_turn, "Replay does not mutate position or turn")
	if "--capture" in OS.get_cmdline_user_args():
		await get_tree().create_timer(0.3).timeout
		await RenderingServer.frame_post_draw
		var image := get_viewport().get_texture().get_image()
		check(image != null and not image.is_empty(), "Real renderer produces a visible game frame")
		if image != null: image.save_png("res://.godot/presentation-preview.png")
	replay._process(2.0)
	check(replay.is_queued_for_deletion(), "Replay frees after one pass and its final fade")
	board._clear_action_replays()
	Match.active_player = unit.player
	Match.phase = Match.Phase.ACTION
	Match.players[unit.player].actions_remaining = 1
	unit.active = true
	var verb := Effect.Verb.new(&"presentation_probe", _probe_action, Callable(), TargetRef.Kind.UNIT, TargetRef.Kind.UNIT)
	var phrase := Effect.ConsequencePhrase.new(Selectors.Self.new(), verb, Selectors.Self.new())
	var effect := Collection.with_action_policy(phrase, true, false)
	check(Match.rules_runner.submit(effect, TargetRef.unit(unit.iun), true), "Unregistered verb opens normally")
	check(Match.rules_runner.active.current.choose(TargetRef.unit(unit.iun)), "Unregistered verb commits normally")
	await wait_until(func() -> bool: return not Match.rules_runner.busy(), "Probe action and phase animations finish")
	check(board.action_history[unit.iun].actions.size() == 1, "Target/resolved events are deduplicated")
	check(board._offer_action_replay(unit.ihx), "Unregistered verb gets automatic replay")
	await get_tree().process_frame
	replay = board.action_replays[0]
	check(replay.icon != null and replay.icon.get_child_count() > 0 and replay.icon.get_child(0) is Label, "Missing artwork gets a readable fallback")
	Match.turn_number += 1
	replay._process(0.01)
	check(replay.is_queued_for_deletion(), "Next turn stops replay")
	game.queue_free()
	await get_tree().process_frame
	print("Presentation integration: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)

## Waits a bounded time for actual graphical continuations; failures return to assertions rather than hanging a test process.
func wait_until(predicate: Callable, message: String) -> void:
	var deadline := Time.get_ticks_msec() + 12000
	while not predicate.call() and Time.get_ticks_msec() < deadline:
		await get_tree().create_timer(0.05).timeout
	check(predicate.call(), message)

## The new test-only verb emits target/resolved notifications without mutating the model, exercising automatic capture/deduplication.
func _probe_action(subject: TargetRef, target: TargetRef) -> bool:
	Match.action_event.emit(EffectEvent.new(&"presentation_probe", subject, target, {}, &"target"))
	Match.action_event.emit(EffectEvent.new(&"presentation_probe", subject, target, {}, &"resolved"))
	return true
