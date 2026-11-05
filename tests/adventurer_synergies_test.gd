## Cross-roster behavioral chains through the authoritative runner; run only after an explicit TEST request.
extends "res://tests/adventurer_units_test.gd"

## Runs multi-card payment, captured-trigger and continuous-grant chains instead of repeating isolated card assertions.
func _ready() -> void:
	Match.action_event.connect(record)
	test_summoner_cleric_followups()
	test_shaman_cleric_batch()
	test_warlock_disable_engines()
	test_druid_growth_watchers()
	test_bard_guardian_ranger()
	test_ember_witch_and_merchants()
	test_scout_pikeman_spent_actions()
	test_cleric_hunter_end_recovery()
	test_cleric_counters_and_opposing_rogue()
	print("Adventurer synergies: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)

## Starts one managed command, checking HUD availability and actual submission before later choices.
func submit(unit: UnitInfo, index: int) -> bool:
	var source := TargetRef.unit(unit.iun)
	var available := Match.rules_runner.command_available(unit.effects[index], source)
	check(available, "%s command is available before paying" % unit.name)
	if not available: return false
	var accepted := Match.rules_runner.submit(unit.effects[index], source)
	check(accepted, "%s command is retained by the runner" % unit.name)
	return accepted

## Submits a specific identity to the current command/trigger and reports missing continuations as assertions, not nil-call exceptions.
func take(ref: TargetRef) -> bool:
	var active := Match.rules_runner.active
	if active == null or active.current == null:
		check(false, "Expected a retained phrase for " + ref.label())
		return false
	var accepted := active.current.choose(ref)
	check(accepted, "Managed phrase accepts " + ref.label())
	return accepted

## Counts actual resolved event occurrences, excluding declaration stages and resource snapshots.
func count_event(action: StringName) -> int:
	return events.filter(func(event: EffectEvent) -> bool: return event.action == action and event.stage == &"resolved").size()

## Cleric's cost followup may Reset the returned hand card before Summoner redeploys that same identity at the retained historical hex.
func test_summoner_cleric_followups() -> void:
	fixture()
	var summoner := add(AdventurerCatalogue.mouse_summoner(1), 0)
	var friend := plain(1, 1)
	var cleric := add(AdventurerCatalogue.guinea_pig_cleric(1), 2)
	friend.actual_life = 2
	friend._change_action_counter(&"Soul", 3)
	var before := Match.players[1].base_actions_remaining
	if not submit(summoner, 1): return
	if not take(TargetRef.unit(summoner.iun)) or not take(TargetRef.unit(friend.iun)): return
	check(friend.t_state == Enum.t_state.UNDEPLOYED, "Return cost commits before Cleric followup")
	check(Match.rules_runner.active.source.id == cleric.iun, "Cleric Reset runs before the deployment consequence")
	if not take(TargetRef.unit(friend.iun)): return
	check(friend.actual_life == friend.max_life and friend._counter_value(&"Soul") == 0, "Reset in hand restores printed state before redeployment")
	if not take(TargetRef.unit(friend.iun)): return
	check(friend.t_state == Enum.t_state.DEPLOYED and friend.ihx == 1, "Summoner still uses the returned identity's captured hex")
	check(friend._counter_value(UnitInfo.STUN_COUNTER) == 1 and not friend.active, "Deployment Stun is applied after the intervening Reset")
	check(Match.players[1].base_actions_remaining == before - 1 and Match.players[1].deployments_remaining == 3, "Whole chain spends one action and no deployment")
	check(count_event(&"return_to_hand") == 1 and count_event(&"reset") == 1 and count_event(&"deploy") == 1, "Exchange publishes exactly one Return, Reset and Deploy")
	check(not Match.rules_runner.busy() and Match.rules_runner.diagnostics.is_empty(), "Exchange releases all captured work")

## Both chosen Bash participants leave before either Cleric trigger asks for Reset, even across separate encounters.
func test_shaman_cleric_batch() -> void:
	fixture()
	var shaman := add(AdventurerCatalogue.porcupine_shaman(1), 0)
	var first := plain(1, 1)
	var first_enemy := plain(2, 1)
	var second := plain(1, 3)
	var second_enemy := plain(2, 3)
	var cleric := add(AdventurerCatalogue.guinea_pig_cleric(1), 5)
	encounter(first, first_enemy, 1)
	encounter(second, second_enemy, 3)
	var before := Match.players[1].base_actions_remaining
	if not submit(shaman, 1): return
	if not take(TargetRef.player(1)) or not take(TargetRef.unit(first.iun)): return
	check(first.t_state == Enum.t_state.DEPLOYED and count_event(&"return_to_hand") == 0, "First Shaman choice produces no Return or Cleric trigger")
	if not take(TargetRef.unit(second.iun)): return
	check(first.t_state == Enum.t_state.UNDEPLOYED and second.t_state == Enum.t_state.UNDEPLOYED, "Both participants leave before followups")
	check(Match.rules_runner.active.source.id == cleric.iun, "Cleric receives the retained Return followups")
	if not take(TargetRef.unit(first.iun)) or not take(TargetRef.unit(second.iun)): return
	check(count_event(&"return_to_hand") == 2 and count_event(&"reset") == 2, "Each Return captures Cleric once")
	check(first_enemy.t_state == Enum.t_state.DEPLOYED and second_enemy.t_state == Enum.t_state.DEPLOYED, "Neither unchosen partner Returns")
	check(Match.players[1].deployments_remaining == 2 and Match.players[1].base_actions_remaining == before - 1, "Two-Return chain pays one deployment and one action")
	check(not Match.rules_runner.busy(), "Batch followups finish before command completion")

## Warlock's Disable creates its own Revive candidate, triggers Mara, excludes Blue Mage self-cost reactions and never rewards Merchant death.
func test_warlock_disable_engines() -> void:
	fixture()
	var warlock := add(AdventurerCatalogue.rat_warlock(1), 0)
	var mara := add(CardCatalogue.wild_mara(1), 1)
	var merchant := add(AdventurerCatalogue.guinea_pig_merchant(1), 2)
	add(SynergyCatalogue.tamia_blue_mage(1), 3)
	var hand := plain(1, -1)
	var enemy_hand := plain(2, -1)
	var before := Match.players[1].base_actions_remaining
	if not submit(warlock, 1): return
	if not take(TargetRef.unit(warlock.iun)): return
	check(not choose(TargetRef.unit(enemy_hand.iun)), "Warlock cannot fund the chain with an enemy hand card")
	if not take(TargetRef.unit(hand.iun)): return
	check(hand.t_state == Enum.t_state.DEFEATED and mara.action_counter(UnitInfo.CANNON_DAMAGE_COUNTER) == 1, "Friendly Disable awards Mara Cannon damage before Revive selection")
	check(warlock._counter_value(UnitInfo.STUN_COUNTER) == 3, "Blue Mage does not amplify the three self-Stun payment")
	if not take(TargetRef.unit(hand.iun)): return
	check(hand.t_state == Enum.t_state.UNDEPLOYED and hand.actual_life == hand.max_life, "Paid ordinary command Revives the card just disabled")
	check(merchant._counter_value(&"Soul") == 0 and count_event(&"die") == 0, "Disable/Revive never masquerades as death")
	check(count_event(&"disable") == 1 and count_event(&"revive") == 1 and count_event(&"return_to_hand") == 1, "Zone recovery publishes its three distinct occurrences once")
	check(Match.players[1].base_actions_remaining == before, "[3S] chain spends no player action")

## A single Druid maximum-life increase feeds Explorer's magic and Wild Red Squirrel's captured Instant Bow without recursive growth.
func test_druid_growth_watchers() -> void:
	fixture()
	var druid := add(AdventurerCatalogue.red_squirrel_druid(1), 0)
	var explorer := add(CardCatalogue.red_squirrel_explorer(1), 1)
	var squirrel := add(CardCatalogue.wild_red_squirrel(1), 2)
	var enemy := plain(2, 3)
	druid._change_action_counter(&"Soul", 1)
	if not submit(druid, 0): return
	if not take(TargetRef.unit(druid.iun)) or not take(TargetRef.property(TargetRef.unit(druid.iun), &"Soul")): return
	check(druid.actual_life == 2 and druid.max_life == 3, "Druid increases only maximum life")
	check(druid.state_effects[0].evaluate(RuleContext.new(TargetRef.unit(druid.iun))) == Vector2i.ONE, "Druid's live modifier sees the same growth")
	check(explorer._counter_value(UnitInfo.PHYSICAL_COUNTER) == 0 and explorer._counter_value(UnitInfo.MAGICAL_COUNTER) == 1, "Explorer copies only the actual positive maximum component")
	check(Match.rules_runner.active.source.id == squirrel.iun, "Wild Squirrel retains one triggered Bow choice")
	if not take(TargetRef.hex(enemy.ihx)): return
	check(Match.pending_bow_attacks.is_empty() and count_event(&"life_increase") == 1, "Captured Bow is instant and its bonuses do not invent new life increases")
	check(not Match.rules_runner.busy(), "Growth chain fully drains")

## Two independent adjacent Bow auras stack at declaration, while later source departure cannot edit the captured attack.
func test_bard_guardian_ranger() -> void:
	fixture()
	var bard := add(AdventurerCatalogue.tamia_bard(1), 0)
	var ranger := add(AdventurerCatalogue.flying_squirrel_ranger(1), 1)
	var guardian := add(SynergyCatalogue.grey_squirrel_guardian(1), 2)
	var enemy := plain(2, 3)
	ranger._change_action_counter(UnitInfo.PHYSICAL_COUNTER, 3)
	check(ranger.effective_bow_bonus() == Vector2i(2, 0), "Bard and qualifying Guardian contribute independent damage-only auras")
	if not submit(ranger, 0): return
	if not take(TargetRef.unit(ranger.iun)) or not take(TargetRef.hex(enemy.ihx)): return
	check(Match.pending_bow_attacks.size() == 1, "Ranger queues one attack")
	if Match.pending_bow_attacks.is_empty(): return
	var attack: BowAttack = Match.pending_bow_attacks[0]
	check(attack.amount == 3 and attack.pierce, "Captured Pierce Bow includes both live damage bonuses")
	Action.return_to_hand(TargetRef.unit(bard.iun), TargetRef.unit(bard.iun))
	check(ranger.effective_bow_bonus() == Vector2i(1, 0) and attack.amount == 3, "Bard departure changes future values without editing the queued attack")
	check(ranger.bow_damage_bonus == 0 and guardian.t_state == Enum.t_state.DEPLOYED, "Auras never become stored Bow counters")
	CombatResolver.resolve_bow(attack)
	check(enemy.actual_life == enemy.max_life - 3, "The captured attack resolves with its original three damage")

## Positive Ember award, paid conversion, friendly death income and independently granted P/F converge on Witch's next Fire once.
func test_ember_witch_and_merchants() -> void:
	fixture()
	var pierce_merchant := add(AdventurerCatalogue.guinea_pig_merchant(1), 0)
	var witch := add(AdventurerCatalogue.dormouse_witch(1), 1)
	var instant_merchant := add(AdventurerCatalogue.guinea_pig_merchant(1), 2)
	var enemy := plain(2, 3, 2)
	var alchemist := add(AdventurerCatalogue.chinchilla_alchemist(1), 4)
	var donor := plain(1, 5)
	SynergyActions.add_counter(TargetRef.unit(alchemist.iun), TargetRef.unit(donor.iun), UnitInfo.EMBER_COUNTER, 2)
	check(alchemist._counter_value(&"Soul") == 1, "Two Embers in one award earn exactly one Soul")
	if not submit(witch, 2): return
	if not take(TargetRef.unit(witch.iun)) or not take(TargetRef.property(TargetRef.unit(donor.iun), UnitInfo.EMBER_COUNTER)): return
	check(donor._counter_value(UnitInfo.EMBER_COUNTER) == 1 and witch._counter_value(&"fire_damage") == 1, "Witch converts exactly one donated Ember to permanent Fire damage")
	check(alchemist._counter_value(&"Soul") == 1, "Paying an Ember does not reward Alchemist")
	Match.defeat(TargetRef.unit(donor.iun), 2)
	check(pierce_merchant._counter_value(&"Soul") == 1 and instant_merchant._counter_value(&"Soul") == 1, "One friendly death funds each independent Merchant once")
	for pair in [[pierce_merchant, 0], [instant_merchant, 1]]:
		var merchant: UnitInfo = pair[0]
		if not submit(merchant, pair[1]): return
		if not take(TargetRef.unit(merchant.iun)) or not take(TargetRef.property(TargetRef.unit(merchant.iun), &"Soul")) or not take(TargetRef.unit(witch.iun)): return
	check(witch.next_fire_stickers.size() == 2, "Separate sources combine Pierce and Instant on the Witch")
	enemy._change_action_counter(UnitInfo.MAGICAL_COUNTER, 9)
	# Prepare the Witch's next legal activation; activity/recovery timing is covered by M2 and local-match suites.
	witch.active = true
	if not submit(witch, 1): return
	if not take(TargetRef.unit(witch.iun)) or not take(TargetRef.hex(enemy.ihx)): return
	check(enemy.t_state == Enum.t_state.DEFEATED, "Upgraded Instant Pierce Fire ignores enemy magic nine and defeats life two")
	check(witch.next_fire_stickers.is_empty() and Match.pending_attacks.is_empty(), "Both one-use stickers consume on this instant declaration")
	check(witch._counter_value(&"fire_damage") == 1, "Permanent conversion survives next-Fire sticker consumption")
	check(alchemist._counter_value(&"Soul") == 1, "Fire/death followups do not invent extra Ember awards")

## Scout geography and Pikeman Bash allowances stack while committed movement spending survives allowance loss/reentry.
func test_scout_pikeman_spent_actions() -> void:
	fixture()
	var pikeman := add(SynergyCatalogue.grey_squirrel_pikeman(1), 0)
	var opponent := plain(2, 0)
	encounter(pikeman, opponent, 0)
	var scout := add(AdventurerCatalogue.jerboa_scout(1), 2)
	Match.map[2].region = Enum.region.STARTING
	Match.map[2].side = Enum.side.P2
	var base := Match.players[1].base_actions_remaining
	check(Match.players[1].actions_remaining == base + 2, "Geography and Bash allowances stack")
	for destination in [4, 2, 4]:
		if not submit(scout, 0) or not take(TargetRef.hex(destination)): return
	check(Match.players[1].base_actions_remaining == base - 3, "Three managed [A] moves spend exactly three ledger actions")
	check(Match.players[1].actions_remaining == base - 2, "Only the still-bashing Pikeman's allowance remains")
	check(scout.active and scout._counter_value(UnitInfo.STUN_COUNTER) == 0, "[A] movement pays no activity during the complete chain")
	Action.return_to_hand(TargetRef.unit(pikeman.iun), TargetRef.unit(pikeman.iun))
	check(Match.players[1].actions_remaining == base - 3, "Bash departure removes the remaining allowance without refunding spending")
	check(SynergyRules.player_action_bonus(2) == 0, "Neither friendly allowance leaks to the enemy player")

## Hunter may pay Cleric's activity Stun, but removing that counter and Resetting an enemy cannot activate either card before own End.
func test_cleric_hunter_end_recovery() -> void:
	fixture()
	var cleric := add(AdventurerCatalogue.guinea_pig_cleric(1), 0)
	var hunter := add(AdventurerCatalogue.tamia_hunter(1), 1)
	var enemy := plain(2, 2)
	enemy.active = false
	enemy.actual_life = 1
	enemy._change_action_counter(UnitInfo.STUN_COUNTER, 2)
	if not submit(cleric, 0): return
	if not take(TargetRef.unit(cleric.iun)) or not take(TargetRef.property(TargetRef.unit(hunter.iun), UnitInfo.PHYSICAL_COUNTER)): return
	check(hunter._counter_value(UnitInfo.PHYSICAL_COUNTER) == 1, "Cleric increases Hunter's already-present physical counter")
	if not submit(hunter, 0): return
	if not take(TargetRef.unit(hunter.iun)) or not take(TargetRef.property(TargetRef.unit(cleric.iun), UnitInfo.STUN_COUNTER)): return
	check(cleric._counter_value(UnitInfo.STUN_COUNTER) == 0 and not cleric.active, "Counter payment removes Cleric Stun without activating it")
	if not take(TargetRef.unit(enemy.iun)): return
	check(enemy.actual_life == enemy.max_life and enemy._counter_value(UnitInfo.STUN_COUNTER) == 0 and not enemy.active, "Enemy Reset removes Stun and wounds while preserving inactivity")
	check(hunter._counter_value(UnitInfo.PHYSICAL_COUNTER) == 1, "Paying Cleric's counter never consumes Hunter's unrelated granted physical")
	Match._activate_unstunned_units(1)
	check(cleric.active and not hunter.active and not enemy.active, "Owner End activates only unstunned Cleric, excluding stunned Hunter and enemy")
	check(count_event(&"activate") == 1, "Only the actual activity transition emits Activate")

## An existing counter created in value by Cleric remains a transferable identity when the opposing player's Rogue pays for it.
func test_cleric_counters_and_opposing_rogue() -> void:
	fixture()
	var cleric := add(AdventurerCatalogue.guinea_pig_cleric(1), 0)
	var friend := plain(1, 1)
	var rogue := add(AdventurerCatalogue.dormouse_rogue(2), 2)
	var rogue_friend := plain(2, 3)
	if not submit(cleric, 0): return
	if not take(TargetRef.unit(cleric.iun)) or not take(TargetRef.property(TargetRef.unit(friend.iun), UnitInfo.MAGICAL_COUNTER)): return
	Match.active_player = 2
	var first_before := Match.players[1].base_actions_remaining
	var second_before := Match.players[2].base_actions_remaining
	if not submit(rogue, 0): return
	if not take(TargetRef.unit(rogue.iun)): return
	check(not choose(TargetRef.property(TargetRef.unit(rogue_friend.iun), UnitInfo.MAGICAL_COUNTER)), "Player two's Rogue cannot steal from its own friend")
	if not take(TargetRef.property(TargetRef.unit(friend.iun), UnitInfo.MAGICAL_COUNTER)): return
	check(friend._counter_value(UnitInfo.MAGICAL_COUNTER) == 0 and rogue._counter_value(UnitInfo.MAGICAL_COUNTER) == 1, "Opposing Rogue moves exactly the kind increased by Cleric")
	check(rogue._counter_value(UnitInfo.PHYSICAL_COUNTER) == 0, "Magical transfer never becomes physical")
	check(Match.players[2].base_actions_remaining == second_before - 1 and Match.players[1].base_actions_remaining == first_before, "The acting second player alone pays the command action")
