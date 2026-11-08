## Reuses the approved-roster fixture helpers; this scene runs only the three new hero regressions when explicitly requested with TEST.
extends "res://tests/synergy_units_test.gd"

## Dedicated entry point covers each new command, aura, sacrifice capture and owner-paired registration without running inherited scenarios.
func _ready() -> void:
	Match.action_event.connect(record)
	test_king_supply()
	test_king_shield()
	test_king_loaded_aura()
	test_jerboa_commands()
	test_jerboa_aura()
	test_continuous_cue_eligibility()
	test_queen_healing()
	test_queen_sacrifice()
	test_queen_aura()
	test_heroes_registered()
	test_hover_conventions_and_mshield()
	test_additional_hover_conventions()
	test_compound_wording()
	test_final_trigger_wording()
	print("Crowned heroes: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)

## Supply creates ammunition on an adjacent friend of any unit type and pays action/activity once.
func test_king_supply() -> void:
	fixture()
	var king := add(HeroCatalogue.grey_squirrel_king(1), 1)
	var troop := plain(1, 2)
	var enemy := plain(2, 0)
	var distant := plain(1, 4)
	var temple := plain(1, 0)
	temple.type = Enum.type.TEMPLE
	check(Match.rules_runner.submit(king.effects[1], TargetRef.unit(king.iun)) and choose(TargetRef.unit(king.iun)), "King pays activity for Supply")
	check(not choose(TargetRef.unit(enemy.iun)) and not choose(TargetRef.unit(distant.iun)) and not choose(TargetRef.unit(king.iun)), "Supply excludes enemies, distance and SELF")
	check(choose(TargetRef.unit(troop.iun)) and troop._counter_value(UnitInfo.PROJECTILE_COUNTER) == 1, "Supply grants one Projectile, creating the counter when absent")
	check(not king.active and king._counter_value(&"stun") == 1 and Match.players[1].actions_remaining == 19, "Supply pays one action and self-Stun once")
	var resolved := TargetResolver.resolve(HeroCatalogue.other_friends(1, true), TargetRef.Kind.UNIT, RuleContext.new(TargetRef.unit(king.iun)))
	check(TargetResolver.contains(resolved.candidates, TargetRef.unit(temple.iun)), "Supply eligibility includes adjacent friendly temples")

## Fortify is separate from ammunition: select one friend within two, including SELF, and award only temporary physical protection.
func test_king_shield() -> void:
	fixture()
	var king := add(HeroCatalogue.grey_squirrel_king(1), 0)
	var friend := plain(1, 2)
	var enemy := plain(2, 1)
	var distant := plain(1, 4)
	check(Match.rules_runner.submit(king.effects[2], TargetRef.unit(king.iun)) and choose(TargetRef.unit(king.iun)), "Fortify pays ordinary activity")
	check(not choose(TargetRef.unit(enemy.iun)) and not choose(TargetRef.unit(distant.iun)), "Fortify rejects enemy and beyond-radius targets")
	check(choose(TargetRef.unit(friend.iun)) and friend._counter_value(&"temp_physical") == 2, "Fortify grants Shield 2 to the exact chosen friend")
	check(king._counter_value(&"temp_physical") == 0 and friend._counter_value(&"physical") == 0, "Fortify neither shields the source automatically nor writes permanent physical")

## Loaded-neighbour protection reads current ammunition for every friendly type without accumulation or source protection.
func test_king_loaded_aura() -> void:
	fixture()
	var king := add(HeroCatalogue.grey_squirrel_king(1), 1)
	var friend := plain(1, 2)
	var enemy := plain(2, 0)
	var aura: ContinuousEffect = king.continuous_effects[0]
	check(aura.evaluate(king.iun, friend.iun) == Vector2i.ZERO, "Unloaded troop receives no protection")
	friend._change_action_counter(UnitInfo.PROJECTILE_COUNTER, 1)
	enemy._change_action_counter(UnitInfo.PROJECTILE_COUNTER, 1)
	check(aura.evaluate(king.iun, friend.iun) == Vector2i(1, 0) and aura.evaluate(king.iun, enemy.iun) == Vector2i.ZERO, "Loaded friendly troop receives exactly +1 physical")
	check(aura.evaluate(king.iun, king.iun) == Vector2i.ZERO, "Loaded aura excludes hero SELF")
	friend.type = Enum.type.TEMPLE
	check(aura.evaluate(king.iun, friend.iun) == Vector2i(1, 0), "Loaded friendly temple receives protection")
	friend.type = Enum.type.HERO
	check(aura.evaluate(king.iun, friend.iun) == Vector2i(1, 0), "Loaded friendly hero receives protection")
	friend.type = Enum.type.TROOP
	friend.ihx = 4
	check(aura.evaluate(king.iun, friend.iun) == Vector2i.ZERO, "Moving outside adjacency removes aura")
	friend.ihx = 2
	friend._change_action_counter(UnitInfo.PROJECTILE_COUNTER, -1)
	check(aura.evaluate(king.iun, friend.iun) == Vector2i.ZERO and friend._counter_value(&"physical") == 0, "Spending last Projectile removes live bonus without counter mutation")
	friend._change_action_counter(UnitInfo.PROJECTILE_COUNTER, 1)
	king.t_state = Enum.t_state.UNDEPLOYED
	check(aura.evaluate(king.iun, friend.iun) == Vector2i.ZERO, "Off-board king cannot supply live loaded protection")

## Khan's independent Push and Stun commands target enemies only, using normal movement and hostile Stun production paths.
func test_jerboa_commands() -> void:
	fixture()
	var king := add(HeroCatalogue.jerboa_king(1), 0)
	var enemy := plain(2, 2)
	var friend := plain(1, 1)
	check(Match.rules_runner.submit(king.effects[1], TargetRef.unit(king.iun)) and choose(TargetRef.unit(king.iun)), "Khan pays for Push")
	check(not choose(TargetRef.unit(friend.iun)) and choose(TargetRef.unit(enemy.iun)), "Push accepts the enemy, never a friend")
	check(enemy.ihx == 3 and enemy.last_displaced_turn == Match.turn_number, "Push displaces exactly one and records current-turn history")
	fixture()
	king = add(HeroCatalogue.jerboa_king(1), 0)
	enemy = plain(2, 1)
	friend = plain(1, 1)
	var distant := plain(2, 3)
	check(Match.rules_runner.submit(king.effects[2], TargetRef.unit(king.iun)) and choose(TargetRef.unit(king.iun)), "Khan pays separately for Stun")
	check(not choose(TargetRef.unit(friend.iun)) and not choose(TargetRef.unit(distant.iun)), "Stun rejects friends and nonadjacent enemies")
	check(choose(TargetRef.unit(enemy.iun)) and enemy._counter_value(&"stun") == 1 and not enemy.active, "Pin down Stuns the exact enemy for one")

## Shifted rewards the displaced friend, excludes voluntary movement/enemies, and lasts through the source enemy End.
func test_jerboa_aura() -> void:
	fixture()
	var king := add(HeroCatalogue.jerboa_king(1), 0)
	var friend := plain(1, 2)
	var enemy := plain(2, 4)
	Match.action_event.emit(EffectEvent.new(&"move", TargetRef.unit(friend.iun), TargetRef.hex(2)))
	Match.action_event.emit(EffectEvent.new(&"fly", TargetRef.unit(friend.iun), TargetRef.hex(2)))
	Match.action_event.emit(EffectEvent.new(&"shifted", TargetRef.unit(enemy.iun), TargetRef.hex(4)))
	Match.action_event.emit(EffectEvent.new(&"shifted", TargetRef.unit(friend.iun), TargetRef.hex(2), {"success": false}))
	check(friend.timed_grants.is_empty() and enemy.timed_grants.is_empty(), "Walk, Fly, failed shifts and enemy shifts never award support")
	check(CombatResolver.displace(TargetRef.unit(king.iun), TargetRef.unit(friend.iun), 1, 2, false, true), "Push changes a friend's actual hex")
	check(friend.ihx == 3 and friend.timed_grants.size() == 1, "Successful Push emits Shifted for its recipient")
	check(friend.timed_grants[0].parameters == [2, 0] and friend._counter_value(&"physical") == 0, "Shift gives derived +2/+0 without counters")
	check(friend.timed_grants[0].expires_player == 2 and friend.timed_grants[0].expires_turn == Match.turn_number + 1, "Own-turn shift captures the next enemy End")
	check(CombatResolver.displace(TargetRef.unit(king.iun), TargetRef.unit(friend.iun), 1, 3, true, true), "Pull shifts the same recipient back")
	check(friend.ihx == 2 and friend.timed_grants.size() == 1, "Repeated Push/Pull refreshes without stacking")
	var shifted_count := events.filter(func(event: EffectEvent) -> bool: return event.action == &"shifted").size()
	check(not CombatResolver.displace(TargetRef.unit(king.iun), TargetRef.unit(friend.iun), 0, 2, false, true), "Zero displacement is illegal")
	check(events.filter(func(event: EffectEvent) -> bool: return event.action == &"shifted").size() == shifted_count, "Failed displacement never emits Shifted")
	king.t_state = Enum.t_state.UNDEPLOYED
	check(friend.timed_grants.size() == 1, "Paid shifted support survives source departure")
	var snapshot := preload("res://scripts/runtime/match_snapshot.gd")
	var saved: Dictionary = snapshot._capture_state()
	friend.timed_grants.clear()
	snapshot._apply_state(saved)
	check(friend.timed_grants.size() == 1 and friend.timed_grants[0].kind == TimedGrant.Kind.MODIFIERS, "Snapshot retains shifted grant and enemy expiry")
	Match.expire_timed_grants(1, Match.turn_number)
	check(friend.timed_grants.size() == 1, "Own End preserves shifted support")
	Match.expire_timed_grants(2, Match.turn_number + 1)
	check(friend.timed_grants.is_empty(), "Enemy End cleanup expires shifted support")
	fixture()
	king = add(HeroCatalogue.jerboa_king(1), 0)
	friend = plain(1, 2)
	enemy = plain(2, 4)
	Match.active_player = 2
	check(CombatResolver.displace(TargetRef.unit(enemy.iun), TargetRef.unit(friend.iun), 1, 2, false, true), "Enemy Push still rewards the king's displaced friend")
	check(friend.timed_grants[0].expires_player == 2 and friend.timed_grants[0].expires_turn == Match.turn_number, "Enemy-turn shift expires at this enemy End")

## Continuous star eligibility shares source/recipient conditions, ownership and deployment without creating rule mutations.
func test_continuous_cue_eligibility() -> void:
	fixture()
	var observer := preload("res://scripts/board/continuous_cues.gd").new()
	var king := add(HeroCatalogue.grey_squirrel_king(1), 1)
	var friend := plain(1, 2)
	var enemy := plain(2, 0)
	check(observer.active_rules(king).is_empty(), "Continuous star absent without a loaded eligible friend")
	enemy._change_action_counter(UnitInfo.PROJECTILE_COUNTER, 1)
	check(observer.active_rules(king).is_empty(), "Loaded enemy does not light the source's aura star")
	friend._change_action_counter(UnitInfo.PROJECTILE_COUNTER, 1)
	check(observer.active_rules(king).size() == 1, "Eligible friend lights exactly the source's continuous rule")
	friend.ihx = 4
	check(observer.active_rules(king).is_empty(), "Leaving range removes continuous star eligibility")
	friend.ihx = 2
	friend._change_action_counter(UnitInfo.PROJECTILE_COUNTER, -1)
	check(observer.active_rules(king).is_empty(), "Losing recipient condition removes continuous star eligibility")
	friend._change_action_counter(UnitInfo.PROJECTILE_COUNTER, 1)
	king.t_state = Enum.t_state.UNDEPLOYED
	check(observer.active_rules(king).is_empty(), "Off-board sources never retain live continuous stars")
	var queen := add(HeroCatalogue.marmot_queen(1), 1)
	check(observer.active_rules(queen).is_empty(), "Full-life source condition leaves star absent")
	queen.actual_life -= 1
	check(observer.active_rules(queen).size() == 1, "Wounded source lights continuous star")
	queen.actual_life = queen.max_life
	check(observer.active_rules(queen).is_empty(), "Healing source removes continuous star eligibility")
	observer.free()
## Queen heals another wounded friend within two, clamps actual life and rejects SELF/enemy/distant targets.
func test_queen_healing() -> void:
	fixture()
	var queen := add(HeroCatalogue.marmot_queen(1), 0)
	var friend := plain(1, 2, 4)
	friend.actual_life = 3
	var enemy := plain(2, 1)
	enemy.actual_life = 1
	var distant := plain(1, 4)
	distant.actual_life = 1
	queen.actual_life = 2
	check(Match.rules_runner.submit(queen.effects[1], TargetRef.unit(queen.iun)) and choose(TargetRef.unit(queen.iun)), "Queen pays for healing")
	check(not choose(TargetRef.unit(queen.iun)) and not choose(TargetRef.unit(enemy.iun)) and not choose(TargetRef.unit(distant.iun)), "Mend excludes SELF, enemy and distant friend")
	check(choose(TargetRef.unit(friend.iun)) and friend.actual_life == 4 and friend.max_life == 4, "Mend 2 clamps to existing maximum without increasing it")

## Sacrifice protection captures the victim's departure hex and grants both consumed counters without activity or action payment.
func test_queen_sacrifice() -> void:
	fixture()
	var queen := add(HeroCatalogue.marmot_queen(1), 0)
	var friend := plain(1, 2)
	var enemy := plain(2, 1)
	var distant := plain(1, 4)
	for ref in [TargetRef.unit(enemy.iun), TargetRef.unit(distant.iun), TargetRef.unit(queen.iun)]:
		Match.action_event.emit(EffectEvent.new(&"sacrifice", TargetRef.unit(queen.iun), ref, {"last_hex": Match.get_unit(ref.id).ihx}))
	Match.action_event.emit(EffectEvent.new(&"die", TargetRef.unit(friend.iun), TargetRef.hex(2)))
	check(queen._counter_value(&"temp_physical") == 0 and queen._counter_value(&"temp_magical") == 0, "Enemy, distant, SELF Sacrifice and ordinary Die do not reward Queen")
	check(SynergyActions.sacrifice(TargetRef.unit(queen.iun), TargetRef.unit(friend.iun)), "Real nearby friendly sacrifice commits")
	check(friend.ihx < 0 and queen._counter_value(&"temp_physical") == 1 and queen._counter_value(&"temp_magical") == 1, "Captured departure within two grants Shield 1 and Mshield 1 after removal")
	check(queen.active and queen._counter_value(&"stun") == 0 and Match.players[1].actions_remaining == 20, "Sacrifice reward is mandatory and costs no action or activity")

## Wounded-source aura includes all other adjacent friendly types and disappears on healing or source departure.
func test_queen_aura() -> void:
	fixture()
	var queen := add(HeroCatalogue.marmot_queen(1), 0)
	var friend := plain(1, 1)
	var enemy := plain(2, 1)
	var aura: ContinuousEffect = queen.continuous_effects[0]
	check(aura.evaluate(queen.iun, friend.iun) == Vector2i.ZERO, "Full-life Queen grants no magical support")
	queen.actual_life = 5
	check(aura.evaluate(queen.iun, friend.iun) == Vector2i(0, 1), "Wounded Queen grants +1 magical to adjacent troop")
	check(aura.evaluate(queen.iun, enemy.iun) == Vector2i.ZERO and aura.evaluate(queen.iun, queen.iun) == Vector2i.ZERO, "Wounded aura excludes enemies and SELF")
	friend.type = Enum.type.TEMPLE
	check(aura.evaluate(queen.iun, friend.iun) == Vector2i(0, 1), "Wounded aura includes friendly temples")
	friend.type = Enum.type.HERO
	check(aura.evaluate(queen.iun, friend.iun) == Vector2i(0, 1), "Wounded aura includes friendly heroes")
	friend.type = Enum.type.TROOP
	friend.ihx = 2
	check(aura.evaluate(queen.iun, friend.iun) == Vector2i.ZERO, "Wounded aura requires exact adjacency")
	friend.ihx = 1
	queen.actual_life = 6
	check(aura.evaluate(queen.iun, friend.iun) == Vector2i.ZERO, "Healing Queen to full removes support")
	queen.actual_life = 5
	queen.t_state = Enum.t_state.UNDEPLOYED
	check(aura.evaluate(queen.iun, friend.iun) == Vector2i.ZERO and friend._counter_value(&"magical") == 0, "Off-board source contributes nothing and never writes permanent counters")

## All three are named, sprite-backed Starting heroes with agreed life totals, available to either owner after older IDs.
func test_heroes_registered() -> void:
	var cards := HeroCatalogue.all_units(1)
	for index in cards.size():
		var unit := cards[index]
		check(unit.type == Enum.type.HERO and unit.max_life == [5, 6, 6][index], "Approved hero types and life totals")
		check(unit.effects[0].consequence.verb.user_params[0] == [1, 2, 1][index], "Heroes retain their approved Move 1/2/1 actions")
		check(unit.deploy_regions == [Enum.region.STARTING] and BoardCharacter.supports(unit), "Each hero deploys Starting and has mapped animation art")
		var text := " ".join(EffectText.unit_lines(unit))
		check(not text.contains("Unrecognized"), "Hero hover text recognizes every authored condition")
		if index == 0: check(text.to_lower().contains("projectile") and text.contains("adjacent friend"), "King text uses concise ammunition/friend wording")
		if index == 1: check(text.contains("friend is shifted: it has") and text.contains("until enemy End"), "Khan text exposes changed movement/expiry rule")
		if index == 2: check(text.contains("sacrificed within 2"), "Queen text exposes sacrifice range without duplicate guards")
	var roster := CardCatalogue.starter_army()
	check(roster.size() == 194 and CardCatalogue.all_units(2).size() == 97, "Both players receive the three hero alternatives in the expanded roster")
	check(roster[0].uuid == "squirrel-king-p1" and roster[3].uuid == "mole-artificer-p2", "Appending heroes preserves old IDs")

## Shared formatting retains compact numeric rules/costs and the distinct native Mshield asset without altering effects.
func test_hover_conventions_and_mshield() -> void:
	var king := HeroCatalogue.grey_squirrel_king(1)
	var supply := EffectText.describe_effect(king.effects[1], king)
	check(supply.begins_with("[lb]AS[rb]:") and supply.contains("adjacent friend"), "Written consequences show explicit default AS before the colon")
	var shield := EffectText.describe_effect(king.effects[2], king)
	check(shield.contains(GameIcons.action_path(&"shield")) and not shield.contains("units on") and not shield.contains("AS"), "Default numeric Shield uses amount/icon/range shorthand")
	var red := CardCatalogue.squirrel_king(1)
	var trigger := EffectText.describe_effect(red.trigger_effects[0], red)
	check(trigger.begins_with("this unit ") and not trigger.contains("any hex"), "Unrestricted action triggers omit redundant destination wording")
	var tamia := CardCatalogue.wild_tamia(1)
	var conversion := EffectText.describe_effect(tamia.effects[1], tamia)
	check(conversion.begins_with("[lb]AS[rb] disable ") and conversion.ends_with(": +1 deploy"), "Disable conversion shares cost-before-colon notation")
	check(GameIcons.action_path(&"mshield") != GameIcons.action_path(&"shield"), "Magical protection uses a distinct purple icon")
	var cue := preload("res://scripts/board/board_trigger.gd").new()
	cue.setup(null, king, 0, "mshield", 1.5)
	check(cue.sprite_frames.get_frame_count(&"default") == 9 and not cue.sprite_frames.get_animation_loop(&"default"), "Mshield loads all nine native frames as finite recipient feedback")
	check(is_equal_approx(cue.lifetime, 1.5), "Mshield retains existing finite fade duration")
	cue.free()

## Additional user examples exercise shared contact, projected Fire, Return costs, Upgrade arity and global threshold wording.
func test_additional_hover_conventions() -> void:
	var guinea := CardCatalogue.wild_guinea_pig(1)
	var contact_text := EffectText.describe_effect(guinea.trigger_effects[0], guinea)
	check(contact_text.contains("hits:") and not contact_text.contains("any unit"), "Wild contact trigger omits an unrestricted victim")
	var marmot := CardCatalogue.wild_marmot(1)
	var return_text := EffectText.describe_effect(marmot.effects[1], marmot)
	check(return_text.begins_with("[lb]AS[rb]: return "), "Marmot Return retains its actual action and activity costs")
	var lemming := CardCatalogue.wild_lemming(1)
	var fire_text := EffectText.describe_effect(lemming.effects[0], lemming)
	check(fire_text.contains("1F") and fire_text.contains("enemy") and not fire_text.contains("hexes occupied"), "Instant Fire keeps enemy ownership without exposing projection terminology")
	var archer := SynergyCatalogue.grey_squirrel_archer(1)
	check(EffectText.describe_effect(archer.trigger_effects[0], archer).begins_with("this unit wounds:"), "Own Wound trigger drops only the unrestricted victim")
	var warrior := SynergyCatalogue.grey_squirrel_warrior(1)
	check(EffectText.describe_effect(warrior.effects[1], warrior).contains("1/0 " + GameIcons.bb(&"upgrade") + " 2"), "Upgrade distinguishes its damage/range pair from recipient reach")
	var soul_text := EffectText.describe_effect(warrior.trigger_effects[0], warrior)
	check(soul_text.contains("wounds with ") and not soul_text.contains("if the contact"), "Attack-family guards share concise Wound wording while retaining the Bow restriction")
	var guard := SynergyCatalogue.grey_squirrel_guardian(1)
	var guard_text := " ".join(EffectText.unit_lines(guard))
	check(guard_text.contains("with +3 or more physical have") and not guard_text.contains("adjacent"), "Guardian wording exposes the global physical threshold")
	var beaver := SynergyCatalogue.beaver_warrior(1)
	check(" ".join(EffectText.unit_lines(beaver)).contains("over bombs have"), "Bomb-support aura uses a concise recipient clause")

## Compound resource/participant choices share concise text without changing their costs, ownership or retained selection stages.
func test_compound_wording() -> void:
	var courier := SynergyCatalogue.jerboa_courier(1)
	check(EffectText.describe_effect(courier.effects[1], courier).contains("transfer up to 2 counters between two units within 2 from this unit"), "Courier text names both range-bound participants")
	var sentinel := SynergyCatalogue.chinchilla_sentinel(1)
	check(" ".join(EffectText.unit_lines(sentinel)).contains("adjacent unit deployment does not trigger any ability"), "Sentinel text describes whole-event suppression")
	var rogue := AdventurerCatalogue.dormouse_rogue(1)
	check(EffectText.describe_effect(rogue.effects[0], rogue).contains("transfer one counter from adjacent "), "Rogue theft is described as a transfer")
	check(EffectText.describe_effect(rogue.effects[1], rogue).contains("-1 counter: defeat an enemy"), "Rogue defeat retains its counter payment")
	var hunter := AdventurerCatalogue.tamia_hunter(1)
	check(EffectText.describe_effect(hunter.effects[0], hunter).contains("-1 counter on adjacent ") and EffectText.describe_effect(hunter.effects[0], hunter).ends_with("reset 2"), "Hunter exposes counter-host and Reset radius")
	var shaman := AdventurerCatalogue.porcupine_shaman(1)
	check(EffectText.describe_effect(shaman.effects[1], shaman).ends_with("return two bashing units"), "Shaman hides duplicate choices without omitting its two participants")
	var summoner := AdventurerCatalogue.mouse_summoner(1)
	check(EffectText.describe_effect(summoner.effects[1], summoner).ends_with("deploy friend on target"), "Summoner retains target-hex deployment wording")
	var cleric := AdventurerCatalogue.guinea_pig_cleric(1)
	check(EffectText.describe_effect(cleric.effects[0], cleric).contains("+1 existing counter on adjacent "), "Cleric text preserves existing-counter eligibility")
	var bard := AdventurerCatalogue.tamia_bard(1)
	check(" ".join(EffectText.unit_lines(bard)).contains("adjacent units have"), "Bard aura preserves recipients of either owner")
	var scout := AdventurerCatalogue.jerboa_scout(1)
	check(EffectText.describe_effect(scout.effects[0], scout).begins_with("[lb]A[rb]:") and not RuleGuide.STICKERS.has("T"), "Activity-exempt actions use A cost notation without a visible Tireless sticker")

## History guards describe the two clarified trigger anchors once, retaining the Jester's Instant Bow and Blue Mage target identity.
func test_final_trigger_wording() -> void:
	var blue := SynergyCatalogue.tamia_blue_mage(1)
	var blue_text := EffectText.describe_effect(blue.trigger_effects[0], blue)
	check(blue_text.begins_with("another friend Stuns any stunned unit:") and blue_text.contains("to target"), "Blue Mage text preserves another actor and exact captured target")
	var jester := AdventurerCatalogue.jerboa_jester(1)
	var jester_text := EffectText.describe_effect(jester.trigger_effects[0], jester)
	check(jester_text.begins_with("enemy gains control of this unit's region: 2F") and not jester_text.contains("if "), "Jester folds its captured own-region condition into its trigger and keeps Instant Bow 2/2")
