## Regression scene for saved army restoration and the match result presentation.
extends Node

var failures := 0

## Records each failed assertion while allowing both UI paths to be exercised.
func check(condition: bool, message: String) -> void:
	if condition: return
	failures += 1
	push_error(message)

## Runs menu, AI seat and result fixtures without saving a deck or match.
func _ready() -> void:
	_check_deck_picker()
	await _check_ai_game()
	await _check_result()
	print("Menu flows: %d failures" % failures)
	get_tree().quit(0 if failures == 0 else 1)

## Builds the actual editor and emits the saved picker signal used by a mouse or keyboard selection.
func _check_deck_picker() -> void:
	var menu: Variant = preload("res://scenes/army_menu.tscn").instantiate()
	add_child(menu)
	check(menu.navigation.get_children().any(func(button: Button) -> bool: return button.text == "Against AI"),
		"The landing menu offers Against AI")
	var keys: Array[String] = []
	for unit in CardCatalogue.all_units(1).slice(0, 12):
		keys.append(unit.uuid)
	menu.decks = {"Previous army": {"size": 12.0, "units": keys}}
	menu._navigate("Build")
	menu.saved.select(0)
	menu.saved.item_selected.emit(0)
	check(menu.army_rows.get_child_count() == 12 and menu.selected.size() == 12, "Selecting a legacy deck fills all 12 centre rows")
	check(menu.army_heading.text.contains("12 / 12") and menu.deck_name.text == "Previous army", "Restore updates the army heading and name")
	check(not menu.save_button.disabled and menu.checks[keys[0].trim_suffix("-p1")].button_pressed,
		"Restored selections and catalogue checks agree")
	menu.free()

## Starts the actual AI scene and gives it the turn with a legal human deployment.
func _check_ai_game() -> void:
	var game := preload("res://scenes/ai_game.tscn").instantiate()
	add_child(game)
	var controller := game.get_node("MatchSession") as LocalMatchController
	check(controller.against_ai and not controller.save_snapshot_button.visible and controller.board.local_input_allowed(),
		"AI play starts fresh and gives the first decision to the human")
	var human := controller._ai_choices.decision()
	if not human.is_empty():
		check(controller._ai_choices.submit(1, human.options[0]), "Player 1 can deploy through the authority")
	await get_tree().create_timer(8.0).timeout
	check(Match.players[2].has_deployed and Match.active_player == 1,
		"Player 2 deploys automatically and gives the turn back")
	game.free()

## Defeats the real local hero and checks that finite presentation leads to the visible result.
func _check_result() -> void:
	var game := preload("res://scenes/game.tscn").instantiate()
	add_child(game)
	var controller := game.get_node("MatchSession") as LocalMatchController
	var hero := Match.get_unit(0)
	check(hero != null and hero.type == Enum.type.HERO, "Fixture has Player 1's hero")
	if hero == null:
		game.free()
		return
	hero.t_state = Enum.t_state.DEPLOYED
	hero.ihx = Match.map[0].hex_id
	Match.players[1].selected_hero_id = hero.iun
	controller.board.refresh_board()
	Match.defeat(TargetRef.unit(0), 2)
	check(Match.winner == 2 and not controller.result_screen.visible, "The winner is immediate and presentation waits")
	await get_tree().create_timer(5.0).timeout
	check(controller.result_screen.visible and controller.result_detail.text == "Player 2 wins.", "The final animation gives way to a visible winner")
	game.free()
