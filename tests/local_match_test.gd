extends Node

var checks := 0
var failures := 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

## Exercises the local format, controlled deployment, derived control bonus, and Start recovery.
## Godot runs this scene directly as a focused regression for Match's first playable loop.
## Hero movement checks distinguish printed actions from the rulebook's implicit Walk 1 added during match setup.
func _ready() -> void:
	_build_map()
	var army := CardCatalogue.starter_army()
	check(Match.start_local_match(army, 1, 3), "A valid one-action two-player test match begins")
	check(army[0].type == Enum.type.HERO and army[0].uuid.begins_with("squirrel-king")
		and army[3].type == Enum.type.HERO and army[3].uuid.begins_with("mole-artificer"),
		"The small local test roster includes two different JS heroes")
	check(not army[0].effects.any(func(effect: Effect) -> bool: return not effect.implicit and effect.consequence.verb.name in [&"move", &"fly"])
		and not army[3].effects.any(func(effect: Effect) -> bool: return not effect.implicit and effect.consequence.verb.name in [&"move", &"fly"]),
		"The hero cards retain their printed actions without an invented Move/Fly action")
	check(army[0].effects.any(func(effect: Effect) -> bool: return effect.consequence.verb.name == &"fire")
		and army[1].effects.any(func(effect: Effect) -> bool: return effect.consequence.verb.name == &"bow")
		and army[2].effects.any(func(effect: Effect) -> bool: return effect.consequence.verb.name == &"cannon")
		and army[3].effects.any(func(effect: Effect) -> bool: return effect.consequence.verb.name == &"bomb_throw")
		and army[3].effects.any(func(effect: Effect) -> bool: return effect.consequence.verb.name == &"fire")
		and army[4].effects.any(func(effect: Effect) -> bool: return effect.consequence.verb.name == &"stun")
		and army[5].effects.any(func(effect: Effect) -> bool: return effect.consequence.verb.name == &"move"),
		"The local starter roster exposes each card's current object-authored actions")
	check(ControlResolver.region_owner(Match.map[0]) == 1, "The empty home region belongs to Player 1 by its half-point")
	check(ControlResolver.region_owner(Match.map[2]) == 2, "The empty home region belongs to Player 2 by its half-point")
	check(ControlResolver.region_owner(Match.map[4]) == Enum.owner.NONE, "An empty front region is neutral")
	check(not Match.can_deploy(1, 1), "A non-hero cannot be the first deployed card")
	check(Match.can_deploy(0, 0), "The hero can deploy to a vacant controlled home hex")
	check(Match.deploy(0, 0) and Match.active_player == 2, "Legal hero deployment spends the turn's action and passes to Player 2")
	check(not Match.army[0].active and Match.players[1].deployments_remaining == 2,
		"Deployment enters inactive and spends one deployment counter")
	check(Match.get_property(TargetRef.property(TargetRef.unit(0), UnitInfo.STUN_COUNTER)).value == 1,
		"Deployment adds one initial Stun counter")
	check(Match.army[0].physical_modifier == 1, "A deployed unit receives the live control bonus")
	check(not Match.can_deploy(1, 0), "Occupied destinations are rejected")
	check(not Match.can_deploy(1, 4), "Deployment into a neutral front region is rejected")
	check(not Match.can_deploy(4, 3), "Player 2 must also deploy their hero first")
	check(Match.deploy(3, 2) and Match.active_player == 1, "Player 2's hero deployment also advances to Player 1")
	check(Match.can_deploy(1, 1), "Another vacant tile in the controlled region is allowed on the next turn")
	check(Match.active_player == 1 and not Match.army[0].active
		and Match.get_property(TargetRef.property(TargetRef.unit(0), UnitInfo.STUN_COUNTER)).value == 0,
		"The first own Start after deployment removes its Stun but leaves it inactive")
	Match.complete_action(1, 0)
	Match.complete_action(2, 0)
	check(Match.active_player == 1 and Match.army[0].active,
		"The following own Start activates the unit after deployment Stun is cleared")

	var hero := TargetRef.unit(0)
	check(Action.pay_activity(hero, hero), "Active SELF can pay the self-Stun cost")
	check(not Match.army[0].active and Match.get_property(TargetRef.property(hero, UnitInfo.STUN_COUNTER)).value == 1, "Payment makes the unit inactive and adds one Stun")
	check(Match.finish_action(1), "A paid action spends one player action")
	Match.complete_action(1, 0)
	Match.complete_action(2, 0)
	check(Match.active_player == 1 and not Match.army[0].active, "A stunned unit removes one Stun but stays inactive at Start")
	check(Match.get_property(TargetRef.property(hero, UnitInfo.STUN_COUNTER)).value == 0, "Start removes one Stun counter")
	Match.complete_action(1, 0)
	Match.complete_action(2, 0)
	check(Match.army[0].active, "An unstunned unit activates at its following Start")

	var opponent_hero := Match.army[3]
	var opponent_troop := Match.army[4]
	var second_opponent_troop := Match.army[5]
	opponent_hero.ihx = 0
	opponent_troop.ihx = 0
	opponent_troop.t_state = Enum.t_state.DEPLOYED
	second_opponent_troop.ihx = 0
	second_opponent_troop.t_state = Enum.t_state.DEPLOYED
	check(ControlResolver.region_owner(Match.map[0]) == 2, "Current unit life can transfer control of a region")
	check(Match.army[0].physical_modifier == 0 and opponent_troop.physical_modifier == 1, "The physical bonus follows current regional ownership")
	opponent_hero.ihx = 2
	opponent_troop.ihx = 2
	second_opponent_troop.ihx = -1
	second_opponent_troop.t_state = Enum.t_state.UNDEPLOYED
	Match.army[2].ihx = 4
	Match.army[2].t_state = Enum.t_state.DEPLOYED
	opponent_troop.ihx = 4
	opponent_troop.actual_life = Match.army[2].actual_life
	check(ControlResolver.region_owner(Match.map[4]) == Enum.owner.NONE, "Equal front-region totals are neutral")

	print("Local match integration: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)

## Creates two starting regions, a P1 intermediate region, and a neutral front region for deterministic checks.
## _ready() calls this before initializing Match.
func _build_map() -> void:
	Match.map.clear()
	Match.map.append(HexInfo.new(0, Vector2i(-2, 1), Enum.region.STARTING, Enum.side.P1, 0))
	Match.map.append(HexInfo.new(1, Vector2i(-3, 1), Enum.region.INTERMEDIATE, Enum.side.P1, 0))
	Match.map.append(HexInfo.new(2, Vector2i(2, 1), Enum.region.STARTING, Enum.side.P2, 0))
	Match.map.append(HexInfo.new(3, Vector2i(3, 1), Enum.region.STARTING, Enum.side.P2, 0))
	Match.map.append(HexInfo.new(4, Vector2i(0, 1), Enum.region.FRONT, Enum.side.NONE, 0))
