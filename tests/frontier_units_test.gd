## Focused behavioral coverage for the eleven approved frontier units.
extends "res://tests/synergy_units_test.gd"

## The dedicated scene uses headless trigger dispatch and real retained choices.
func _ready() -> void:
	Match.action_event.connect(record)
	test_shaman()
	test_wizard()
	test_alchemist()
	test_thief()
	test_hunter()
	test_berserker()
	test_merchant()
	test_engineer()
	test_crossbowman()
	test_paladin()
	test_pirate()
	test_printed_commands()
	print("Frontier units: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)

## Starts the catalogue command through RulesRunner, including normal costs and phase accounting.
func play(unit: UnitInfo, slot: int) -> bool:
	return Match.rules_runner.submit(unit.effects[slot], TargetRef.unit(unit.iun))

## Marks an off-board fixture defeated without manufacturing a trigger.
func defeated(owner: int) -> UnitInfo:
	var unit := plain(owner, -1)
	unit.t_state = Enum.t_state.DEFEATED
	unit.actual_life = 0
	return unit

## Publishes one declaration with the production action, stage and identity domains.
func declaration(action: StringName, unit: UnitInfo, target: TargetRef) -> void:
	Match.action_event.emit(EffectEvent.new(action, TargetRef.unit(unit.iun), target, {}, &"target"))

## Enemy geography gates Revive; Sacrifice chooses another friend and queues only the owner's next-turn action.
func test_shaman() -> void:
	fixture()
	var shaman := add(FrontierCatalogue.mole_shaman(1), 0)
	var ally := defeated(1)
	var enemy := defeated(2)
	Match.map[0].side = Enum.side.P1
	check(not play(shaman, 1) and shaman.active, "Own-side Revive spends neither activity nor an action")
	Match.map[0].side = Enum.side.P2
	check(play(shaman, 1) and choose(TargetRef.unit(shaman.iun)), "Enemy-side Revive pays AS")
	check(not choose(TargetRef.unit(enemy.iun)), "Enemy defeated card cannot be Revived")
	check(choose(TargetRef.unit(ally.iun)) and ally.t_state == Enum.t_state.UNDEPLOYED and ally.actual_life == ally.max_life, "Revive restores the chosen friend to hand")
	shaman.active = true
	var donor := plain(1, 1)
	var hostile := plain(2, 2)
	Match.players[1].next_turn_actions = 0
	Match.players[2].next_turn_actions = 0
	check(play(shaman, 2) and choose(TargetRef.unit(shaman.iun)), "Sacrifice retains its cost choice")
	check(not choose(TargetRef.unit(shaman.iun)) and not choose(TargetRef.unit(hostile.iun)), "Self and enemies cannot pay the friendly Sacrifice")
	check(choose(TargetRef.unit(donor.iun)) and donor.t_state == Enum.t_state.DEFEATED, "The selected donor is sacrificed")
	check(Match.players[1].next_turn_actions == 1 and Match.players[2].next_turn_actions == 0, "Only the Shaman owner receives a future action")

## Multiple simultaneous gains reserve just one capture; self, enemies and removals never qualify.
func test_wizard() -> void:
	fixture()
	var wizard := add(FrontierCatalogue.lemming_wizard(1), 0)
	var ally := plain(1, 1)
	var enemy := plain(2, 2)
	var own := TargetRef.unit(wizard.iun)
	SynergyActions.add_counter(own, own, UnitInfo.EMBER_COUNTER, 1)
	SynergyActions.add_counter(own, TargetRef.unit(enemy.iun), UnitInfo.EMBER_COUNTER, 2)
	check(wizard._counter_value(UnitInfo.EMBER_COUNTER) == 1, "Self and enemy gains do not use the friendly-Ember trigger")
	Match.rules_runner.begin_boundary()
	SynergyActions.add_counter(own, TargetRef.unit(ally.iun), UnitInfo.EMBER_COUNTER, 3)
	SynergyActions.add_counter(own, TargetRef.unit(ally.iun), UnitInfo.EMBER_COUNTER, 1)
	Match.rules_runner.end_boundary()
	check(wizard._counter_value(UnitInfo.EMBER_COUNTER) == 2, "A multi-Ember gain and a queued second gain yield only one bonus")
	var snapshot := preload("res://scripts/runtime/match_snapshot.gd")
	var saved: Dictionary = snapshot._capture_state()
	wizard.trigger_turns.clear()
	snapshot._apply_state(saved)
	SynergyActions.add_counter(own, TargetRef.unit(ally.iun), UnitInfo.EMBER_COUNTER, 1)
	check(wizard._counter_value(UnitInfo.EMBER_COUNTER) == 2, "Snapshot round trip preserves this turn's reservation")
	Match.turn_number += 1
	Action.decrement(own, TargetRef.property(TargetRef.unit(ally.iun), UnitInfo.EMBER_COUNTER), 1)
	check(wizard._counter_value(UnitInfo.EMBER_COUNTER) == 2, "Removing Embers never triggers")
	SynergyActions.add_counter(own, TargetRef.unit(ally.iun), UnitInfo.EMBER_COUNTER, 1)
	check(wizard._counter_value(UnitInfo.EMBER_COUNTER) == 3, "A new turn permits another friendly gain")

## The Alchemist captures actual life from its paid donor, with eligibility and no early mutation.
func test_alchemist() -> void:
	fixture()
	var alchemist := add(FrontierCatalogue.mole_alchemist(2), 0)
	var donor := plain(2, 1)
	donor.actual_life = 3
	var hostile := plain(1, 2)
	Match.active_player = 2
	check(Match.rules_runner.command_available(alchemist.effects[1], TargetRef.unit(alchemist.iun)), "Sacrifice's captured life is available to the command preview")
	check(play(alchemist, 1) and choose(TargetRef.unit(alchemist.iun)), "Alchemist collects activity before the donor")
	check(alchemist.active and not choose(TargetRef.unit(hostile.iun)), "Unpaid selection changes no activity and rejects the opponent")
	check(choose(TargetRef.unit(donor.iun)) and donor.t_state == Enum.t_state.DEFEATED, "Alchemist's friendly donor is defeated")
	check(alchemist._counter_value(UnitInfo.EMBER_COUNTER) == 3, "Award uses the donor's pre-sacrifice actual life rather than its maximum")

## Only an adjacent enemy hero's exact two-component gain grants deployment and a friendly Revive.
func test_thief() -> void:
	fixture()
	var thief := add(FrontierCatalogue.flying_squirrel_thief(1), 0)
	var hero := plain(2, 2)
	hero.type = Enum.type.HERO
	var friend_hero := plain(1, 1)
	friend_hero.type = Enum.type.HERO
	var ally := defeated(1)
	var enemy := defeated(2)
	var before := Match.players[1].deployments_remaining
	var ref := TargetRef.unit(thief.iun)
	Action.up_life(ref, TargetRef.unit(hero.iun), 1, 1)
	Action.up_life(ref, TargetRef.unit(friend_hero.iun), 1, 1)
	hero.ihx = 1
	hero.actual_life -= 1
	Action.up_life(ref, TargetRef.unit(hero.iun), 1, 0)
	check(Match.players[1].deployments_remaining == before, "Distant, friendly, and current-only gains do not qualify")
	Action.up_life(ref, TargetRef.unit(hero.iun), 1, 1)
	check(Match.players[1].deployments_remaining == before + 1, "The adjacent enemy hero's +1/+1 grants the Thief owner's deployment")
	check(not choose(TargetRef.unit(enemy.iun)) and choose(TargetRef.unit(ally.iun)), "The followup Revive is friendly only")
	check(ally.t_state == Enum.t_state.UNDEPLOYED and thief.effects[0].consequence.verb.name == &"fly", "Thief Revives to hand and retains Fly")

## A loaded unit's live Bow aura ends without ammo or adjacency; its declaration alone offers one step farther away.
func test_hunter() -> void:
	fixture()
	var hunter := add(FrontierCatalogue.rat_hunter(1), 2)
	var attacker := plain(2, 3)
	var empty := plain(1, 4)
	var ref := TargetRef.unit(attacker.iun)
	check(attacker.effective_bow_bonus() == Vector2i.ZERO, "Empty ammunition does not qualify")
	SynergyActions.add_counter(ref, ref, UnitInfo.PROJECTILE_COUNTER, 1)
	check(attacker.effective_bow_bonus() == Vector2i.ONE, "An adjacent loaded enemy gets the same aura as a friend")
	Match.action_event.emit(EffectEvent.new(&"bow", ref, TargetRef.hex(2)))
	declaration(&"bow", empty, TargetRef.hex(2))
	check(not Match.rules_runner.busy(), "Resolution and unloaded declarations offer no retreat")
	var tokens := Match.players[1].actions_remaining
	declaration(&"bow", attacker, TargetRef.hex(2))
	check(not choose(TargetRef.hex(0)) and choose(TargetRef.hex(1)), "Retreat is exactly one step farther from the attacker")
	check(hunter.ihx == 1 and hunter.active and Match.players[1].actions_remaining == tokens, "Retreat pays neither activity nor an action")
	check(attacker.effective_bow_bonus() == Vector2i.ZERO, "The adjacency bonus disappears after retreat")

## Own Bash declarations grant Soul; bounded X survives payment and modifiers expire only at opposing End.
func test_berserker() -> void:
	fixture()
	var berserker := add(FrontierCatalogue.guinea_pig_berserker(1), 0)
	var enemy := plain(2, 4)
	var self_ref := TargetRef.unit(berserker.iun)
	declaration(&"bash", enemy, self_ref)
	check(berserker._counter_value(&"Soul") == 0, "Defending does not award Soul")
	declaration(&"bash", berserker, TargetRef.unit(enemy.iun))
	declaration(&"bash", berserker, TargetRef.unit(enemy.iun))
	check(berserker._counter_value(&"Soul") == 2, "Each own Bash declaration awards one Soul")
	check(play(berserker, 0) and choose(TargetRef.property(self_ref, &"Soul")), "Berserker selects its own Soul balance")
	var payment := Match.rules_runner.active.current
	check(not payment.choose_amount(3) and payment.choose_amount(2), "X cannot exceed the stored balance")
	check(not choose(TargetRef.hex(3)) and choose(TargetRef.hex(2)), "Paid X governs the walk distance")
	check(berserker.ihx == 2 and berserker.active and berserker._counter_value(&"Soul") == 0, "The walk spends only the selected Souls")
	check(berserker.timed_grants.size() == 1 and berserker.timed_grants[0].parameters == [2, 2], "Paid X grants both timed modifier components")
	SynergyActions.add_counter(self_ref, self_ref, &"Soul", 2)
	check(play(berserker, 0) and choose(TargetRef.property(self_ref, &"Soul")), "Another payment can buy the same X")
	check(Match.rules_runner.active.current.choose_amount(2) and choose(TargetRef.hex(0)), "The second paid walk also resolves")
	check(berserker.timed_grants.size() == 2, "Separate paid modifier awards stack even at the same X")
	Match.expire_timed_grants(1, Match.turn_number)
	check(berserker.timed_grants.size() == 2, "Own End does not remove either bonus")
	Match.expire_timed_grants(2, Match.turn_number + 1)
	check(berserker.timed_grants.is_empty(), "Enemy End removes the bonus")

## Merchant alone crosses enemy control while ordinary vacancy, first hero, neutral and Shield checks remain.
func test_merchant() -> void:
	fixture()
	var merchant := add(FrontierCatalogue.mara_merchant(1), -1)
	var ordinary := plain(1, -1)
	var enemy := plain(2, 2)
	check(ControlResolver.region_owner(Match.map[0]) == 2, "Fixture is enemy controlled")
	check(Match.can_deploy(merchant.iun, 0) and not Match.can_deploy(ordinary.iun, 0), "Only Merchant bypasses enemy control")
	check(not Match.can_deploy(merchant.iun, enemy.ihx), "Enemy control exception cannot bypass occupancy")
	Match.players[1].has_deployed = false
	check(not Match.can_deploy(merchant.iun, 0), "Merchant cannot precede the first hero")
	Match.players[1].has_deployed = true
	enemy.ihx = -1
	enemy.t_state = Enum.t_state.UNDEPLOYED
	check(not Match.can_deploy(merchant.iun, 0), "Neutral territory remains ineligible")
	merchant.ihx = 0
	merchant.t_state = Enum.t_state.DEPLOYED
	merchant.active = true
	var ref := TargetRef.unit(merchant.iun)
	check(merchant.control_bonus == 3 and play(merchant, 0) and choose(ref) and choose(ref), "Merchant has +3 control and can pay AS for Shield")
	check(merchant._counter_value(UnitInfo.TEMP_PHYSICAL_COUNTER) == 2, "Shield adds two temporary physical counters")

## An adjacent friend pays exactly two Souls, then the Engineer disables one hand unit of each owner without AS.
func test_engineer() -> void:
	fixture()
	var engineer := add(FrontierCatalogue.beaver_engineer(1), 0)
	var donor := plain(1, 1)
	var distant := plain(1, 3)
	var opponent := plain(2, 4)
	var hand := plain(1, -1)
	var enemy_hand := plain(2, -1)
	for unit in [donor, distant, opponent]:
		SynergyActions.add_counter(TargetRef.unit(engineer.iun), TargetRef.unit(unit.iun), &"Soul", 2)
	var token_count := Match.players[1].actions_remaining
	check(play(engineer, 1), "Both hands have a legal Disable target")
	check(not choose(TargetRef.property(TargetRef.unit(distant.iun), &"Soul")) and not choose(TargetRef.property(TargetRef.unit(opponent.iun), &"Soul")), "Distant and opposing Soul balances cannot pay")
	check(choose(TargetRef.property(TargetRef.unit(donor.iun), &"Soul")), "Adjacent friend pays the exact two Souls")
	check(not choose(TargetRef.unit(enemy_hand.iun)) and choose(TargetRef.unit(hand.iun)), "First Disable accepts only a friend in hand")
	check(not choose(TargetRef.unit(opponent.iun)) and choose(TargetRef.unit(enemy_hand.iun)), "Second Disable requires an opponent in hand")
	check(hand.t_state == Enum.t_state.DEFEATED and enemy_hand.t_state == Enum.t_state.DEFEATED and donor._counter_value(&"Soul") == 0, "Both hand choices are disabled after payment")
	check(engineer.active and Match.players[1].actions_remaining == token_count, "Soul-only command pays no activity or action")

## Crossbowman gains ammo on its own Deploy and permanent Bow damage on own contact only.
func test_crossbowman() -> void:
	fixture()
	var crossbowman := add(FrontierCatalogue.marmot_crossbowman(1), 0)
	var ally := plain(1, 1)
	var enemy := plain(2, 2)
	Match.action_event.emit(EffectEvent.new(&"deploy", TargetRef.unit(ally.iun), TargetRef.hex(1)))
	check(crossbowman._counter_value(UnitInfo.PROJECTILE_COUNTER) == 0, "Another card's Deploy grants no Projectiles")
	Match.action_event.emit(EffectEvent.new(&"deploy", TargetRef.unit(crossbowman.iun), TargetRef.hex(0)))
	check(crossbowman._counter_value(UnitInfo.PROJECTILE_COUNTER) == 2, "Own Deploy grants two Projectiles")
	contact(&"hit", ally, enemy)
	contact(&"wound", crossbowman, enemy)
	check(crossbowman.bow_damage_bonus == 0, "An ally's Hit and a standalone Wound do not qualify")
	contact(&"hit", crossbowman, enemy, &"bow", 0)
	check(crossbowman.bow_damage_bonus == 1 and crossbowman.bow_range_bonus == 0, "Own contact adds damage even when blocked by modifiers")

## The Paladin's pair selects a friend in Bash and the deployed enemy hero, paying only one self-Stun.
func test_paladin() -> void:
	fixture()
	var paladin := add(FrontierCatalogue.red_squirrel_paladin(1), 0)
	var ally := plain(1, 1)
	var bystander := plain(1, 2)
	var enemy := plain(2, 1)
	var hero := plain(2, 3)
	hero.type = Enum.type.HERO
	check(not play(paladin, 1) and paladin.active, "No friendly Bash leaves the protection command unavailable")
	var bash := BashInfo.new()
	bash.attacker_id = ally.iun
	bash.defender_id = enemy.iun
	bash.target_hex = ally.ihx
	Match.bashes.append(bash)
	var tokens := Match.players[1].actions_remaining
	check(paladin.deployment_enemy_side and paladin.effects[0].is_action_free(), "Paladin deploys on the enemy side and Bow costs no action")
	check(play(paladin, 1) and choose(TargetRef.unit(paladin.iun)), "Paladin pays one self-Stun")
	check(not choose(TargetRef.unit(bystander.iun)) and not choose(TargetRef.unit(enemy.iun)), "Nonparticipant friend and Bash enemy cannot take the first Shield")
	check(choose(TargetRef.unit(ally.iun)), "A friendly Bash participant receives Shield")
	check(ally._counter_value(UnitInfo.TEMP_PHYSICAL_COUNTER) == 2 and hero._counter_value(UnitInfo.TEMP_PHYSICAL_COUNTER) == 2, "Only the selected friend and opposing hero gain Shield")
	check(not paladin.active and paladin._counter_value(UnitInfo.STUN_COUNTER) == 1 and Match.players[1].actions_remaining == tokens, "One Stun and no player action pay the pair")

## Pirate's free Walk requires a reachable Bash and buffs only other allies' Walk ranges while deployed.
func test_pirate() -> void:
	fixture()
	var pirate := add(FrontierCatalogue.jerboa_pirate(1), 0)
	var enemy := plain(2, 2)
	var ally := plain(1, 4)
	var ref := TargetRef.unit(pirate.iun)
	check(ally.effective_action_values(&"move", [1]) == [2] and ally.effective_action_values(&"fly", [1]) == [1], "Other friend gains Walk only")
	check(enemy.effective_action_values(&"move", [1]) == [1] and pirate.effective_action_values(&"move", [2]) == [2], "Enemies and SELF gain no movement bonus")
	var tokens := Match.players[1].actions_remaining
	enemy.ihx = 3
	check(CombatResolver.can_move(ref, TargetRef.hex(1), 2, false, true), "An unreachable enemy does not prohibit an empty landing")
	enemy.ihx = 2
	check(play(pirate, 0) and not choose(TargetRef.hex(1)), "A reachable enemy excludes an otherwise legal empty landing")
	check(choose(TargetRef.hex(2)) and pirate.ihx == 2 and Match.bashes.size() == 1, "Free Walk lands on the enemy and declares Bash")
	check(pirate.active and Match.players[1].actions_remaining == tokens, "Compulsory Bash does not add an action or Stun cost")
	Action.return_to_hand(ref, ref)
	check(ally.effective_action_values(&"move", [1]) == [1], "Leaving the board removes the live Walk bonus")

## Exercises the ordinary printed attacks and movement at the advertised range through real retained choices.
func test_printed_commands() -> void:
	var cards := [FrontierCatalogue.mole_shaman(1), FrontierCatalogue.flying_squirrel_thief(1),
		FrontierCatalogue.lemming_wizard(1), FrontierCatalogue.mole_alchemist(1),
		FrontierCatalogue.beaver_engineer(1), FrontierCatalogue.marmot_crossbowman(1),
		FrontierCatalogue.red_squirrel_paladin(1)]
	var ranges := [2, 2, 3, 2, 3, 3, 2]
	for index in cards.size():
		fixture()
		var unit := add(cards[index], 0)
		var reach: int = ranges[index]
		var action: StringName = unit.effects[0].consequence.verb.name
		if action not in [&"move", &"fly"]:
			plain(2, reach)
			plain(2, reach + 1)
		if action == &"fly": plain(1, 1)
		var tokens := Match.players[1].actions_remaining
		check(play(unit, 0) and choose(TargetRef.unit(unit.iun)), "%s starts its printed command and pays activity" % unit.name)
		check(not choose(TargetRef.hex(reach + 1)) and choose(TargetRef.hex(reach)), "%s enforces its printed reach" % unit.name)
		check(not unit.active and unit._counter_value(UnitInfo.STUN_COUNTER) == 1, "%s pays one self-Stun" % unit.name)
		check(Match.players[1].actions_remaining == tokens - (0 if unit == cards.back() else 1), "%s pays its printed action policy" % unit.name)
		match action:
			&"move", &"fly": check(unit.ihx == reach, "%s lands at the chosen hex" % unit.name)
			&"fire": check(Match.pending_attacks.size() == 1, "%s queues Fire" % unit.name)
			&"cannon": check(Match.pending_cannon_attacks.size() == reach, "%s queues the selected Cannon line" % unit.name)
			&"bow": check(Match.pending_bow_attacks.size() == 1, "%s queues Bow" % unit.name)
