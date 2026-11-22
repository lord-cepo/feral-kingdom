## Focused behavioral coverage for both approved Frontier batches.
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
	test_beaver_bard()
	test_beaver_bard_push()
	test_chinchilla_druid()
	test_dormouse_bard()
	test_guinea_pig_jester()
	test_hedgehog_cleric()
	test_hedgehog_musketeer()
	test_lemming_monk()
	test_mara_witch()
	test_otter_blacksmith()
	test_printed_commands()
	test_concise_rule_text()
	print("Frontier units: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)

## Starts the catalogue command through RulesRunner, including normal costs and phase accounting.
func play(unit: UnitInfo, slot: int) -> bool:
	return Match.rules_runner.submit(unit.effects[slot], TargetRef.unit(unit.iun))

## Rally gives both stored counters to each friend launching a Bash from adjacent, with no separate protection commands.
func test_beaver_bard() -> void:
	fixture()
	var bard := add(FrontierRecruits.beaver_bard(1), 0)
	check(bard.effects.size() == 2, "Bard has only its Walk and Push commands")
	var ally := plain(1, 1)
	var ally_ref := TargetRef.unit(ally.iun)
	var defender := plain(2, 3)
	var defender_ref := TargetRef.unit(defender.iun)
	check(CombatResolver.move_unit(ally_ref, TargetRef.hex(2), 1, false) and ally._counter_value(UnitInfo.SHIELD_COUNTER) == 0,
		"A friendly walk without Bash does not use Rally")
	Match.action_event.emit(EffectEvent.new(&"bash", ally_ref, defender_ref, {"origin_hex": 2}, &"target"))
	Match.action_event.emit(EffectEvent.new(&"bash", defender_ref, ally_ref, {"origin_hex": 1}, &"target"))
	check(ally._counter_value(UnitInfo.SHIELD_COUNTER) == 0 and defender._counter_value(UnitInfo.SHIELD_COUNTER) == 0,
		"Neither an off-range friendly launch nor an adjacent enemy launch receives Shield")
	ally.ihx = 1
	check(CombatResolver.move_unit(ally_ref, TargetRef.hex(3), 2, false) and ally._counter_value(UnitInfo.SHIELD_COUNTER) == 1 \
		and ally._counter_value(UnitInfo.MSHIELD_COUNTER) == 1, "Friendly Bash from beside the Bard grants both counters")
	Match.map[4].coordinate = Vector2i(-1, 0)
	Match.map[5].coordinate = Vector2i(-2, 0)
	var second := plain(1, 4)
	plain(2, 5)
	check(CombatResolver.move_unit(TargetRef.unit(second.iun), TargetRef.hex(5), 1, false) \
		and second._counter_value(UnitInfo.SHIELD_COUNTER) == 1, "A second qualifying Bash can trigger in the same turn")

## Bard's hover and legal target picker agree on distance, enemy ownership and straight-line alignment.
func test_beaver_bard_push() -> void:
	fixture()
	var bard := add(FrontierRecruits.beaver_bard(1), 0)
	var aligned := plain(2, 2)
	Match.map[4].coordinate = Vector2i(1, 1)
	Match.map[5].coordinate = Vector2i(-1, 0)
	var off_axis := plain(2, 4)
	var friend := plain(1, 5)
	var hover := EffectText.describe_effect(bard.effects[1], bard)
	check(hover == "1" + GameIcons.bb(&"push", bard.player) + "2", "Bard hover displays only compact Push 1/2")
	check(play(bard, 1) and choose(TargetRef.unit(bard.iun)) and not choose(TargetRef.unit(off_axis.iun)) \
		and not choose(TargetRef.unit(friend.iun)), "Push excludes in-range off-axis enemies and aligned friends")
	check(choose(TargetRef.unit(aligned.iun)) and aligned.ihx == 3, "Push moves an aligned enemy at range two one hex farther away")

## Druid Mends within two while its control aura still excludes itself, enemies and full-life allies across regions.
func test_chinchilla_druid() -> void:
	fixture()
	var druid := add(FrontierRecruits.chinchilla_druid(1), 0)
	var nearby := plain(1, 2, 2)
	var distant := plain(1, 5, 3)
	var enemy := plain(2, 1, 3)
	Match.map[5].region_count = 1
	for unit in [druid, nearby, distant, enemy]: unit.actual_life -= 1
	check(ControlResolver.strength(Match.map[5], 1) == 3.0, "Distant wounded friend contributes +1 in its own region")
	check(ControlResolver.live_strength(druid.iun) == 0 and ControlResolver.live_strength(enemy.iun) == 0,
		"Druid excludes self and enemies")
	check(play(druid, 1) and choose(TargetRef.unit(druid.iun)) and not choose(TargetRef.unit(distant.iun)) \
		and not choose(TargetRef.unit(enemy.iun)) and choose(TargetRef.unit(nearby.iun)), "Mend reaches a wounded friend at distance two")
	check(nearby.actual_life == nearby.max_life and ControlResolver.live_strength(nearby.iun) == 0,
		"Full healing removes the live control bonus")
	druid.enter_hand()
	check(ControlResolver.live_strength(distant.iun) == 0, "Druid leaving play removes its global bonus")

## The adjacent Return pays S only; the separate relocation retains both two-hex ranges and repeatability.
func test_dormouse_bard() -> void:
	fixture()
	var bard := add(FrontierRecruits.dormouse_bard(1), 0)
	var friend := plain(1, 1)
	var opponent := plain(2, 2)
	Match.map[3].coordinate = Vector2i(0, 2)
	var second_friend := plain(1, 3)
	var distant := plain(1, 4)
	var own := TargetRef.unit(bard.iun)
	Action.return_to_hand(own, TargetRef.unit(distant.iun))
	check(Match.rules_runner.active == null, "Out-of-range Return opens no Bard trigger")
	var tokens: int = Match.players[1].actions_remaining
	check(play(bard, 1) and choose(own) and not choose(TargetRef.unit(opponent.iun)) \
		and not choose(TargetRef.unit(second_friend.iun)) and choose(TargetRef.unit(friend.iun)),
		"Printed Return accepts an adjacent friend and excludes the enemy and distance-two friend")
	if Match.rules_runner.active != null: Match.rules_runner.active.confirm(true)
	check(choose(TargetRef.unit(opponent.iun)) and opponent.ihx == 1, "Bard can move an opponent from range two onto the recorded hex")
	check(Match.players[1].actions_remaining == tokens and bard._counter_value(UnitInfo.STUN_COUNTER) == 1,
		"Return pays self-Stun without spending an action")
	check(events.any(func(event: EffectEvent) -> bool: return event.action == &"shifted" and event.subject.id == opponent.iun) \
		and not events.any(func(event: EffectEvent) -> bool: return event.action == &"move" and event.subject.id == opponent.iun),
		"Bard movement emits Shifted without a voluntary Move")
	Action.return_to_hand(own, TargetRef.unit(second_friend.iun))
	var second := Match.rules_runner.active
	check(second != null and second.status == EffectExecution.Status.CONFIRMING, "A Return at distance two can trigger again this turn")
	if second != null: second.confirm(true)
	check(choose(own) and bard.ihx == 3, "The Bard remains an eligible relocation subject")

## The Jester must choose Flee before impact and can repeat in the same turn without spending its Deploy Soul.
func test_guinea_pig_jester() -> void:
	for family in [&"bow", &"fire", &"cannon", &"bash"]:
		fixture()
		var attacker := plain(1, 0)
		var jester := add(FrontierRecruits.guinea_pig_jester(2), 2)
		var actor := TargetRef.unit(attacker.iun)
		var own := TargetRef.unit(jester.iun)
		var aim := TargetRef.hex(2)
		Match.action_event.emit(EffectEvent.new(&"deploy", own, aim))
		check(jester._counter_value(&"Soul") == 1, "Jester Deploy grants one Soul")
		CombatResolver.declare_bow(actor, TargetRef.hex(1), 1, 3, false, false)
		check(Match.rules_runner.active == null, "A Bow aimed at an empty hex does not use Jester's reaction")
		var declared := false
		match family:
			&"bow": declared = CombatResolver.declare_bow(actor, aim, 9, 3, true, false)
			&"fire": declared = CombatResolver.declare_fire(actor, aim, 9, true, false)
			&"cannon": declared = CombatResolver.declare_cannon(actor, TargetRef.hex(3), 9, 3, true, false)
			&"bash": declared = CombatResolver.move_unit(actor, aim, 2, false)
		var response := Match.rules_runner.active
		check(declared and response != null and response.status == EffectExecution.Status.CONSEQUENCE and jester.actual_life == 2,
			"Jester can answer %s before it takes damage" % family)
		check(not choose(TargetRef.hex(5)) and choose(TargetRef.hex(4)), "Jester flees at most two steps")
		check(jester.ihx == 4 and jester.actual_life == 2 and jester._counter_value(&"Soul") == 1,
			"The Jester escapes the original victim or Cannon line")
		check(not Match.rules_runner.busy() and Match.bashes.is_empty(), "The reaction releases impact or cancels its original Bash")
		Action.decrement(own, TargetRef.property(own, &"Soul"), 1)
		CombatResolver.declare_bow(actor, TargetRef.hex(4), 1, 5, false, false)
		check(choose(TargetRef.hex(5)) and jester._counter_value(&"Soul") == 0, "Jester flees again without a Soul")

## Cleric's implicit Walk and friendly Mshield support repeated three-life gains after physical contact only.
func test_hedgehog_cleric() -> void:
	fixture()
	var cleric := add(FrontierRecruits.hedgehog_cleric(1), 0)
	var ally := plain(1, 4)
	var attacker := plain(2, 5, 1)
	var own := TargetRef.unit(cleric.iun)
	var target := TargetRef.unit(ally.iun)
	var actor := TargetRef.unit(attacker.iun)
	check(cleric.effects[1].implicit, "Cleric has the ordinary implicit Walk 1")
	ally.actual_life = 4
	Match.active_player = 2
	CombatResolver.declare_bow(actor, TargetRef.hex(4), 1, 2, true, true)
	check(ally.actual_life == 3 and ally._counter_value(UnitInfo.SHIELD_COUNTER) == 0, "Physical contact without Mshield gives no treatment")
	Match.active_player = 1
	check(play(cleric, 0) and choose(own) and not choose(actor) and choose(target) \
		and ally._counter_value(UnitInfo.MSHIELD_COUNTER) == 1, "Cleric gives Mshield 1 to a distant friend")
	Match.active_player = 2
	CombatResolver.declare_bow(actor, TargetRef.hex(4), 1, 2, true, true)
	check(ally.actual_life == 5 and ally._counter_value(UnitInfo.SHIELD_COUNTER) == 1,
		"The surviving friend gains exactly three life and one Shield")
	CombatResolver.declare_bow(actor, TargetRef.hex(4), 1, 2, true, true)
	check(ally.actual_life == 7 and ally._counter_value(UnitInfo.MSHIELD_COUNTER) == 1,
		"Physical contact preserves Mshield and the same friend can trigger again")
	CombatResolver.declare_fire(actor, TargetRef.hex(4), 1, true, false)
	check(ally.actual_life == 7 and ally._counter_value(UnitInfo.MSHIELD_COUNTER) == 0, "Magical contact consumes Mshield without treatment")
	Action.shield(own, target, 1, true)
	CombatResolver.declare_bow(actor, TargetRef.hex(4), 20, 2, true, true)
	check(ally.t_state == Enum.t_state.DEFEATED and ally._counter_value(UnitInfo.SHIELD_COUNTER) == 0,
		"Lethal physical contact cannot trigger treatment despite the Mshield")

## A friendly Wound grants Shield before its free forced Flee, while enemy wounds and mere contact do not.
func test_hedgehog_musketeer() -> void:
	fixture()
	var musketeer := add(FrontierRecruits.hedgehog_musketeer(1), 0)
	var ally := plain(1, 1)
	var enemy := plain(2, 4)
	var own := TargetRef.unit(musketeer.iun)
	Match.action_event.emit(EffectEvent.new(&"deploy", own, TargetRef.hex(0)))
	contact(&"hit", musketeer, ally, &"cannon", 0)
	contact(&"wound", musketeer, enemy, &"cannon")
	check(Match.rules_runner.active == null and ally._counter_value(UnitInfo.SHIELD_COUNTER) == 0,
		"Enemy wounds and friendly Hit without Wound give no Shield or Flee")
	check(play(musketeer, 1) and choose(TargetRef.hex(1)) \
		and musketeer._counter_value(UnitInfo.PROJECTILE_COUNTER) == 1,
		"The printed Cannon pays one of its two Deploy projectiles")
	CombatResolver.resolve_cannon(Match.pending_cannon_attacks.pop_front())
	check(ally.actual_life == ally.max_life - 2 and ally._counter_value(UnitInfo.SHIELD_COUNTER) == 2,
		"The exact friendly Cannon victim is Shielded before choosing Flee")
	check(choose(TargetRef.hex(2)) and ally.ihx == 2 and ally.last_displaced_turn == Match.turn_number,
		"The recipient uses its own movement and is moved by the Musketeer")
	ally.actual_life = 0
	contact(&"wound", musketeer, ally, &"cannon")
	check(Match.rules_runner.active == null and ally._counter_value(UnitInfo.SHIELD_COUNTER) == 2,
		"A lethal Wound cannot give Shield or Flee to its casualty")
	var temple := plain(1, 3)
	temple.type = Enum.type.TEMPLE
	contact(&"wound", musketeer, temple, &"cannon")
	check(temple.ihx == 3 and temple._counter_value(UnitInfo.SHIELD_COUNTER) == 2 and Match.rules_runner.active == null,
		"An immovable friend keeps the Shield even with no legal Flee")

## Monk converts a friend's exact Stun into an enemy counter and adds one live action at the hero threshold.
func test_lemming_monk() -> void:
	fixture()
	var monk := add(FrontierRecruits.lemming_monk(1), 0)
	var donor := plain(1, 1)
	var distant := plain(1, 3)
	var hero := plain(2, 5)
	hero.type = Enum.type.HERO
	for unit in [donor, distant, hero]: unit._change_action_counter(UnitInfo.STUN_COUNTER, 1 if unit != hero else 4)
	var owner := Match.players[1]
	var tokens: int = owner.actions_remaining
	check(play(monk, 1) and not choose(TargetRef.property(TargetRef.unit(distant.iun), UnitInfo.STUN_COUNTER)) \
		and choose(TargetRef.property(TargetRef.unit(donor.iun), UnitInfo.STUN_COUNTER)), "Only an adjacent friend's positive Stun can pay")
	check(not choose(TargetRef.unit(donor.iun)) and choose(TargetRef.unit(hero.iun)), "Only a deployed enemy receives the transferred Stun")
	check(donor._counter_value(UnitInfo.STUN_COUNTER) == 0 and hero._counter_value(UnitInfo.STUN_COUNTER) == 5 \
		and hero.active and monk.active and owner.actions_remaining == tokens + 1,
		"The free raw-counter transfer crosses five Stun without altering activity")
	hero._change_action_counter(UnitInfo.STUN_COUNTER, -1)
	check(owner.actions_remaining == tokens and not Match.rules_runner.command_available(monk.effects[1], TargetRef.unit(monk.iun)),
		"Dropping below five removes the allowance and an empty donor cannot pay again")

## Mara's Ash Offering pays self-Stun and a friendly hand Disable together, but spends no player action.
func test_mara_witch() -> void:
	fixture()
	var witch := add(FrontierRecruits.mara_witch(1), 0)
	var recipient := plain(1, 2)
	var distant := plain(1, 3)
	var opponent := plain(2, -1)
	var reserve := plain(1, -1)
	var own := TargetRef.unit(witch.iun)
	var tokens: int = Match.players[1].actions_remaining
	check(play(witch, 2) and choose(own) and not choose(TargetRef.unit(opponent.iun)) and witch.active,
		"Enemy hand cards cannot fund Ash Offering and incomplete costs do not change activity")
	check(choose(TargetRef.unit(reserve.iun)) and reserve.t_state == Enum.t_state.DEFEATED and not witch.active,
		"A friendly hand card and one self-Stun pay together")
	check(not choose(TargetRef.unit(distant.iun)) and choose(TargetRef.unit(recipient.iun)), "Ember can reach an ordinary friend within two")
	check(recipient._counter_value(UnitInfo.EMBER_COUNTER) == 2 and Match.players[1].actions_remaining == tokens,
		"Ash Offering grants two stored Ember without an action token")

## Otter pays one actual Shield and can load any adjacent friend, even without an ammunition action.
func test_otter_blacksmith() -> void:
	fixture()
	var otter := add(FrontierRecruits.otter_blacksmith(1), 0)
	var ally := plain(1, 1)
	var enemy := plain(2, 2)
	var distant := plain(1, 3)
	var own := TargetRef.unit(otter.iun)
	otter._change_action_counter(UnitInfo.PHYSICAL_COUNTER, 3)
	check(not Match.rules_runner.command_available(otter.effects[2], own), "Permanent physical protection cannot fund forging")
	check(play(otter, 1) and choose(own) and choose(own) and otter._counter_value(UnitInfo.SHIELD_COUNTER) == 2,
		"Self Shield stores two counters for future use")
	otter.active = true
	Match.map[2].coordinate = Vector2i(0, 1)
	check(play(otter, 2) and choose(own) and choose(TargetRef.property(own, UnitInfo.SHIELD_COUNTER)), "Forge spends exactly one Shield")
	check(not choose(TargetRef.unit(enemy.iun)) and not choose(TargetRef.unit(distant.iun)) and choose(TargetRef.unit(ally.iun)),
		"Only adjacency and friendly ownership restrict the recipient")
	check(otter._counter_value(UnitInfo.SHIELD_COUNTER) == 1 and ally._counter_value(UnitInfo.PROJECTILE_COUNTER) == 2,
		"One Shield becomes two Projectiles even on a friend without an ammunition action")

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

## The Bow aura is neutral, but only a loaded friend declaring Bash, Bow, Fire or Cannon offers a retreat.
func test_hunter() -> void:
	fixture()
	var hunter := add(FrontierCatalogue.rat_hunter(1), 2)
	var attacker := plain(1, 3)
	var empty := plain(1, 4)
	var enemy := plain(2, 5)
	var ref := TargetRef.unit(attacker.iun)
	check(attacker.effective_bow_bonus() == Vector2i.ZERO, "Empty ammunition does not qualify")
	SynergyActions.add_counter(ref, ref, UnitInfo.PROJECTILE_COUNTER, 1)
	var hostile := TargetRef.unit(enemy.iun)
	SynergyActions.add_counter(hostile, hostile, UnitInfo.PROJECTILE_COUNTER, 1)
	enemy.ihx = 3
	check(attacker.effective_bow_bonus() == Vector2i.ONE and enemy.effective_bow_bonus() == Vector2i.ONE,
		"Loaded adjacent units of either owner get the Bow aura")
	declaration(&"bow", enemy, TargetRef.hex(2))
	enemy.ihx = 5
	Match.action_event.emit(EffectEvent.new(&"bow", ref, TargetRef.hex(2)))
	declaration(&"bow", empty, TargetRef.hex(2))
	declaration(&"gore", attacker, TargetRef.hex(2))
	check(not Match.rules_runner.busy(), "Enemy, unloaded, resolved and Gore events offer no retreat")
	var tokens := Match.players[1].actions_remaining
	declaration(&"bow", attacker, TargetRef.hex(2))
	check(not choose(TargetRef.hex(0)) and choose(TargetRef.hex(1)), "Retreat is exactly one step farther from the attacker")
	check(hunter.ihx == 1 and hunter.active and Match.players[1].actions_remaining == tokens, "Retreat pays neither activity nor an action")
	check(attacker.effective_bow_bonus() == Vector2i.ZERO, "The adjacency bonus disappears after retreat")
	for action in [&"bash", &"fire", &"cannon"]:
		hunter.ihx = 2
		var target := hostile if action == &"bash" else TargetRef.hex(5)
		declaration(action, attacker, target)
		check(choose(TargetRef.hex(1)), "%s uses the attacking friend as the retreat anchor" % action)

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

## Crossbowman needs its own ammo for Bow, loads on its own Deploy and gains Bow damage on its own Hit.
func test_crossbowman() -> void:
	fixture()
	var crossbowman := add(FrontierCatalogue.marmot_crossbowman(1), 0)
	var ally := plain(1, 1)
	var enemy := plain(2, 2)
	check(not play(crossbowman, 0) and crossbowman.active and Match.pending_bow_attacks.is_empty(),
		"An unloaded Crossbowman cannot shoot or pay activity")
	Match.action_event.emit(EffectEvent.new(&"deploy", TargetRef.unit(ally.iun), TargetRef.hex(1)))
	check(crossbowman._counter_value(UnitInfo.PROJECTILE_COUNTER) == 0, "Another card's Deploy grants no Projectiles")
	Match.action_event.emit(EffectEvent.new(&"deploy", TargetRef.unit(crossbowman.iun), TargetRef.hex(0)))
	check(crossbowman._counter_value(UnitInfo.PROJECTILE_COUNTER) == 2, "Own Deploy grants two Projectiles")
	contact(&"hit", ally, enemy)
	contact(&"wound", crossbowman, enemy)
	check(crossbowman.bow_damage_bonus == 0, "An ally's Hit and a standalone Wound do not qualify")
	contact(&"hit", crossbowman, enemy, &"bow", 0)
	check(crossbowman.bow_damage_bonus == 1 and crossbowman.bow_range_bonus == 0, "Own contact adds damage even when blocked by modifiers")

## Paladin pays self-Stun and enemy-hero Shield atomically before a selected friendly Bash participant receives Shield.
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
	check(play(paladin, 1) and choose(TargetRef.unit(paladin.iun)), "Paladin selects one self-Stun as part of the payment")
	check(paladin.active and not choose(TargetRef.unit(enemy.iun)), "Ordinary opponents cannot pay the enemy-hero Shield cost")
	check(choose(TargetRef.unit(hero.iun)), "Only the deployed enemy hero can take the payment Shield")
	check(not paladin.active and hero._counter_value(UnitInfo.TEMP_PHYSICAL_COUNTER) == 2 \
		and ally._counter_value(UnitInfo.TEMP_PHYSICAL_COUNTER) == 0, "Enemy hero is shielded before the friendly consequence")
	check(not choose(TargetRef.unit(bystander.iun)) and not choose(TargetRef.unit(enemy.iun)), "Nonparticipant friend and Bash enemy cannot take the consequence")
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
		var uses_projectiles := unit.uuid.begins_with("marmot-crossbowman")
		if uses_projectiles:
			Match.action_event.emit(EffectEvent.new(&"deploy", TargetRef.unit(unit.iun), TargetRef.hex(0)))
		var tokens := Match.players[1].actions_remaining
		check(play(unit, 0) and (uses_projectiles or choose(TargetRef.unit(unit.iun))),
			"%s starts its printed command and pays activity" % unit.name)
		if uses_projectiles:
			check(unit._counter_value(UnitInfo.PROJECTILE_COUNTER) == 1,
				"Marmot Crossbowman spends exactly one of its own Projectiles automatically")
		check(not choose(TargetRef.hex(reach + 1)) and choose(TargetRef.hex(reach)), "%s enforces its printed reach" % unit.name)
		check(not unit.active and unit._counter_value(UnitInfo.STUN_COUNTER) == 1, "%s pays one self-Stun" % unit.name)
		check(Match.players[1].actions_remaining == tokens - (0 if unit == cards.back() else 1), "%s pays its printed action policy" % unit.name)
		match action:
			&"move", &"fly": check(unit.ihx == reach, "%s lands at the chosen hex" % unit.name)
			&"fire": check(Match.pending_attacks.size() == 1, "%s queues Fire" % unit.name)
			&"cannon": check(Match.pending_cannon_attacks.size() == reach, "%s queues the selected Cannon line" % unit.name)
			&"bow": check(Match.pending_bow_attacks.size() == 1, "%s queues Bow" % unit.name)

## Card wording omits implicit legality checks while preserving payment, the affected recipient and amount provenance.
func test_concise_rule_text() -> void:
	var engineer := FrontierCatalogue.beaver_engineer(1)
	var paladin := FrontierCatalogue.red_squirrel_paladin(1)
	var alchemist := FrontierCatalogue.mole_alchemist(1)
	var wizard := FrontierCatalogue.lemming_wizard(1)
	var thief := FrontierCatalogue.flying_squirrel_thief(1)
	var hunter := FrontierCatalogue.rat_hunter(1)
	check(not EffectText.describe_effect(engineer.effects[1], engineer).contains("if "), "Engineer target existence is implicit")
	var shield := EffectText.describe_effect(paladin.effects[1], paladin)
	check(shield.contains("[lb]S[rb]") and not shield.contains("if ") and shield.find("enemy hero") < shield.find("friend in a Bash"),
		"Paladin shows its cost before the friendly Shield")
	var sacrifice := EffectText.describe_effect(alchemist.effects[1], alchemist)
	check(sacrifice.contains("sacrifice another friend") and sacrifice.contains("+X Embers") and sacrifice.contains("current life"),
		"Alchemist names the paid target's life without an implicit deployment clause")
	check(not EffectText.describe_effect(wizard.trigger_effects[0], wizard).contains("deployed"), "Wizard implies deployed friends")
	check(EffectText.describe_effect(thief.trigger_effects[0], thief).contains(EffectText.life_change(1, 1)),
		"Thief uses compact heart notation")
	check(EffectText.describe_effect(hunter.trigger_effects[0], hunter).begins_with("friend with Projectiles attacks: Walk 1 away from it"),
		"Hunter's retreat names the attacking friend once")
