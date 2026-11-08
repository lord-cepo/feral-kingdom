## Focused Mara/Tamia/Grey Squirrel regressions; execute only when the user requests TEST.
extends Node

var failures := 0
var events: Array[EffectEvent] = []

## Headless scene entry point exercises source/target ownership, ordinary costs, persistent Cannon growth and the Action-free timed bonus.
func _ready() -> void:
	Match.action_event.connect(func(event: EffectEvent) -> void: events.append(event))
	test_tamia_and_both_disable_triggers()
	test_tamia_eligibility()
	test_mara_life_and_non_triggers()
	test_cannon_capture_and_lifetime()
	test_grey_squirrel()
	test_grey_eligibility_and_expiry()
	test_registration()
	print("Disable units: %d failures" % failures)
	get_tree().quit(0 if failures == 0 else 1)

## Reports independent semantic failures without stopping subsequent scenarios.
func check(value: bool, message: String) -> void:
	if value: return
	failures += 1
	push_error(message)

## Resets all rule work and finite presentation gates; six straight playable hexes isolate targeting from deployment setup.
func fixture() -> void:
	Match.reset_combat()
	Match.rules_runner.trigger_acknowledgements_enabled = false
	Match.rules_runner.presentation_busy_query = Callable()
	Match.army.clear()
	Match.map.clear()
	events.clear()
	for index in 6: Match.map.append(HexInfo.new(index, Vector2i(index, 0), Enum.region.FRONT, Enum.side.NONE, 0))
	for player in Match.players.values():
		player.actions_remaining = 10
		player.action_allowance = 10
		player.deployments_remaining = 3
		player.has_deployed = true

## Attaches a stable unit ID and printed Reset baseline; negative position creates a hand card without emitting Deploy.
func add(unit: UnitInfo, hex_id: int) -> UnitInfo:
	unit.iun = Match.army.size()
	unit.ihx = hex_id
	unit.t_state = Enum.t_state.DEPLOYED if hex_id >= 0 else Enum.t_state.UNDEPLOYED
	unit.active = hex_id >= 0
	unit.ensure_implicit_walk()
	unit.capture_printed_state()
	Match.army.append(unit)
	return unit

## Supplies a non-triggering card so eligibility and non-trigger assertions do not accidentally activate unrelated catalogue engines.
func plain(owner: int, hex_id: int) -> UnitInfo:
	var unit := UnitInfo.new()
	unit.player = owner
	unit.name = "Test body"
	unit.uuid = "test-%d-p%d" % [Match.army.size(), owner]
	unit.actual_life = 5
	unit.max_life = 5
	return add(unit, hex_id)

## Submits the retained exact identity through production PhraseExecution; absent pending choices fail safely.
func choose(ref: TargetRef) -> bool:
	var run := Match.rules_runner.active
	return run != null and run.current != null and run.current.choose(ref)

## One Tamia command triggers each Mara according to the disabled card's owner, not the disabling actor; costs/resources commit once.
func test_tamia_and_both_disable_triggers() -> void:
	fixture()
	var red := add(CardCatalogue.wild_mara(1), 0)
	var blue := add(CardCatalogue.wild_mara(2), 2)
	var tamia := add(CardCatalogue.wild_tamia(1), 1)
	var reserve := plain(1, -1)
	var enemy := plain(2, -1)
	var hero := plain(1, -1)
	hero.type = Enum.type.HERO
	check(Match.rules_runner.submit(tamia.effects[1], TargetRef.unit(tamia.iun)), "Tamia submits its reserve conversion")
	check(choose(TargetRef.unit(tamia.iun)), "Tamia pays ordinary self-Stun")
	check(not choose(TargetRef.unit(hero.iun)) and not choose(TargetRef.unit(enemy.iun)), "Tamia excludes heroes and enemy hand cards")
	check(choose(TargetRef.unit(reserve.iun)), "Tamia selects a friendly non-hero in hand")
	check(reserve.t_state == Enum.t_state.DEFEATED and reserve.actual_life == 5, "Disable preserves health while moving hand to defeated")
	check(Match.players[1].deployments_remaining == 4 and Match.players[1].actions_remaining == 9 and tamia._counter_value(&"stun") == 1, "Tamia grants one deployment and spends one action/activity")
	check(red.effective_action_values(&"cannon", [2, 2]) == [3, 2] and red.actual_life == 2, "Friendly Disable permanently raises only red Mara's Cannon damage")
	check(blue.actual_life == 3 and blue.max_life == 3 and blue.action_counter(UnitInfo.CANNON_DAMAGE_COUNTER) == 0, "The same Disable grows opposing Mara's health rather than Cannon")
	check(not events.any(func(event: EffectEvent) -> bool: return event.action in [&"die", &"return_to_hand"]), "Disable does not invent death or Return triggers")
	check(not Action.disable(TargetRef.unit(tamia.iun), TargetRef.unit(reserve.iun)) and red.action_counter(UnitInfo.CANNON_DAMAGE_COUNTER) == 1, "A repeated Disable of the same defeated card cannot retrigger growth")

## No eligible hand unit means no available command; non-hero includes temples, but deployed/defeated cards remain illegal.
func test_tamia_eligibility() -> void:
	fixture()
	var tamia := add(CardCatalogue.wild_tamia(1), 0)
	var deployed := plain(1, 1)
	var defeated := plain(1, -1)
	defeated.t_state = Enum.t_state.DEFEATED
	plain(2, -1)
	check(not Match.rules_runner.command_available(tamia.effects[1], TargetRef.unit(tamia.iun)) and tamia.active, "No hand recipient does not pay or offer Tamia's action")
	var temple := plain(1, -1)
	temple.type = Enum.type.TEMPLE
	check(Match.rules_runner.submit(tamia.effects[1], TargetRef.unit(tamia.iun)) and choose(TargetRef.unit(tamia.iun)), "A friendly temple makes conversion available")
	check(not choose(TargetRef.unit(deployed.iun)) and not choose(TargetRef.unit(defeated.iun)), "Tamia excludes deployed and defeated friends")
	check(choose(TargetRef.unit(temple.iun)) and temple.t_state == Enum.t_state.DEFEATED, "A non-hero temple in hand can be disabled")

## Enemy Disable grants genuine life growth and activates Explorer; ordinary Return/Die and off-board Mara cannot qualify.
func test_mara_life_and_non_triggers() -> void:
	fixture()
	var mara := add(CardCatalogue.wild_mara(1), 0)
	var explorer := add(CardCatalogue.red_squirrel_explorer(1), 1)
	var enemy := plain(2, -1)
	Action.disable(TargetRef.unit(explorer.iun), TargetRef.unit(enemy.iun))
	check(mara.actual_life == 3 and mara.max_life == 3, "Enemy Disable grants +1 current/+1 maximum life")
	check(explorer.counter_modifiers() == Vector2i(1, 1), "Applied Mara growth activates the existing life-increase engine")
	var friend := plain(1, 2)
	Action.return_to_hand(TargetRef.unit(explorer.iun), TargetRef.unit(friend.iun))
	Match.defeat(TargetRef.unit(friend.iun))
	check(mara.actual_life == 3 and mara.action_counter(UnitInfo.CANNON_DAMAGE_COUNTER) == 0, "Return and Die do not activate either Disable rule")
	Action.return_to_hand(TargetRef.unit(explorer.iun), TargetRef.unit(mara.iun))
	var another := plain(2, -1)
	Action.disable(TargetRef.unit(explorer.iun), TargetRef.unit(another.iun))
	check(mara.actual_life == 3 and mara.max_life == 3, "Mara in hand does not capture new Disable triggers")

## Permanent Cannon counters affect future captured attacks, survive Return/snapshots and remain distinct from Reset and attack consumption.
func test_cannon_capture_and_lifetime() -> void:
	fixture()
	var mara := add(CardCatalogue.wild_mara(1), 0)
	var friend := plain(1, -1)
	check(CombatResolver.declare_cannon(TargetRef.unit(mara.iun), TargetRef.hex(2), 2, 2, false, false, true), "Mara captures printed Cannon 2")
	var earlier := Match.pending_cannon_attacks.duplicate()
	Action.disable(TargetRef.unit(mara.iun), TargetRef.unit(friend.iun))
	check(earlier.all(func(attack: CannonAttack) -> bool: return attack.amount == 2), "Already queued Cannon values do not drift after growth")
	check(CombatResolver.declare_cannon(TargetRef.unit(mara.iun), TargetRef.hex(2), 2, 2, false, false, true) and Match.pending_cannon_attacks.back().amount == 3, "Next Cannon captures its persistent +1 damage")
	check(mara.action_counter(UnitInfo.CANNON_DAMAGE_COUNTER) == 1, "Declaring attacks does not consume permanent Cannon counters")
	Action.return_to_hand(TargetRef.unit(mara.iun), TargetRef.unit(mara.iun))
	check(mara.action_counter(UnitInfo.CANNON_DAMAGE_COUNTER) == 1, "Return retains permanent Cannon counters")
	var snapshot := preload("res://scripts/runtime/match_snapshot.gd")
	var saved: Dictionary = snapshot._capture_state()
	mara.props = []
	snapshot._apply_state(saved)
	check(mara.action_counter(UnitInfo.CANNON_DAMAGE_COUNTER) == 1, "Snapshot restores Cannon counters through ordinary properties")
	Action.reset_unit(TargetRef.unit(mara.iun), TargetRef.unit(mara.iun))
	check(mara.action_counter(UnitInfo.CANNON_DAMAGE_COUNTER) == 0 and mara.max_life == 2, "Reset removes acquired Cannon counters and restores printed health")

## Grey's A action grants only one adjacent friend a timed +1 Bow damage, pays activity, preserves the player action and freezes future Bow capture.
func test_grey_squirrel() -> void:
	fixture()
	var grey := add(CardCatalogue.wild_grey_squirrel(1), 0)
	var archer := add(CardCatalogue.reed_archer(1), 1)
	var enemy := plain(2, 2)
	var distant := plain(1, 4)
	check(Match.rules_runner.submit(grey.effects[1], TargetRef.unit(grey.iun)) and choose(TargetRef.unit(grey.iun)), "Grey pays activity for its A action")
	check(not choose(TargetRef.unit(grey.iun)) and not choose(TargetRef.unit(enemy.iun)) and not choose(TargetRef.unit(distant.iun)), "Only another exact-distance-one friend is legal")
	check(choose(TargetRef.unit(archer.iun)), "Grey chooses its adjacent friend")
	check(not grey.active and grey._counter_value(&"stun") == 1 and Match.players[1].actions_remaining == 10, "A still pays self-Stun but spends no action")
	check(archer.effective_bow_bonus() == Vector2i(1, 0) and archer.bow_damage_bonus == 0 and archer.timed_grants.size() == 1, "Grey's recipient gets a timed damage-only bonus, not permanent counters")
	check(CombatResolver.declare_bow(TargetRef.unit(archer.iun), TargetRef.hex(enemy.ihx), 1, 4, false, false, true) and Match.pending_bow_attacks.back().amount == 2, "Bow captures Grey's applied damage bonus")
	Match.expire_timed_grants(1, Match.turn_number)
	check(archer.effective_bow_bonus() == Vector2i.ZERO and Match.pending_bow_attacks.back().amount == 2, "End expiry removes future bonus without changing a captured Bow")

## Missing adjacent targets leave no available command; source departure and wrong-owner cleanup do not erase a captured recipient-bound lifetime.
func test_grey_eligibility_and_expiry() -> void:
	fixture()
	var grey := add(CardCatalogue.wild_grey_squirrel(1), 0)
	var reserve := plain(1, -1)
	plain(1, 4)
	check(not Match.rules_runner.command_available(grey.effects[1], TargetRef.unit(grey.iun)) and grey.active, "No adjacent deployed friend offers no paid Grey action")
	var friend := plain(1, 1)
	Match.rules_runner.submit(grey.effects[1], TargetRef.unit(grey.iun))
	choose(TargetRef.unit(grey.iun))
	check(not choose(TargetRef.unit(reserve.iun)) and choose(TargetRef.unit(friend.iun)), "Grey cannot grant to a hand card")
	Action.return_to_hand(TargetRef.unit(friend.iun), TargetRef.unit(grey.iun))
	Match.expire_timed_grants(2, Match.turn_number)
	check(friend.effective_bow_bonus().x == 1, "Source Return and opponent cleanup preserve the captured grant")
	Match.expire_timed_grants(1, Match.turn_number)
	check(friend.timed_grants.is_empty(), "Grant expires at its captured current-player End cleanup")

## The three Disable cards keep exact stats/names/portraits as the twenty newer adventurers append for both owners.
func test_registration() -> void:
	var roster := CardCatalogue.starter_army()
	check(roster.size() == 194, "Both players have all 97 PixelLab units")
	var cards: Array[UnitInfo] = [CardCatalogue.wild_mara(1), CardCatalogue.wild_tamia(1), CardCatalogue.wild_grey_squirrel(1)]
	var lives := [2, 2, 1]
	var regions := [[Enum.region.INTERMEDIATE], [Enum.region.STARTING], [Enum.region.STARTING, Enum.region.INTERMEDIATE]]
	for index in cards.size():
		var card := cards[index]
		check(card.actual_life == lives[index] and card.deploy_regions == regions[index], "New unit retains specified health and regions")
		check(BoardCharacter.supports(card) and ResourceLoader.exists(BoardCharacter.portrait_path(card)), "New unit has imported PixelLab art")
		var key := card.uuid.trim_suffix("-p1")
		for player_id in [1, 2]: check(roster.any(func(unit: UnitInfo) -> bool: return unit.uuid == "%s-p%d" % [key, player_id]), "New unit is available to both owners")
