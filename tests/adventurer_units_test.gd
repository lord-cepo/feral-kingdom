## Focused adventurer regressions; execution requires a user prompt ending TEST.
extends "res://tests/synergy_units_test.gd"

## Dedicated scene reuses fixture helpers without running the older roster's test entry point.
func _ready() -> void:
	Match.action_event.connect(record)
	test_shaman_across_encounters()
	test_shaman_stale_pair()
	test_shaman_payment_guard()
	test_live_modifiers_and_scout()
	test_berserker_ranger_and_protection()
	test_berserker_stun_only_walk()
	test_rogue_and_hunter()
	test_witch_druid_and_warlock()
	test_summoner()
	test_cleric()
	test_alchemist()
	test_bard_and_healer()
	test_jester()
	test_pirate_blacksmith_and_merchant()
	test_registration()
	test_printed_movement_and_displacement()
	test_printed_stun_and_summoner_shield()
	test_atomic_departures_and_deployments()
	test_counter_bound_command_availability()
	print("Adventurer units: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)

## Builds a pending encounter with stable participant identities for independent-pair selection.
func encounter(first: UnitInfo, second: UnitInfo, hex_id: int) -> BashInfo:
	var bash := BashInfo.new()
	bash.attacker_id = first.iun
	bash.defender_id = second.iun
	bash.target_hex = hex_id
	Match.bashes.append(bash)
	return bash

## One [A] payment permits any two participants, even same-owner units from different encounters; no self-Stun is added.
func test_shaman_across_encounters() -> void:
	fixture()
	var shaman := add(AdventurerCatalogue.porcupine_shaman(1), 0)
	var first := plain(2, 1)
	var first_partner := plain(1, 1)
	var second := plain(2, 3)
	var second_partner := plain(1, 3)
	encounter(first, first_partner, 1)
	encounter(second, second_partner, 3)
	var run := EffectExecution.new(shaman.effects[1], TargetRef.unit(shaman.iun))
	run.start()
	check(run.current.choose(TargetRef.player(1)), "Shaman pays exactly one own deployment")
	check(Match.players[1].deployments_remaining == 2, "Shaman deployment balance decreases once")
	check(run.current.choose(TargetRef.unit(first.iun)), "Shaman accepts an enemy in the first encounter")
	check(first.t_state == Enum.t_state.DEPLOYED, "First choice alone does not Return")
	check(not run.current.choose(TargetRef.unit(first.iun)), "Shaman rejects choosing the same identity twice")
	check(run.current.choose(TargetRef.unit(second.iun)), "Shaman accepts another enemy from a different encounter")
	check(first.t_state == Enum.t_state.UNDEPLOYED and second.t_state == Enum.t_state.UNDEPLOYED, "Both chosen participants Return")
	check(first_partner.t_state == Enum.t_state.DEPLOYED and second_partner.t_state == Enum.t_state.DEPLOYED, "Unchosen Bash partners stay deployed")
	check(shaman.active and shaman._counter_value(UnitInfo.STUN_COUNTER) == 0, "[A] Return does not pay activity or Stun")

## If either retained participant leaves, final selection cannot Return the other or replace the first identity.
func test_shaman_stale_pair() -> void:
	fixture()
	var shaman := add(AdventurerCatalogue.porcupine_shaman(1), 0)
	var first := plain(1, 1)
	var second := plain(2, 1)
	encounter(first, second, 1)
	var run := EffectExecution.new(shaman.effects[1], TargetRef.unit(shaman.iun))
	run.start()
	run.current.choose(TargetRef.player(1))
	run.current.choose(TargetRef.unit(first.iun))
	Action.return_to_hand(TargetRef.unit(shaman.iun), TargetRef.unit(first.iun))
	check(not run.current.choose(TargetRef.unit(second.iun)), "A stale first participant invalidates the complete pair")
	check(second.t_state == Enum.t_state.DEPLOYED, "Failed pair leaves the second participant untouched")
	check(Match.players[1].deployments_remaining == 2, "A paid deployment is not refunded after consequence failure")

## No Bash, resolved encounters, a missing second participant and no deployments cannot fund this command.
func test_shaman_payment_guard() -> void:
	fixture()
	var shaman := add(AdventurerCatalogue.porcupine_shaman(1), 0)
	var source := TargetRef.unit(shaman.iun)
	check(not Match.rules_runner.command_available(shaman.effects[1], source), "No Bash makes Return unavailable")
	var first := plain(1, 1)
	var second := plain(2, 1)
	var bash := encounter(first, second, 1)
	check(Match.rules_runner.command_available(shaman.effects[1], source), "Two opposing participants enable Return")
	bash.resolved = true
	check(not Match.rules_runner.command_available(shaman.effects[1], source), "Resolved Bash participants do not qualify")
	bash.resolved = false
	Match.players[1].deployments_remaining = 0
	check(not Match.rules_runner.command_available(shaman.effects[1], source), "Zero deployments prevents payment")
	check(not AdventurerRules.can_spend_deployment(source, TargetRef.player(2)), "An opponent's deployment cannot pay")

## Starts a production effect and records validation failures before any later choice, preventing silent script-error-only success reports.
func begin(unit: UnitInfo, index: int) -> EffectExecution:
	var run := EffectExecution.new(unit.effects[index], TargetRef.unit(unit.iun))
	run.start()
	check(run.status != EffectExecution.Status.FAILED, "%s effect %d starts: %s" % [unit.name, index, run.error])
	return run

## Berserker's Walk spends only self-Stun, retains enemy-only destinations and rejects wrong-owner/repeated activity.
func test_berserker_stun_only_walk() -> void:
	fixture()
	var unit := add(AdventurerCatalogue.marmot_berserker(1), 0)
	plain(2, 2)
	var opponent := add(AdventurerCatalogue.marmot_berserker(2), 5)
	var walk := unit.effects[0]
	check(walk.is_action_free() and walk.cost_label == &"S", "Berserker Walk is explicitly [S]")
	check(EffectText.describe_effect(walk, unit).contains("[lb]S[rb]"), "Berserker hover exposes the Stun-only cost")
	check(not unit.effects[1].is_action_free(), "Berserker Shield keeps its player-action cost")
	var actions := Match.players[1].actions_remaining
	check(not Match.rules_runner.command_available(opponent.effects[0], TargetRef.unit(opponent.iun)), "Opponent cannot use Berserker Walk on this turn")
	check(Match.rules_runner.submit(walk, TargetRef.unit(unit.iun)) and choose(TargetRef.unit(unit.iun)), "Berserker pays self-Stun for Walk")
	check(not choose(TargetRef.hex(1)) and not choose(TargetRef.hex(5)), "Empty and out-of-range destinations remain illegal")
	check(choose(TargetRef.hex(2)) and unit.ihx == 2, "Berserker Walk reaches the enemy")
	check(not unit.active and unit._counter_value(UnitInfo.STUN_COUNTER) == 1, "Walk deactivates and pays exactly one Stun")
	check(Match.players[1].actions_remaining == actions, "Committed [S] Walk preserves player actions")
	check(not Match.rules_runner.command_available(walk, TargetRef.unit(unit.iun)), "Inactive Berserker cannot repeat Walk")

## Barbarian/Druid modifiers are derived and Scout's allowance follows geography even under enemy control.
func test_live_modifiers_and_scout() -> void:
	fixture()
	var barbarian := add(AdventurerCatalogue.porcupine_barbarian(1), 1)
	var friend := plain(1, 0)
	plain(2, 2)
	var ctx := RuleContext.new(TargetRef.unit(barbarian.iun))
	check(barbarian.state_effects[0].evaluate(ctx) == Vector2i.ONE, "Only adjacent friends count for Barbarian")
	friend.ihx = 5
	check(barbarian.state_effects[0].evaluate(ctx) == Vector2i.ZERO, "Moving a friend removes both modifiers without counters")
	check(barbarian._counter_value(UnitInfo.PHYSICAL_COUNTER) == 0, "Barbarian reads never accumulate stored counters")
	var druid := add(AdventurerCatalogue.red_squirrel_druid(1), 3)
	druid.max_life = 5
	druid.actual_life = 1
	check(druid.state_effects[0].evaluate(RuleContext.new(TargetRef.unit(druid.iun))) == Vector2i(3, 3), "Druid counts maximum rather than current life")
	var scout := add(AdventurerCatalogue.jerboa_scout(1), 4)
	Match.map[4].region = Enum.region.STARTING
	Match.map[4].side = Enum.side.P2
	var base := Match.players[1].actions_remaining
	check(SynergyRules.player_action_bonus(1) == 1, "Scout on enemy Starting grants its owner one action")
	check(SynergyRules.player_action_bonus(2) == 0, "Scout grants no opposing action")
	scout.ihx = 5
	check(Match.players[1].actions_remaining == base - 1, "Leaving enemy Starting removes the allowance")
	scout.ihx = 4
	check(Match.players[1].actions_remaining == base, "Reentry restores the same allowance without refilling spent actions")

## Restricted enemy Walk, Pierce Bow and magical/physical protection retain their exact targets and non-target exclusions.
func test_berserker_ranger_and_protection() -> void:
	fixture()
	var berserker := add(AdventurerCatalogue.marmot_berserker(1), 0)
	plain(2, 2)
	var destinations := AdventurerRules.EnemyDestinations.new().resolve(RuleContext.new(TargetRef.unit(berserker.iun)))
	check(destinations.size() == 1 and destinations[0].id == 2, "Berserker offers the enemy within two, excluding empty tiles")
	var run := begin(berserker, 1)
	run.current.choose(TargetRef.unit(berserker.iun))
	run.current.choose(TargetRef.unit(berserker.iun))
	check(berserker._counter_value(UnitInfo.TEMP_PHYSICAL_COUNTER) == 2, "Berserker gets Shield two at range zero")
	fixture()
	var ranger := add(AdventurerCatalogue.flying_squirrel_ranger(1), 1)
	var friend := plain(1, 2)
	var enemy := plain(2, 0)
	check(ranger.effects[0].consequence.verb.user_params[3], "Ranger's Bow is printed Pierce")
	run = begin(ranger, 1)
	run.current.choose(TargetRef.unit(ranger.iun))
	check(not run.current.choose(TargetRef.unit(enemy.iun)), "Ranger cannot Mshield an enemy")
	run.current.choose(TargetRef.unit(friend.iun))
	check(friend._counter_value(UnitInfo.TEMP_MAGICAL_COUNTER) == 1, "Ranger Mshields adjacent friend")
	fixture()
	var monk := add(AdventurerCatalogue.marmot_monk(1), 0)
	friend = plain(1, 5)
	enemy = plain(2, 3)
	for index in 2:
		monk.active = true
		run = begin(monk, index)
		run.current.choose(TargetRef.unit(monk.iun))
		check(not run.current.choose(TargetRef.unit(enemy.iun)), "Monk never shields an enemy")
		run.current.choose(TargetRef.unit(friend.iun))
	check(friend._counter_value(UnitInfo.TEMP_PHYSICAL_COUNTER) == 1 and friend._counter_value(UnitInfo.TEMP_MAGICAL_COUNTER) == 1,
		"Monk's two independent commands reach a distant friend")

## Rogue transfers the exact selected kind and defeats only enemies; Hunter spends an adjacent friend's counter before Reset.
func test_rogue_and_hunter() -> void:
	fixture()
	var rogue := add(AdventurerCatalogue.dormouse_rogue(1), 0)
	var enemy := plain(2, 1)
	var friend := plain(1, 2)
	enemy._change_action_counter(&"Soul", 2)
	var run := begin(rogue, 0)
	run.current.choose(TargetRef.unit(rogue.iun))
	check(not run.current.choose(TargetRef.property(TargetRef.unit(friend.iun), UnitInfo.STUN_COUNTER)), "Rogue cannot steal a friendly counter")
	run.current.choose(TargetRef.property(TargetRef.unit(enemy.iun), &"Soul"))
	check(enemy._counter_value(&"Soul") == 1 and rogue._counter_value(&"Soul") == 1, "Rogue takes and gains one of the same kind")
	rogue.active = true
	run = begin(rogue, 1)
	run.current.choose(TargetRef.unit(rogue.iun))
	run.current.choose(TargetRef.property(TargetRef.unit(rogue.iun), &"Soul"))
	check(not run.current.choose(TargetRef.unit(friend.iun)), "Rogue cannot defeat a friendly target")
	run.current.choose(TargetRef.unit(enemy.iun))
	check(enemy.t_state == Enum.t_state.DEFEATED, "Rogue defeats the selected enemy")
	fixture()
	var hunter := add(AdventurerCatalogue.tamia_hunter(1), 0)
	friend = plain(1, 1)
	enemy = plain(2, 2)
	friend._change_action_counter(&"Soul", 1)
	enemy.actual_life = 2
	run = begin(hunter, 0)
	run.current.choose(TargetRef.unit(hunter.iun))
	run.current.choose(TargetRef.property(TargetRef.unit(friend.iun), &"Soul"))
	run.current.choose(TargetRef.unit(enemy.iun))
	check(enemy.actual_life == enemy.max_life and friend._counter_value(&"Soul") == 0, "Hunter resets either owner within two after friendly counter payment")
	check(hunter.control_bonus == 2, "Hunter has printed regional control two")

## Witch's permanent damage survives Ember consumption, Druid grows maximum only, and Warlock disables without inventing Die.
func test_witch_druid_and_warlock() -> void:
	fixture()
	var witch := add(AdventurerCatalogue.dormouse_witch(1), 0)
	var friend := plain(1, 3)
	friend._change_action_counter(UnitInfo.EMBER_COUNTER, 1)
	var run := begin(witch, 2)
	run.current.choose(TargetRef.unit(witch.iun))
	run.current.choose(TargetRef.property(TargetRef.unit(friend.iun), UnitInfo.EMBER_COUNTER))
	check(witch.effective_action_values(&"fire", [1, 2]) == [2, 2], "Witch buys permanent damage without range")
	check(friend._counter_value(UnitInfo.EMBER_COUNTER) == 0, "Witch pays the friendly Ember")
	fixture()
	var druid := add(AdventurerCatalogue.red_squirrel_druid(1), 0)
	druid._change_action_counter(&"Soul", 1)
	run = begin(druid, 0)
	run.current.choose(TargetRef.unit(druid.iun))
	run.current.choose(TargetRef.property(TargetRef.unit(druid.iun), &"Soul"))
	check(druid.max_life == 3 and druid.actual_life == 2 and druid._counter_value(&"Soul") == 0, "Druid trades one Soul for maximum life only")
	fixture()
	var warlock := add(AdventurerCatalogue.rat_warlock(1), 0)
	friend = plain(1, -1)
	var enemy_hand := plain(2, -1)
	run = begin(warlock, 1)
	run.current.choose(TargetRef.unit(warlock.iun))
	check(not run.current.choose(TargetRef.unit(enemy_hand.iun)), "Warlock cannot pay with enemy hand card")
	run.current.choose(TargetRef.unit(friend.iun))
	check(friend.t_state == Enum.t_state.DEFEATED and warlock._counter_value(UnitInfo.STUN_COUNTER) == 3, "Warlock pays Disable and three self-Stun")
	run.current.choose(TargetRef.unit(friend.iun))
	check(friend.t_state == Enum.t_state.UNDEPLOYED and friend.actual_life == friend.max_life, "Warlock may Revive the card it just disabled")
	check(not events.any(func(event: EffectEvent) -> bool: return event.action == &"die"), "Disable/Revive never invent Die")

## Summoner may choose the same returned identity; the destination follows paid historical position without extra deployment spending.
func test_summoner() -> void:
	fixture()
	var summoner := add(AdventurerCatalogue.mouse_summoner(1), 0)
	var friend := plain(1, 4)
	var enemy_hand := plain(2, -1)
	friend.actual_life = 3
	check(Match.rules_runner.command_available(summoner.effects[1], TargetRef.unit(summoner.iun)), "Exchange is available with no preexisting friendly hand card")
	var run := begin(summoner, 1)
	run.current.choose(TargetRef.unit(summoner.iun))
	run.current.choose(TargetRef.unit(friend.iun))
	check(friend.t_state == Enum.t_state.UNDEPLOYED, "Return cost places friend in hand")
	check(not run.current.choose(TargetRef.unit(enemy_hand.iun)), "Summoner cannot deploy an enemy hand card")
	run.current.choose(TargetRef.unit(friend.iun))
	check(friend.t_state == Enum.t_state.DEPLOYED and friend.ihx == 4 and friend.actual_life == 3, "Same friend redeploys at captured hex, preserving health")
	check(not friend.active and friend._counter_value(UnitInfo.STUN_COUNTER) == 1, "Effect deployment enters inactive with normal one Stun")
	check(Match.players[1].deployments_remaining == 3, "Exchange does not spend an additional deployment")

## Cleric selects zero-valued existing counters and observes either owner's Return, excluding absent counters and nonadjacent recipients.
func test_cleric() -> void:
	fixture()
	var cleric := add(AdventurerCatalogue.guinea_pig_cleric(1), 0)
	var friend := plain(1, 1)
	var distant := plain(1, 4)
	var enemy := plain(2, 2)
	var run := begin(cleric, 0)
	run.current.choose(TargetRef.unit(cleric.iun))
	check(not run.current.choose(TargetRef.property(TargetRef.unit(friend.iun), &"Soul")), "Cleric cannot create a missing Soul kind")
	check(not run.current.choose(TargetRef.property(TargetRef.unit(distant.iun), UnitInfo.PHYSICAL_COUNTER)), "Cleric excludes distant friend")
	run.current.choose(TargetRef.property(TargetRef.unit(friend.iun), UnitInfo.PHYSICAL_COUNTER))
	check(friend._counter_value(UnitInfo.PHYSICAL_COUNTER) == 1, "Cleric can increment existing physical at zero")
	friend.actual_life = 1
	Action.return_to_hand(TargetRef.unit(enemy.iun), TargetRef.unit(enemy.iun))
	check(Match.rules_runner.active != null, "Enemy Return captures Cleric Reset")
	choose(TargetRef.unit(friend.iun))
	check(friend.actual_life == friend.max_life, "Cleric's Return trigger resets chosen unit")
	check(EffectText.describe_effect(cleric.effects[0], cleric).contains("already-present"), "Cleric effect explains existing counter restriction")

## Each positive friendly Ember addition pays one Soul regardless of size; zero/removal/enemy awards do not trigger.
func test_alchemist() -> void:
	fixture()
	var alchemist := add(AdventurerCatalogue.chinchilla_alchemist(1), 0)
	var friend := plain(1, 1)
	var enemy := plain(2, 2)
	friend._change_action_counter(UnitInfo.EMBER_COUNTER, 3)
	enemy._change_action_counter(UnitInfo.EMBER_COUNTER, 2)
	friend._change_action_counter(UnitInfo.EMBER_COUNTER, 0)
	friend._change_action_counter(UnitInfo.EMBER_COUNTER, -1)
	check(alchemist._counter_value(&"Soul") == 1, "Only positive friendly addition pays once, independent of Ember amount")
	Action.change_counter(TargetRef.unit(alchemist.iun), TargetRef.property(TargetRef.unit(friend.iun), UnitInfo.EMBER_COUNTER), 2)
	check(alchemist._counter_value(&"Soul") == 2, "PROPERTY-targeted Ember addition shares the canonical occurrence")
	alchemist._change_action_counter(&"Soul", 1)
	var run := begin(alchemist, 0)
	run.current.choose(TargetRef.unit(alchemist.iun))
	run.current.choose(TargetRef.property(TargetRef.unit(alchemist.iun), &"Soul"))
	run.current.choose(TargetRef.hex(2))
	check(alchemist._counter_value(&"Soul") == 0 and Match.pending_attacks.is_empty(), "Alchemist spends three Soul for Instant rather than queued Fire")

## Bard boosts both owners only at exact adjacency; Healer mends friends within two and never enemy recipients.
func test_bard_and_healer() -> void:
	fixture()
	var bard := add(AdventurerCatalogue.tamia_bard(1), 1)
	var friend := plain(1, 0)
	var enemy := plain(2, 2)
	var distant := plain(1, 5)
	check(friend.effective_bow_bonus() == Vector2i(1, 0) and enemy.effective_bow_bonus() == Vector2i(1, 0), "Bard gives both adjacent owners Bow damage only")
	check(distant.effective_bow_bonus() == Vector2i.ZERO and bard.effective_bow_bonus() == Vector2i.ZERO, "Bard excludes distant units and itself")
	bard.t_state = Enum.t_state.UNDEPLOYED
	check(enemy.effective_bow_bonus() == Vector2i.ZERO, "Bard aura disappears on departure")
	fixture()
	var healer := add(AdventurerCatalogue.lemming_healer(1), 0)
	friend = plain(1, 2)
	enemy = plain(2, 1)
	friend.actual_life = 3
	var run := begin(healer, 1)
	run.current.choose(TargetRef.unit(healer.iun))
	check(not run.current.choose(TargetRef.unit(enemy.iun)), "Healer cannot mend an enemy")
	run.current.choose(TargetRef.unit(friend.iun))
	check(friend.actual_life == 4, "Healer mends one within two")

## A new enemy region owner captures one Instant Bow; repeated refresh, another region, and friendly ownership do not retrigger.
func test_jester() -> void:
	fixture()
	var jester := add(AdventurerCatalogue.jerboa_jester(1), 0)
	var enemy := plain(2, 2)
	enemy.actual_life = 1
	Match.refresh_control()
	check(Match.rules_runner.active == null, "Friendly control does not trigger Jester")
	enemy.actual_life = 8
	Match.refresh_control()
	check(Match.rules_runner.active != null, "Enemy gaining Jester's region captures Bow")
	choose(TargetRef.hex(enemy.ihx))
	check(events.any(func(event: EffectEvent) -> bool: return event.action == &"bow" and event.stage == &"target"), "Jester declares its captured Bow")
	check(Match.pending_bow_attacks.is_empty(), "Jester's Bow resolves instantly")
	Match.refresh_control()
	check(Match.rules_runner.active == null, "Unchanged control cannot recapture Jester")
	Match.map[5].region_count = 1
	var elsewhere := plain(2, 5)
	Match.refresh_control()
	check(Match.rules_runner.active == null, "Enemy gaining a different region does not trigger Jester")
	var snapshot: Dictionary = preload("res://scripts/runtime/match_snapshot.gd")._capture_state()
	for tile in Match.map: tile.control = Enum.control.NONE
	preload("res://scripts/runtime/match_snapshot.gd")._apply_state(snapshot)
	check(Match.rules_runner.active == null and elsewhere.t_state == Enum.t_state.DEPLOYED, "Snapshot cache rebuild does not invent a control-gain trigger")
	check(jester.trigger_effects.size() == 1, "Jester has one control watcher")

## Pirate/Blacksmith use native flags; Merchant earns only friendly death Soul and grants recipient-bound next-Fire P/F once.
func test_pirate_blacksmith_and_merchant() -> void:
	fixture()
	var pirate := add(AdventurerCatalogue.rat_pirate(1), 0)
	var smith := add(AdventurerCatalogue.beaver_blacksmith(1), 2)
	check(pirate.has_effective_flag(&"fast") and smith.has_effective_flag(&"fast") and smith.has_effective_flag(&"steady"), "Pirate/Blacksmith expose their native Bash passives")
	pirate.active = false
	check(Match.rules_runner.command_available(pirate.effects[0], TargetRef.unit(pirate.iun)), "Pirate [A] Walk remains available inactive")
	fixture()
	var merchant := add(AdventurerCatalogue.guinea_pig_merchant(1), 0)
	var friend := plain(1, 1)
	var enemy := plain(2, 3)
	Match.defeat(TargetRef.unit(enemy.iun), 1)
	check(merchant._counter_value(&"Soul") == 0, "Enemy death does not reward Merchant")
	Match.defeat(TargetRef.unit(friend.iun), 2)
	check(merchant._counter_value(&"Soul") == 1, "Friendly death rewards Merchant once")
	friend = plain(1, 1)
	merchant._change_action_counter(&"Soul", 1)
	for index in 2:
		merchant.active = true
		var run := begin(merchant, index)
		run.current.choose(TargetRef.unit(merchant.iun))
		run.current.choose(TargetRef.property(TargetRef.unit(merchant.iun), &"Soul"))
		run.current.choose(TargetRef.unit(friend.iun))
	check(friend.next_fire_stickers.size() == 2 and merchant.next_fire_stickers.is_empty(), "Both next-Fire stickers are recipient-bound")
	check(not Action.fire(TargetRef.unit(friend.iun), TargetRef.hex(-1), 1), "Invalid Fire cannot declare")
	check(friend.next_fire_stickers.size() == 2, "Failed Fire preserves pending stickers")
	enemy = plain(2, 2)
	check(Action.fire(TargetRef.unit(friend.iun), TargetRef.hex(2), 1), "Recipient declares Fire")
	check(friend.next_fire_stickers.is_empty() and Match.pending_attacks.is_empty(), "Instant/Pierce combine and consume only on successful declaration")
	friend.next_fire_stickers.append(&"pierce")
	var snapshot: Dictionary = preload("res://scripts/runtime/match_snapshot.gd")._capture_state()
	check(snapshot.units[friend.iun].next_fire_stickers == [&"pierce"], "Snapshot retains pending recipient sticker")
	friend.next_fire_stickers.clear()
	preload("res://scripts/runtime/match_snapshot.gd")._apply_state(snapshot)
	check(friend.next_fire_stickers == [&"pierce"], "Snapshot restore reinstates the exact recipient's pending sticker")
	friend.reset_printed_state()
	check(friend.next_fire_stickers.is_empty(), "Reset clears pending next-Fire stickers")

## Catalogue integration preserves twenty distinct names, player identities and explanatory effect text.
func test_registration() -> void:
	var cards := AdventurerCatalogue.all_units(1)
	check(cards.size() == 20, "All twenty adventurer factories are registered")
	var army := CardCatalogue.starter_army()
	check(army.size() == 194, "Both players receive the expanded 97-card roster")
	var ids: Dictionary = {}
	for unit in cards:
		check(not ids.has(unit.uuid), "Adventurer UUIDs are distinct")
		ids[unit.uuid] = true
		check(unit.player == 1 and unit.max_life > 0, "Printed owner/life are populated")
		check(not EffectText.unit_lines(unit).is_empty(), "Every adventurer has readable rules")
		check(army.any(func(card: UnitInfo) -> bool: return card.uuid == unit.uuid), "Player one's adventurer is playable")
		check(army.any(func(card: UnitInfo) -> bool: return card.uuid == unit.uuid.replace("-p1", "-p2")), "Player two has the matching adventurer")
		var key := unit.uuid.trim_suffix("-p1")
		check(BoardCharacter.MAPPED_CARDS.has(key), "Every adventurer has its sprite mapping")

## Each printed movement profile uses its own range/payment, and Bard/Jester retain their opposite displacement directions.
func test_printed_movement_and_displacement() -> void:
	for factory in [AdventurerCatalogue.porcupine_barbarian, AdventurerCatalogue.jerboa_scout,
			AdventurerCatalogue.rat_pirate, AdventurerCatalogue.lemming_healer]:
		fixture()
		var unit := add(factory.call(1), 0)
		var run := begin(unit, 0)
		var tireless := unit.name in ["Jerboa Scout", "Rat Pirate"]
		if not tireless: run.current.choose(TargetRef.unit(unit.iun))
		check(not run.current.choose(TargetRef.hex(3)), "%s excludes a destination beyond two" % unit.name)
		run.current.choose(TargetRef.hex(2))
		check(unit.ihx == 2, "%s completes its printed Walk two" % unit.name)
		check(unit.active == tireless and unit._counter_value(UnitInfo.STUN_COUNTER) == (0 if tireless else 1), "%s uses its printed activity policy" % unit.name)
	fixture()
	var witch := add(AdventurerCatalogue.dormouse_witch(1), 0)
	plain(1, 1)
	var run := begin(witch, 0)
	run.current.choose(TargetRef.unit(witch.iun))
	run.current.choose(TargetRef.hex(2))
	check(witch.ihx == 2, "Witch's Fly crosses an occupied intermediate hex")
	fixture()
	var berserker := add(AdventurerCatalogue.marmot_berserker(1), 0)
	plain(2, 2)
	run = begin(berserker, 0)
	run.current.choose(TargetRef.unit(berserker.iun))
	check(not run.current.choose(TargetRef.hex(1)), "Berserker rejects an empty destination despite legal distance")
	run.current.choose(TargetRef.hex(2))
	check(berserker.ihx == 2 and Match.bashes.size() == 1, "Berserker reaches enemy and starts Bash")
	for pulling in [false, true]:
		fixture()
		var unit := add(AdventurerCatalogue.jerboa_jester(1) if pulling else AdventurerCatalogue.tamia_bard(1), 0)
		var enemy := plain(2, 2 if pulling else 1)
		run = begin(unit, 0)
		run.current.choose(TargetRef.unit(unit.iun))
		run.current.choose(TargetRef.unit(enemy.iun))
		check(enemy.ihx == (1 if pulling else 2), "Jester Pull/Bard Push move one in the printed direction")

## Shaman/Warlock hostile Stun preserves friendly/range exclusions and the distinct three-S versus normal payment policies.
func test_printed_stun_and_summoner_shield() -> void:
	for shaman_card in [true, false]:
		fixture()
		var unit := add(AdventurerCatalogue.porcupine_shaman(1) if shaman_card else AdventurerCatalogue.rat_warlock(1), 0)
		var friend := plain(1, 1)
		var enemy := plain(2, 2)
		var distant := plain(2, 4)
		var run := begin(unit, 0)
		run.current.choose(TargetRef.unit(unit.iun))
		check(not run.current.choose(TargetRef.unit(friend.iun)), "Printed hostile Stun excludes friends")
		check(not run.current.choose(TargetRef.unit(distant.iun)), "Printed hostile Stun excludes distant enemies")
		run.current.choose(TargetRef.unit(enemy.iun))
		check(enemy._counter_value(UnitInfo.STUN_COUNTER) == (2 if shaman_card else 1) and not enemy.active, "Printed Stun adds its amount and deactivates enemy")
		check(unit._counter_value(UnitInfo.STUN_COUNTER) == (3 if shaman_card else 1), "Printed Stun pays the correct source activity amount")
	fixture()
	var summoner := add(AdventurerCatalogue.mouse_summoner(1), 0)
	var friend := plain(1, 1)
	var enemy := plain(2, 2)
	var run := begin(summoner, 0)
	run.current.choose(TargetRef.unit(summoner.iun))
	check(not run.current.choose(TargetRef.unit(enemy.iun)), "Summoner's Mshield excludes enemy recipients")
	run.current.choose(TargetRef.unit(friend.iun))
	check(friend._counter_value(UnitInfo.TEMP_MAGICAL_COUNTER) == 2, "Summoner grants Mshield two to adjacent friend")
	fixture()
	var ranger := add(AdventurerCatalogue.flying_squirrel_ranger(1), 0)
	plain(2, 3)
	run = begin(ranger, 0)
	run.current.choose(TargetRef.unit(ranger.iun))
	run.current.choose(TargetRef.hex(3))
	check(Match.pending_bow_attacks.size() == 1 and Match.pending_bow_attacks[0].pierce, "Ranger queues Pierce Bow at its printed range three")

## Cumulative deployment payments and stale Return identities fail without committing any earlier bundle resource.
func test_atomic_departures_and_deployments() -> void:
	fixture()
	var shaman := add(AdventurerCatalogue.porcupine_shaman(1), 0)
	var friend := plain(1, 1)
	var enemy := plain(2, 1)
	encounter(friend, enemy, 1)
	var effect := AdventurerRules.shaman_return()
	var payment: Effect.CostPhrase = effect.cost
	effect.cost = Effect.CostBundle.new([payment, payment])
	Match.players[1].deployments_remaining = 1
	check(not Match.rules_runner.command_available(effect, TargetRef.unit(shaman.iun)), "Availability rejects cumulative deployment overspending")
	var run := EffectExecution.new(effect, TargetRef.unit(shaman.iun))
	run.start()
	run.current.choose(TargetRef.player(1))
	run.current.choose(TargetRef.player(1))
	check(run.status == EffectExecution.Status.FAILED and Match.players[1].deployments_remaining == 1, "Atomic deployment ledger rejects all payment before mutation")
	fixture()
	var summoner := add(AdventurerCatalogue.mouse_summoner(1), 0)
	friend = plain(1, 1)
	run = begin(summoner, 1)
	run.current.choose(TargetRef.unit(summoner.iun))
	friend.t_state = Enum.t_state.UNDEPLOYED
	friend.ihx = -1
	check(not run.current.choose(TargetRef.unit(friend.iun)), "Return cost cannot substitute a departed recipient")
	check(summoner.active and summoner._counter_value(UnitInfo.STUN_COUNTER) == 0, "Failed Return bundle preserves source activity")

## Rogue availability must bind the exact payable donor kind through its reward without granting counters or accepting a conflicting FLAG.
func test_counter_bound_command_availability() -> void:
	for owner in [1, 2]:
		fixture()
		Match.active_player = owner
		var rogue := add(AdventurerCatalogue.dormouse_rogue(owner), 0)
		var enemy := plain(3 - owner, 1)
		enemy._change_action_counter(&"Soul", 2)
		var source := TargetRef.unit(rogue.iun)
		check(Match.rules_runner.command_available(rogue.effects[0], source), "Counter-bound command is available for either owner before payment")
		check(rogue._counter_property(&"Soul") == null and enemy._counter_value(&"Soul") == 2 and rogue.active \
			and rogue._counter_value(UnitInfo.STUN_COUNTER) == 0, "Availability creates no reward counter and pays no activity/donor cost")
		var flag := Prop.new()
		flag.name = &"Soul"
		flag.increment = Enum.p_increment.FLAG
		flag.target = Enum.p_target.UNIT
		flag.value = 1
		rogue.props.append(flag)
		check(not Match.rules_runner.command_available(rogue.effects[0], source), "An incompatible existing reward FLAG makes that donor kind unusable")
		enemy._change_action_counter(UnitInfo.PHYSICAL_COUNTER, 1)
		check(Match.rules_runner.command_available(rogue.effects[0], source), "Availability explores another payable kind after an unusable first reward")
		check(enemy._counter_value(UnitInfo.PHYSICAL_COUNTER) == 1 and events.is_empty(), "Exploring alternate payments emits no events and preserves resources")
