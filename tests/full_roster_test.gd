## Full-catalogue availability and first-deployed hero choice regressions; run only on an explicit TEST request.
extends Node

var failures := 0

## Records each behavioral failure without preventing remaining roster and ownership checks.
func check(value: bool, message: String) -> void:
	if value: return
	failures += 1
	push_error(message)

## Finds one stable roster identity by its exact per-owner catalogue UUID.
func find(unit_id: String, owner: int) -> UnitInfo:
	for unit in Match.army:
		if unit.uuid == "%s-p%d" % [unit_id, owner]: return unit
	return null

## Verifies complete inventories and every authored rule's contracts before testing hero choice, Return and snapshot behavior.
func _ready() -> void:
	Match.reset_combat()
	Match.rules_runner.trigger_acknowledgements_enabled = false
	Match.rules_runner.presentation_busy_query = Callable()
	Match.map.clear()
	Match.map.append(HexInfo.new(0, Vector2i(0, 0), Enum.region.STARTING, Enum.side.P1, 0))
	Match.map.append(HexInfo.new(1, Vector2i(1, 0), Enum.region.INTERMEDIATE, Enum.side.P1, 0))
	Match.map.append(HexInfo.new(2, Vector2i(4, 0), Enum.region.STARTING, Enum.side.P2, 0))
	Match.map.append(HexInfo.new(3, Vector2i(5, 0), Enum.region.INTERMEDIATE, Enum.side.P2, 0))
	var roster := CardCatalogue.starter_army()
	var inventory: Array[UnitInfo] = CardCatalogue.all_units(1)
	check(inventory.all(BoardCharacter.supports), "Catalogue API itself excludes every unsupported legacy portrait-only definition")
	check(not inventory.any(func(unit: UnitInfo) -> bool: return unit.uuid == "alps-lone-wolf-p1"), "A known unsprited legacy factory stays out of the playable inventory")
	check(roster.size() == inventory.size() * 2, "Both players receive one copy of every sprite-backed unit")
	check(inventory.size() == 86 and roster.size() == 172, "Exactly 86 sprite-backed units are available per owner")
	var identities := {}
	for unit in roster:
		check(BoardCharacter.supports(unit), "No sprite-less card enters the local roster")
		check(not identities.has(unit.uuid), "Full roster contains no duplicate per-owner UUID")
		identities[unit.uuid] = true
	for unit in inventory:
		var key := unit.uuid.trim_suffix("-p1")
		check(identities.has(key + "-p1") and identities.has(key + "-p2"), "Each sprite-backed unit is available to red and blue")
	check(roster[0].uuid == "squirrel-king-p1" and roster[3].uuid == "mole-artificer-p2", "Existing saved-roster IDs remain unchanged")
	check(Match.start_local_match(roster, 10, 3), "Full roster accepts alternative hero candidates")
	check_all_rule_contracts()
	var squirrel := find("squirrel-king", 1)
	var mole := find("mole-artificer", 1)
	check(Match.can_deploy(squirrel.iun, 0) and Match.can_deploy(mole.iun, 0), "Any supported hero can be the first hero choice")
	check(not Match.can_deploy(find("reed-archer", 1).iun, 1), "A troop still cannot precede the first hero")
	check(Match.deploy(mole.iun, 0) and Match.players[1].selected_hero_id == mole.iun, "First hero deployment records the chosen identity")
	check(not Match.can_deploy(squirrel.iun, 0), "Other hero alternatives cannot deploy after a choice")
	Action.return_to_hand(TargetRef.unit(mole.iun), TargetRef.unit(mole.iun))
	check(not Match.can_deploy(squirrel.iun, 0), "Returning the chosen hero allows its redeployment without unlocking another hero")
	var snapshot := preload("res://scripts/runtime/match_snapshot.gd")
	var saved: Dictionary = snapshot._capture_state()
	Match.players[1].selected_hero_id = -1
	snapshot._apply_state(saved)
	check(Match.players[1].selected_hero_id == mole.iun and not Match.can_deploy(squirrel.iun, 0), "Saved matches retain hero choice even while that hero is in hand")
	print("Full roster: %d failures" % failures)
	get_tree().quit(0 if failures == 0 else 1)

## Sweeps all deployed/hand-independent definition contracts for both owners; no activation, cost or target selection is committed.
## The roster entry point calls after stable IDs/default Walk/printed baselines exist, catching unusable cost bundles on any card.
func check_all_rule_contracts() -> void:
	for unit in Match.army:
		var ctx := RuleContext.new(TargetRef.unit(unit.iun))
		for effect in unit.effects + unit.trigger_effects:
			if effect.cost != null: check(effect.cost.validate().is_empty(), "%s cost validates: %s" % [unit.uuid, effect.cost.validate()])
			if effect.event != null: check(effect.event.validate(ctx).is_empty(), "%s event contract validates" % unit.uuid)
			check(effect.consequence != null and effect.consequence.validate().is_empty(), "%s consequence contract validates" % unit.uuid)
		check(unit.type == Enum.type.TEMPLE or unit.effects.any(func(effect: Effect) -> bool: return unit._consequence_has_movement(effect.consequence)), "%s receives printed or implicit movement" % unit.uuid)
