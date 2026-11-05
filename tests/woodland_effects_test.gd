## Focused regressions for the new woodland catalogue rules; run only when explicitly requested with TEST.
extends Node

var checks := 0
var failures := 0
var events: Array[EffectEvent] = []

## Integration scene entry point covers incoming-Bash identity and exact retaliation recipients.
func _ready() -> void:
	Match.action_event.connect(func(event: EffectEvent) -> void: events.append(event))
	test_mouse_warrior()
	test_explorer()
	test_doctor()
	test_wild_squirrel()
	test_beaver()
	test_miner()
	test_mole_rat()
	test_sorcerer()
	test_wild_mouse()
	test_guinea_pig()
	test_upgrade_persistence()
	print("Woodland effects: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)

## Records each semantic assertion without preventing the independent scenarios from completing.
func check(value: bool, message: String) -> void:
	checks += 1
	if value: return
	failures += 1
	push_error(message)

## Builds a fresh stable-ID two-player board and disables presentation gates for deterministic command/event assertions.
func fixture() -> void:
	Match.reset_combat()
	Match.rules_runner.trigger_acknowledgements_enabled = false
	Match.rules_runner.presentation_busy_query = Callable()
	Match.army.clear()
	Match.map.clear()
	events.clear()
	for index in 4: Match.map.append(HexInfo.new(index, Vector2i(index, 0), Enum.region.FRONT, Enum.side.NONE, 0))
	for player in Match.players.values():
		player.actions_remaining = 10
		player.next_turn_actions = 0
		player.deployments_remaining = 3
		player.has_deployed = true

## Supplies a stable deployed card with printed defaults and a clean Reset baseline.
func add(unit: UnitInfo, hex_id: int) -> UnitInfo:
	unit.iun = Match.army.size()
	unit.ihx = hex_id
	unit.t_state = Enum.t_state.DEPLOYED
	unit.active = true
	unit.ensure_implicit_walk()
	unit.capture_printed_state()
	Match.army.append(unit)
	return unit

## Enemy attack entry triggers exactly one hostile Stun and one physical grant; Warrior attacking instead does not qualify.
func test_mouse_warrior() -> void:
	fixture()
	var warrior := add(CardCatalogue.mouse_warrior(1), 1)
	var attacker := add(CardCatalogue.rat_warrior(2), 0)
	Match.active_player = 2
	check(CombatResolver.move_unit(TargetRef.unit(attacker.iun), TargetRef.hex(1), 2, false, true), "Enemy enters Mouse Warrior's hex")
	check(attacker._counter_value(&"stun") == 1 and warrior._counter_value(&"physical") == 1, "Incoming Bash stuns attacker and grants Warrior one physical")
	check(warrior._counter_value(&"stun") == 0, "Free retaliation does not self-Stun Warrior")
	fixture()
	warrior = add(CardCatalogue.mouse_warrior(1), 0)
	attacker = add(CardCatalogue.rat_warrior(2), 1)
	check(CombatResolver.move_unit(TargetRef.unit(warrior.iun), TargetRef.hex(1), 2, false, true), "Warrior can enter as attacker")
	check(warrior._counter_value(&"physical") == 0 and attacker._counter_value(&"stun") == 0, "Warrior's outgoing Bash does not qualify")

## Pending choices use production PhraseExecution identity checks; absent choices fail safely instead of causing null-access noise.
func choose(ref: TargetRef) -> bool:
	var run := Match.rules_runner.active
	if run == null or run.current == null:
		check(false, "Expected a retained woodland choice")
		return false
	return run.current.choose(ref)

## CostBundle tests explicitly select activity and life/Soul identities, exercising collection before atomic commitment.
func pay_bundle(unit: UnitInfo, resource: StringName = &"") -> void:
	check(choose(TargetRef.unit(unit.iun)), "Choose activity payment")
	var target := TargetRef.unit(unit.iun) if resource.is_empty() else TargetRef.property(TargetRef.unit(unit.iun), resource)
	check(choose(target), "Choose explicit payment")

## Positive actual/max components award separate Explorer counters; damage and opposing increases do not qualify.
func test_explorer() -> void:
	fixture()
	var explorer := add(CardCatalogue.red_squirrel_explorer(1), 0)
	var friend := add(CardCatalogue.rat_warrior(1), 1)
	var enemy := add(CardCatalogue.rat_warrior(2), 2)
	check(Action.up_life(TargetRef.unit(friend.iun), TargetRef.unit(friend.iun), 1, 2), "Friendly life effect resolves")
	check(explorer.counter_modifiers() == Vector2i(1, 2), "Explorer receives captured +X/+Y from positive life components")
	Action.up_life(TargetRef.unit(friend.iun), TargetRef.unit(friend.iun), -1, 0)
	Action.up_life(TargetRef.unit(enemy.iun), TargetRef.unit(enemy.iun), 1, 1)
	check(explorer.counter_modifiers() == Vector2i(1, 2), "Explorer ignores reductions and enemy increases")
	check(explorer.deploy_regions == [Enum.region.STARTING, Enum.region.FRONT], "Explorer's SF regions are explicit")

## Doctor's lethal AC is payable and still heals its chosen friend; enemy targets and unpayable costs are rejected before mutation.
func test_doctor() -> void:
	fixture()
	var doctor := add(CardCatalogue.red_squirrel_doctor(1), 0)
	var friend := add(CardCatalogue.rat_warrior(1), 1)
	var enemy := add(CardCatalogue.rat_warrior(2), 2)
	doctor.actual_life = 1
	check(Match.rules_runner.submit(doctor.effects[1], TargetRef.unit(doctor.iun)), "Doctor offers an AC life payment")
	pay_bundle(doctor)
	check(doctor.t_state == Enum.t_state.DEFEATED, "Paying the final current life defeats Doctor")
	check(not choose(TargetRef.unit(enemy.iun)), "Doctor cannot select an enemy")
	check(choose(TargetRef.unit(friend.iun)) and friend.actual_life == 4 and friend.max_life == 4, "Paid consequence survives source death and gives +1 current/+1 max")
	check(Match.players[1].actions_remaining == 9, "Doctor consumes exactly one player action")

## Wild Squirrel captures X from maximum growth, chooses one range-2 Instant Bow target, and ignores current-only healing.
func test_wild_squirrel() -> void:
	fixture()
	var squirrel := add(CardCatalogue.wild_red_squirrel(1), 0)
	var friend := add(CardCatalogue.red_squirrel_doctor(1), 1)
	var enemy := add(CardCatalogue.rat_warrior(2), 2)
	friend.actual_life -= 1
	Action.up_life(TargetRef.unit(friend.iun), TargetRef.unit(friend.iun), 1, 0)
	check(not Match.rules_runner.busy(), "Current-only healing does not trigger Wild Squirrel")
	Action.up_life(TargetRef.unit(friend.iun), TargetRef.unit(friend.iun), 0, 2)
	check(choose(TargetRef.hex(enemy.ihx)), "Maximum growth opens an Instant Bow choice")
	check(Match.pending_bow_attacks.is_empty(), "Growth Bow resolves instantly")
	check(events.any(func(event: EffectEvent) -> bool: return event.action == &"bow" and event.data.get("amount", -1) == 2), "Instant Bow uses the frozen maximum increase X")
	check(squirrel._counter_value(&"stun") == 0, "Growth trigger does not pay normal action activity")

## Beaver automatically leaves Bomb 2 on its captured movement origin, independent of region; other movers and absent origin data do not trigger a placement.
func test_beaver() -> void:
	fixture()
	var beaver := add(CardCatalogue.wild_beaver(1), 0)
	Match.map[0].region = Enum.region.INTERMEDIATE
	check(beaver.effects[0].consequence.has_sticker(ActionSticker.Kind.PIERCE), "Beaver has Piercing Fire")
	check(beaver.magical_modifier == 2 and beaver._counter_value(&"magical") == 0, "Beaver magic is a live static modifier")
	check(CombatResolver.move_unit(TargetRef.unit(beaver.iun), TargetRef.hex(1), 1, false, true), "Beaver Walk resolves")
	check(Match.bomb_at(0) != null and Match.bomb_at(0).damage == 2, "Beaver leaves Bomb 2 on its non-Starting former hex automatically")
	check(Match.bomb_at(1) == null and not Match.rules_runner.busy(), "Beaver does not bomb its destination or ask for a tile")
	var other := add(CardCatalogue.rat_warrior(1), 2)
	Match.action_event.emit(EffectEvent.new(&"move", TargetRef.unit(other.iun), TargetRef.hex(3), {"origin_hex": 2}))
	check(Match.bomb_at(2) == null, "Another unit's movement does not trigger Beaver")
	var history := EffectEvent.new(&"move", TargetRef.unit(beaver.iun), TargetRef.hex(1), {"origin_hex": 3})
	var anchor := Selectors.EventHex.new()
	var refs := anchor.resolve(RuleContext.new(TargetRef.unit(beaver.iun), history))
	check(refs.size() == 1 and refs[0].id == 3, "Historical origin stays captured rather than following Beaver's current hex")
	Match.action_event.emit(EffectEvent.new(&"move", TargetRef.unit(beaver.iun), TargetRef.hex(1)))
	check(Match.bomb_at(1) == null and Match.bomb_at(3) == null, "Missing origin history cannot invent a destination placement")

## Miner grants +1/+1 on friendly Bomb contact, not immunity; its side restriction preserves ordinary control and vacancy rules.
func test_miner() -> void:
	fixture()
	var miner := add(CardCatalogue.mole_miner(1), 0)
	var friend := add(CardCatalogue.rat_warrior(1), 1)
	var enemy := add(CardCatalogue.rat_warrior(2), 2)
	var blast := CannonAttack.new()
	blast.source_id = enemy.iun
	blast.owner = 2
	blast.target_hex = friend.ihx
	blast.amount = 1
	blast.explosion = true
	CombatResolver.resolve_cannon(blast)
	check(friend.actual_life == 3 and friend.max_life == 4, "Bomb contact heals and enlarges its exact friendly victim")
	check(miner.has_effective_flag(&"first-strike"), "Miner has First Strike")
	fixture()
	miner = add(CardCatalogue.mole_miner(1), 0)
	miner.t_state = Enum.t_state.UNDEPLOYED
	miner.ihx = -1
	friend = add(CardCatalogue.rat_warrior(1), 2)
	Match.map[2].region = Enum.region.INTERMEDIATE
	Match.map[2].side = Enum.side.P2
	Match.map[3].region = Enum.region.INTERMEDIATE
	Match.map[3].side = Enum.side.P2
	check(Match.can_deploy(miner.iun, 3), "Miner deploys on an opponent-side controlled vacant Intermediate hex")
	Match.map[3].side = Enum.side.P1
	check(not Match.can_deploy(miner.iun, 3), "Miner rejects its own side")

## Defending Mole Rat leaves Bomb on its original hex, then uses one free own movement and cancels the Bash.
func test_mole_rat() -> void:
	fixture()
	var mole := add(CardCatalogue.wild_mole_rat(1), 1)
	var enemy := add(CardCatalogue.rat_warrior(2), 0)
	Match.active_player = 2
	CombatResolver.move_unit(TargetRef.unit(enemy.iun), TargetRef.hex(1), 2, false, true)
	check(Match.bomb_at(1) != null and Match.bomb_at(1).damage == 2, "Defending Mole Rat places Bomb before fleeing")
	check(not choose(TargetRef.hex(3)), "Implicit Walk 1 cannot Flee two hexes")
	check(choose(TargetRef.hex(2)) and mole.ihx == 2 and Match.bashes.is_empty(), "Flee uses implicit movement and leaves the Bash")
	check(mole._counter_value(&"stun") == 0 and mole.magical_modifier == 2, "Flee is free and preserves magical static")

## Sorcerer pays both health values and activity; a lethal payer can still grant Bow counters to its exact chosen ally.
func test_sorcerer() -> void:
	fixture()
	var sorcerer := add(CardCatalogue.mouse_sorcerer(1), 0)
	var archer := add(CardCatalogue.rat_thief(1), 1)
	sorcerer.actual_life = 1
	check(Match.rules_runner.submit(sorcerer.effects[1], TargetRef.unit(sorcerer.iun)), "Sorcerer starts its explicit life cost")
	pay_bundle(sorcerer)
	check(sorcerer.max_life == 1 and sorcerer.t_state == Enum.t_state.DEFEATED, "Sorcerer loses one current and maximum life")
	check(choose(TargetRef.unit(archer.iun)) and archer.bow_damage_bonus == 1 and archer.bow_range_bonus == 1, "Sorcerer's paid Bow upgrade survives its death")

## Wild Mouse's C stores the enemy's next-turn action and grants Soul; AC Reset separately pays Soul/activity with unrestricted ownership.
func test_wild_mouse() -> void:
	fixture()
	var mouse := add(CardCatalogue.wild_mouse(1), 0)
	var enemy := add(CardCatalogue.rat_warrior(2), 1)
	check(Match.rules_runner.submit(mouse.effects[0], TargetRef.unit(mouse.iun)), "Borrow Soul begins with a player cost choice")
	check(choose(TargetRef.player(2)), "Borrow Soul explicitly pays the opponent's next-turn action")
	check(mouse._counter_value(&"Soul") == 2 and mouse.active and Match.players[2].next_turn_actions == 1, "C grants two Soul without self-Stun and schedules enemy bonus")
	Match.start_turn(2)
	check(Match.players[2].actions_remaining == Match.players[2].action_allowance + 1 and Match.players[2].next_turn_actions == 0, "Enemy action bonus is consumed once at the enemy Start")
	Match.active_player = 1
	Match.phase = Match.Phase.ACTION
	Match.players[1].actions_remaining = 5
	enemy.actual_life = 1
	check(Match.rules_runner.submit(mouse.effects[2], TargetRef.unit(mouse.iun)), "Soul Reset is payable")
	pay_bundle(mouse, &"Soul")
	check(choose(TargetRef.unit(enemy.iun)) and enemy.actual_life == enemy.max_life, "Soul Reset accepts an enemy and restores printed health")
	check(mouse._counter_value(&"Soul") == 1 and mouse._counter_value(&"stun") == 1, "Soul Reset pays one Soul and normal self-Stun")

## Guinea Pig's growth changes maximum only; friendly Wild physical contact heals it, while non-Wild contact does not.
func test_guinea_pig() -> void:
	fixture()
	var guinea := add(CardCatalogue.wild_guinea_pig(1), 0)
	var wild := add(CardCatalogue.wild_rat(1), 1)
	var other := add(CardCatalogue.rat_warrior(1), 2)
	var enemy := add(CardCatalogue.rat_warrior(2), 3)
	check(Match.rules_runner.submit(guinea.effects[0], TargetRef.unit(guinea.iun)), "Guinea Pig growth is activated")
	pay_bundle(guinea)
	check(guinea.actual_life == 1 and guinea.max_life == 3, "Growth costs current life and grants maximum only")
	Match.action_event.emit(EffectEvent.new(&"hit", TargetRef.unit(other.iun), TargetRef.unit(enemy.iun), {"damage": 1}))
	check(guinea.actual_life == 1, "Non-Wild contact does not heal Guinea Pig")
	Match.action_event.emit(EffectEvent.new(&"hit", TargetRef.unit(wild.iun), TargetRef.unit(enemy.iun), {"damage": 0}))
	check(guinea.actual_life == 2 and guinea.max_life == 3, "A friendly Wild Hit heals current life, including zero-damage contact")

## Generic Upgrade chooses unit then ability, modifies only that ability and survives a snapshot round trip before Reset clears it.
func test_upgrade_persistence() -> void:
	fixture()
	var mouse := add(CardCatalogue.wild_mouse(1), 0)
	var archer := add(CardCatalogue.rat_thief(1), 1)
	Match.get_property(TargetRef.property(TargetRef.unit(mouse.iun), &"Soul")).value = 1
	check(Match.rules_runner.submit(mouse.effects[1], TargetRef.unit(mouse.iun)), "Soul Upgrade starts its AC")
	pay_bundle(mouse, &"Soul")
	check(choose(TargetRef.unit(archer.iun)), "Upgrade first chooses a friendly unit")
	var bow: EffectOption
	for option in archer.effect_options():
		if option.category == &"effects" and option.definition.consequence.verb.name == &"bow": bow = option
	check(bow != null and choose(TargetRef.property(TargetRef.unit(archer.iun), bow.name)), "Upgrade then chooses one specific ability")
	var ctx := RuleContext.new(TargetRef.unit(archer.iun))
	ctx.subject = ctx.source
	check(archer.effects[1].consequence.verb.bound_to(ctx).user_params[0] == 2 and archer.effects[0].consequence.verb.bound_to(ctx).user_params[0] == 2, "Bow increases while separate Walk remains unchanged")
	var snapshot = preload("res://scripts/runtime/match_snapshot.gd")
	var saved: Dictionary = snapshot._capture_state()
	archer.ability_upgrades.clear()
	snapshot._apply_state(saved)
	check(archer.ability_upgrades.size() == 1 and archer.ability_bonus(archer.effects[1].consequence.verb).x == 1, "Snapshot restores the recipient's chosen ability bonus")
	Action.reset_unit(TargetRef.unit(mouse.iun), TargetRef.unit(archer.iun))
	check(archer.ability_upgrades.is_empty(), "Reset removes chosen-ability upgrades")
