## Focused approved-roster regressions; create/update freely, execute only on a user request ending TEST.
extends Node

var failures := 0
var checks := 0
var events: Array[EffectEvent] = []

## The dedicated headless scene exercises counter results, eligibility, ownership and exclusions through production rules.
func _ready() -> void:
	Match.action_event.connect(record)
	test_control_archer()
	test_naturalist()
	test_ammunition()
	test_warrior_and_wizard()
	test_warrior_upgrade()
	test_guardians()
	test_ranged_shields()
	test_beavers()
	test_jerboa_combat()
	test_assassin_bash_and_exclusion()
	test_banner()
	test_chinchilla_and_knight()
	test_tamia_archers()
	test_ember_capture()
	test_fire_contact_payoffs()
	test_cannon_contact_payoffs()
	test_blue_mage()
	test_courier()
	test_sacrifice()
	test_sacrifice_preflight_and_departure()
	test_hero_sacrifice_window()
	test_sentinel()
	test_pikeman_actions()
	test_registration_and_text()
	print("Approved synergy units: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)

## Retains immutable occurrences so tests can distinguish payments, attack declaration and actual contact.
func record(event: EffectEvent) -> void:
	events.append(event)

## Reports independent semantic failures while allowing later scenarios to run.
func check(value: bool, message: String) -> void:
	checks += 1
	if value: return
	failures += 1
	push_error(message)

## Rebuilds a straight six-hex board with high resources and no presentation gate; each scenario owns its identities.
func fixture() -> void:
	Match.reset_combat()
	Match.rules_runner.trigger_acknowledgements_enabled = false
	Match.rules_runner.presentation_busy_query = Callable()
	Match.army.clear()
	Match.map.clear()
	events.clear()
	for index in 6: Match.map.append(HexInfo.new(index, Vector2i(index, 0), Enum.region.FRONT, Enum.side.NONE, 0))
	for player in Match.players.values():
		player.actions_remaining = 20
		player.action_allowance = 20
		player.deployments_remaining = 3
		player.has_deployed = true

## Adds one printed card at a stable ID; negative hex means hand and does not manufacture a Deploy occurrence.
func add(unit: UnitInfo, hex_id: int) -> UnitInfo:
	unit.iun = Match.army.size()
	unit.ihx = hex_id
	unit.t_state = Enum.t_state.DEPLOYED if hex_id >= 0 else Enum.t_state.UNDEPLOYED
	unit.active = hex_id >= 0
	unit.ensure_implicit_walk()
	unit.capture_printed_state()
	Match.army.append(unit)
	return unit

## Supplies an untriggered body for ownership, immunity and range exclusions.
func plain(owner: int, hex_id: int, life: int = 8) -> UnitInfo:
	var unit := UnitInfo.new()
	unit.player = owner
	unit.name = "Body"
	unit.uuid = "body-%d" % Match.army.size()
	unit.actual_life = life
	unit.max_life = life
	return add(unit, hex_id)

## Submits one exact choice through the retained production phrase; stale or ineligible choices return false.
func choose(ref: TargetRef) -> bool:
	var run := Match.rules_runner.active
	return run != null and run.current != null and run.current.choose(ref)

## Source/victim helpers publish contact history without declaring a second attack; the runner captures real card definitions.
func contact(action: StringName, actor: UnitInfo, victim: UnitInfo, kind: StringName = &"bow", damage: int = 1) -> void:
	Match.action_event.emit(EffectEvent.new(action, TargetRef.unit(actor.iun), TargetRef.unit(victim.iun),
		{"kind": kind, "damage": damage}))

## Archer awards stored control only on its own Wound; effective physical does not enter regional strength.
func test_control_archer() -> void:
	fixture()
	var archer := add(SynergyCatalogue.grey_squirrel_archer(1), 0)
	var friend := plain(1, 1)
	var enemy := plain(2, 3)
	var before := ControlResolver.strength(Match.map[0], 1)
	contact(&"hit", archer, enemy, &"bow", 0)
	contact(&"wound", friend, enemy)
	check(archer._counter_value(UnitInfo.CONTROL_COUNTER) == 0, "Archer ignores mere Hit and another actor's Wound")
	contact(&"wound", archer, enemy)
	check(archer._counter_value(UnitInfo.CONTROL_COUNTER) == 2, "Archer's Wound awards two control counters")
	check(ControlResolver.strength(Match.map[0], 1) == before + 2, "Stored control contributes once to regional strength")
	Action.return_to_hand(TargetRef.unit(archer.iun), TargetRef.unit(archer.iun))
	contact(&"wound", archer, enemy)
	check(archer._counter_value(UnitInfo.CONTROL_COUNTER) == 2, "Off-board archer cannot capture new wounds")

## Naturalist's [2S] costs no action; the separate Reset remains ordinary [AS] and exact adjacent-friendly selection.
func test_naturalist() -> void:
	fixture()
	var unit := add(SynergyCatalogue.grey_squirrel_naturalist(1), 0)
	var enemy := plain(2, 1)
	check(Match.rules_runner.submit(unit.effects[0], TargetRef.unit(unit.iun)), "Naturalist offers two-Stun payment")
	check(choose(TargetRef.unit(unit.iun)) and choose(TargetRef.unit(enemy.iun)), "Naturalist pays SELF and selects hostile recipient")
	check(unit._counter_value(&"stun") == 2 and enemy._counter_value(&"stun") == 2 and Match.players[1].actions_remaining == 20, "[2S] pays two self-Stun but no action")
	unit.active = true
	enemy.player = 1
	enemy.actual_life = 1
	check(Match.rules_runner.submit(unit.effects[1], TargetRef.unit(unit.iun)) and choose(TargetRef.unit(unit.iun)), "Naturalist's Reset pays normal activity")
	check(not choose(TargetRef.unit(unit.iun)) and choose(TargetRef.unit(enemy.iun)), "Reset excludes SELF but accepts exact adjacent friend")
	check(enemy.actual_life == 8 and Match.players[1].actions_remaining == 19, "Reset restores printed life and spends one action")

## Both ammunition cards gain only on own Deploy, preserve ammo on Return, and cannot fire without a cumulative resource payment.
func test_ammunition() -> void:
	for cannon in [false, true]:
		fixture()
		var unit := add(SynergyCatalogue.grey_squirrel_musketeer(1) if cannon else SynergyCatalogue.grey_squirrel_crossbowman(1), 0)
		var friend := plain(1, 1)
		var enemy := plain(2, 2)
		check(not Match.rules_runner.command_available(unit.effects[0], TargetRef.unit(unit.iun)), "Zero-ammo ranged command unavailable")
		Match.action_event.emit(EffectEvent.new(&"deploy", TargetRef.unit(friend.iun), TargetRef.hex(1)))
		check(unit._counter_value(UnitInfo.PROJECTILE_COUNTER) == 0, "Other unit's Deploy cannot load ammunition")
		Match.action_event.emit(EffectEvent.new(&"deploy", TargetRef.unit(unit.iun), TargetRef.hex(0)))
		check(unit._counter_value(UnitInfo.PROJECTILE_COUNTER) == 2, "Own Deploy loads two projectiles")
		check(Match.rules_runner.submit(unit.effects[0], TargetRef.unit(unit.iun)), "Loaded ranged command submits")
		check(choose(TargetRef.unit(unit.iun)) and choose(TargetRef.property(TargetRef.unit(unit.iun), UnitInfo.PROJECTILE_COUNTER)) \
			and choose(TargetRef.hex(2)), "Ammo/activity choices commit before chosen attack")
		check(unit._counter_value(UnitInfo.PROJECTILE_COUNTER) == 1 and unit._counter_value(&"stun") == 1 and Match.players[1].actions_remaining == 19, "One shot spends exactly ammo, activity and action")
		if cannon:
			contact(&"wound", unit, enemy, &"cannon")
			check(unit._counter_value(UnitInfo.PROJECTILE_COUNTER) == 1, "Enemy wound does not refund Musketeer ammo")
			contact(&"wound", unit, friend, &"cannon")
			check(unit._counter_value(UnitInfo.PROJECTILE_COUNTER) == 2, "Friendly wound refunds one Musketeer projectile")
		Action.reset_unit(TargetRef.unit(unit.iun), TargetRef.unit(unit.iun))
		check(unit._counter_value(UnitInfo.PROJECTILE_COUNTER) == 0, "Reset clears ammo and does not manufacture Deploy")

## Bow-specific friendly wounds and friendly Reset recipients award only their own resource watchers.
func test_warrior_and_wizard() -> void:
	fixture()
	var warrior := add(SynergyCatalogue.grey_squirrel_warrior(1), 0)
	var wizard := add(SynergyCatalogue.grey_squirrel_wizard(1), 1)
	var enemy := plain(2, 3)
	contact(&"wound", enemy, warrior)
	contact(&"wound", warrior, enemy, &"cannon")
	check(warrior._counter_value(&"Soul") == 0, "Warrior ignores hostile actors and non-Bow wounds")
	contact(&"wound", wizard, enemy)
	check(warrior._counter_value(&"Soul") == 1 and wizard._counter_value(&"Soul") == 0, "Friendly Bow wound awards Soul only to Warrior")
	Action.reset_unit(TargetRef.unit(warrior.iun), TargetRef.unit(enemy.iun))
	check(wizard._counter_value(&"Soul") == 0, "Wizard ignores enemy Reset recipient")
	Action.reset_unit(TargetRef.unit(enemy.iun), TargetRef.unit(warrior.iun))
	check(wizard._counter_value(&"Soul") == 1, "Wizard observes friendly recipient regardless of Reset actor")
	check(Match.rules_runner.submit(wizard.effects[0], TargetRef.unit(wizard.iun)) \
		and choose(TargetRef.unit(wizard.iun)) and choose(TargetRef.property(TargetRef.unit(wizard.iun), &"Soul")), "Wizard preflights one Soul plus activity")
	check(not choose(TargetRef.unit(enemy.iun)) and choose(TargetRef.unit(warrior.iun)), "Return uses exact adjacency rather than global friend range")
	check(warrior.t_state == Enum.t_state.UNDEPLOYED and wizard._counter_value(&"Soul") == 0, "Wizard spends Soul and Returns the exact friend")

## Guardian thresholds use physical totals and ownership globally; both exclude weak/enemy/off-board recipients and never write counters.
func test_guardians() -> void:
	fixture()
	var bow_guard := add(SynergyCatalogue.grey_squirrel_guardian(1), 0)
	var magic_guard := add(SynergyCatalogue.beaver_guardian(1), 2)
	var friend := plain(1, 1)
	var enemy := plain(2, 3)
	friend._change_action_counter(UnitInfo.PHYSICAL_COUNTER, 3)
	enemy._change_action_counter(UnitInfo.PHYSICAL_COUNTER, 3)
	check(friend.effective_bow_bonus().x == 1 and friend.magical_modifier == 1, "Both Guardian auras reward a high-physical adjacent friend")
	friend.ihx = 5
	check(friend.effective_bow_bonus().x == 1 and friend.magical_modifier == 1, "Both Guardian auras reach a distant friendly unit without adjacency")
	friend.t_state = Enum.t_state.UNDEPLOYED
	check(friend.effective_bow_bonus().x == 0 and friend.magical_modifier == 0, "Undeployed high-physical recipient gains neither aura")
	friend.t_state = Enum.t_state.DEPLOYED
	friend.ihx = 5
	check(enemy.magical_modifier == 0 and enemy.effective_bow_bonus() == Vector2i.ZERO, "Enemy above threshold gains neither friendly aura")
	friend._counter_property(UnitInfo.PHYSICAL_COUNTER).value = -10
	check(friend.effective_bow_bonus().x == 0 and friend.magical_modifier == 0, "Dropping below threshold removes both derived bonuses")
	check(bow_guard._counter_value(UnitInfo.BOW_DAMAGE_COUNTER) == 0 and magic_guard._counter_value(UnitInfo.MAGICAL_COUNTER) == 0, "Guardian auras never mutate recipient counters")
	friend._counter_property(UnitInfo.PHYSICAL_COUNTER).value = 3
	bow_guard.t_state = Enum.t_state.UNDEPLOYED
	magic_guard.t_state = Enum.t_state.UNDEPLOYED
	check(friend.effective_bow_bonus().x == 0 and friend.magical_modifier == 0, "Off-board Guardian sources cannot provide global support")

## Warrior's two-Soul Upgrade preserves exact recipient/ability identity and excludes enemies or friends beyond the printed radius.
func test_warrior_upgrade() -> void:
	fixture()
	var warrior := add(SynergyCatalogue.grey_squirrel_warrior(1), 0)
	var archer := add(SynergyCatalogue.grey_squirrel_archer(1), 1)
	var enemy := add(SynergyCatalogue.tamia_archer(2), 2)
	var distant := add(SynergyCatalogue.tamia_archer(1), 5)
	check(not Match.rules_runner.command_available(warrior.effects[1], TargetRef.unit(warrior.iun)), "Warrior cannot offer Upgrade without its two Souls")
	warrior._change_action_counter(&"Soul", 2)
	check(Match.rules_runner.submit(warrior.effects[1], TargetRef.unit(warrior.iun)) and choose(TargetRef.unit(warrior.iun)) \
		and choose(TargetRef.property(TargetRef.unit(warrior.iun), &"Soul")), "Warrior preflights AS and two Souls")
	check(not choose(TargetRef.unit(enemy.iun)) and not choose(TargetRef.unit(distant.iun)) and choose(TargetRef.unit(archer.iun)), "Upgrade chooses only an eligible friendly unit within two")
	var option: EffectOption
	for candidate in archer.effect_options():
		if candidate.category == &"effects" and candidate.definition == archer.effects[0]: option = candidate
	check(option != null and choose(TargetRef.property(TargetRef.unit(archer.iun), option.name)), "Upgrade chooses that recipient's exact Bow ability")
	check(archer.ability_bonus(archer.effects[0].consequence.verb) == Vector2i(1, 0) \
		and archer.bow_damage_bonus == 0 and warrior._counter_value(&"Soul") == 0, "Upgrade stores damage-only on the exact ability, not a family counter")

## The three ranged Shield cards apply only to a selected friend within one and pay AS once.
func test_ranged_shields() -> void:
	for index in 3:
		fixture()
		var cards := [SynergyCatalogue.grey_squirrel_guardian(1), SynergyCatalogue.beaver_guardian(1), SynergyCatalogue.marmot_paladin(1)]
		var source := add(cards[index], 0)
		var friend := plain(1, 1)
		var enemy := plain(2, 2)
		var distant := plain(1, 4)
		check(Match.rules_runner.submit(source.effects[0], TargetRef.unit(source.iun)) and choose(TargetRef.unit(source.iun)), "Ranged Shield collects ordinary activity")
		check(not choose(TargetRef.unit(enemy.iun)) and not choose(TargetRef.unit(distant.iun)) and choose(TargetRef.unit(friend.iun)), "Shield rejects enemy/distant targets and accepts a friend within one")
		check(friend._counter_value(UnitInfo.TEMP_PHYSICAL_COUNTER) == (3 if index == 1 else 2) \
			and source._counter_value(&"stun") == 1 and Match.players[1].actions_remaining == 19, "Ranged Shield applies the printed protection and one AS payment")

## Beaver protection follows an inert bomb live; Architect earns Soul only from its own successful Defuse and spends it on Bomb 3.
func test_beavers() -> void:
	fixture()
	var warrior := add(SynergyCatalogue.beaver_warrior(1), 0)
	var architect := add(SynergyCatalogue.beaver_architect(1), 1)
	var enemy := plain(2, 2)
	var bomb := BombInfo.new()
	bomb.hex_id = 1
	bomb.damage = 1
	Match.bombs.append(bomb)
	check(warrior.magical_modifier == 1 and architect.magical_modifier == 1 and enemy.magical_modifier == 0, "Warrior's own magic and bomb aura are separate friendly contributions")
	check(CombatResolver.defuse_bomb(TargetRef.unit(architect.iun), TargetRef.hex(1), 2, true), "Architect defuses an existing inert bomb")
	check(architect._counter_value(&"Soul") == 1 and architect.magical_modifier == 0, "Successful own Defuse earns Soul and removes inert-bomb aura")
	check(not CombatResolver.defuse_bomb(TargetRef.unit(architect.iun), TargetRef.hex(1), 2, true) and architect._counter_value(&"Soul") == 1, "Failed repeated Defuse earns nothing")
	check(Match.rules_runner.submit(architect.effects[0], TargetRef.unit(architect.iun)) and choose(TargetRef.unit(architect.iun)) \
		and choose(TargetRef.property(TargetRef.unit(architect.iun), &"Soul")) and choose(TargetRef.hex(3)), "Architect pays one Soul before placing a ranged bomb")
	check(Match.bomb_at(3) != null and Match.bomb_at(3).damage == 3 and architect._counter_value(&"Soul") == 0, "Architect places Bomb 3 without creating resources")

## Jerboa Warrior's derived Bash condition and Assassin's two native passives preserve existing combat semantics.
func test_jerboa_combat() -> void:
	fixture()
	var warrior := add(SynergyCatalogue.jerboa_warrior(1), 0)
	var enemy := plain(2, 0)
	var assassin := add(SynergyCatalogue.jerboa_assassin(1), 2)
	var bash := BashInfo.new()
	bash.attacker_id = warrior.iun
	bash.defender_id = enemy.iun
	bash.target_hex = 0
	Match.bashes.append(bash)
	var before := warrior.physical_modifier
	enemy._change_action_counter(&"stun", 1)
	check(warrior.physical_modifier == before + 3, "Stunned opposing Bash participant grants exactly +3 physical")
	bash.resolved = true
	check(warrior.physical_modifier == before and warrior._counter_value(UnitInfo.PHYSICAL_COUNTER) == 0, "Resolved Bash removes the bonus without stored counters")
	check(assassin.has_effective_flag(&"steady") and assassin.has_effective_flag(&"first-strike"), "Assassin has both printed Bash passives")

## Assassin's Steady and First Strike combine to defeat an armoured equal-life enemy before retaliation; neither makes Bow ignore armour.
func test_assassin_bash_and_exclusion() -> void:
	fixture()
	var assassin := add(SynergyCatalogue.jerboa_assassin(1), 0)
	var enemy := plain(2, 0, 2)
	enemy._change_action_counter(UnitInfo.PHYSICAL_COUNTER, 10)
	CombatResolver._create_bash(assassin.iun, enemy.iun, 0)
	CombatResolver.resolve_bash(Match.bashes[0], 2)
	check(enemy.t_state == Enum.t_state.DEFEATED and assassin.actual_life == 2, "Assassin ignores Bash opponent's armour and defeats it before retaliation")
	check(enemy._counter_value(UnitInfo.PHYSICAL_COUNTER) == 10, "Steady suppresses effective Bash protection without deleting persistent counters")
	fixture()
	assassin = add(SynergyCatalogue.jerboa_assassin(1), 0)
	enemy = plain(2, 1, 2)
	enemy._change_action_counter(UnitInfo.PHYSICAL_COUNTER, 10)
	CombatResolver.declare_bow(TargetRef.unit(assassin.iun), TargetRef.hex(1), 1, 1, true, false, true)
	check(enemy.actual_life == 2 and assassin.actual_life == 2, "Steady/First Strike do not pierce or add a Bash exchange to a Bow attack")

## Banner requires exact adjacency, the opposing Bash identity and current-turn forced movement; Reset preserves historical displacement.
## Banner now rewards adjacent friendly Bash participation without requiring current-turn forced movement.
func test_banner() -> void:
	fixture()
	var pusher := plain(1, 0)
	var enemy := plain(2, 1)
	var fighter := plain(1, 2)
	var banner := add(SynergyCatalogue.jerboa_banner_bearer(1), 3)
	enemy.ihx = fighter.ihx
	CombatResolver._create_bash(enemy.iun, fighter.iun, fighter.ihx)
	check(banner.continuous_effects[0].evaluate(banner.iun, fighter.iun) == Vector2i(1, 0), "Banner grants +1 for ordinary adjacent friendly Bash participation")
	check(banner.continuous_effects[0].evaluate(banner.iun, enemy.iun) == Vector2i.ZERO, "Banner cannot support an opposing occupant")
	Action.reset_unit(TargetRef.unit(pusher.iun), TargetRef.unit(enemy.iun))
	check(banner.continuous_effects[0].evaluate(banner.iun, fighter.iun).x == 1, "Opponent Reset does not remove an unresolved friendly Bash bonus")
	Match.turn_number += 1
	check(banner.continuous_effects[0].evaluate(banner.iun, fighter.iun) == Vector2i(1, 0), "Bash support does not depend on displacement turn history")
	check(banner.continuous_effects[0].evaluate(banner.iun, pusher.iun) == Vector2i.ZERO, "Nonadjacent non-bashing friend receives no support")
	fighter.ihx = 5
	check(banner.continuous_effects[0].evaluate(banner.iun, fighter.iun) == Vector2i.ZERO, "Moving outside adjacency removes support")
	fighter.ihx = 2
	Match.bashes[0].resolved = true
	check(banner.continuous_effects[0].evaluate(banner.iun, fighter.iun) == Vector2i.ZERO, "Resolved Bash removes support")

## Soldier's mandatory Return excludes SELF; Knight receives three extra ETB Stun and a separate +4 Bash contribution.
func test_chinchilla_and_knight() -> void:
	fixture()
	var soldier := add(SynergyCatalogue.chinchilla_soldier(1), 0)
	var friend := plain(1, 4)
	var enemy := plain(2, 1)
	Match.action_event.emit(EffectEvent.new(&"deploy", TargetRef.unit(soldier.iun), TargetRef.hex(0)))
	check(not choose(TargetRef.unit(soldier.iun)) and not choose(TargetRef.unit(enemy.iun)), "Soldier's forced Return excludes SELF and enemies")
	check(choose(TargetRef.unit(friend.iun)) and friend.t_state == Enum.t_state.UNDEPLOYED, "Soldier Returns a distant friend without a range restriction")
	var knight := add(SynergyCatalogue.tamia_knight(1), 2)
	knight._change_action_counter(&"stun", 1)
	Match.action_event.emit(EffectEvent.new(&"deploy", TargetRef.unit(knight.iun), TargetRef.hex(2)))
	check(knight._counter_value(&"stun") == 4, "Knight's extra three Stun stack with ordinary entry Stun")
	check(knight.state_effects[0].physical == 4, "Knight's printed Bash grant is +4 physical")

## Tamia Archer separates S from A; Crossbowman's own Hit grows range even when damage is zero, but other hits do not.
func test_tamia_archers() -> void:
	fixture()
	var archer := add(SynergyCatalogue.tamia_archer(1), 0)
	var crossbow := add(SynergyCatalogue.tamia_crossbowman(1), 1)
	var enemy := plain(2, 2)
	check(Match.rules_runner.submit(archer.effects[0], TargetRef.unit(archer.iun)) and choose(TargetRef.unit(archer.iun)) \
		and choose(TargetRef.hex(2)), "[S] Archer uses normal activity and legal Bow target")
	check(Match.players[1].actions_remaining == 20 and archer._counter_value(&"stun") == 1, "[S] Archer preserves player action")
	contact(&"hit", archer, enemy)
	check(crossbow.bow_range_bonus == 0, "Other actor's Hit does not upgrade Crossbowman")
	contact(&"hit", crossbow, enemy, &"bow", 0)
	check(crossbow.bow_range_bonus == 1 and crossbow.bow_damage_bonus == 0, "Own zero-damage Hit awards range-only permanent Bow counter")

## Ember is previewed, captured and consumed once at declaration; Reset and later grants cannot rewrite queued Fire values.
func test_ember_capture() -> void:
	fixture()
	var source := add(CardCatalogue.squirrel_king(1), 0)
	plain(2, 2)
	SynergyActions.add_counter(TargetRef.unit(source.iun), TargetRef.unit(source.iun), UnitInfo.EMBER_COUNTER, 3)
	check(source.effective_action_values(&"fire", [1, 3]) == [4, 3], "Ember increases Fire damage without changing range")
	check(CombatResolver.declare_fire(TargetRef.unit(source.iun), TargetRef.hex(2), 1, false, false, true), "Ember-backed Fire declares")
	check(Match.pending_attacks.back().amount == 4 and source._counter_value(UnitInfo.EMBER_COUNTER) == 0, "Declaration captures and consumes all three Ember exactly once")
	SynergyActions.add_counter(TargetRef.unit(source.iun), TargetRef.unit(source.iun), UnitInfo.EMBER_COUNTER, 2)
	check(Match.pending_attacks.back().amount == 4 and source.effective_action_values(&"fire", [1, 3])[0] == 3, "New Ember belongs to a later attack")
	Action.reset_unit(TargetRef.unit(source.iun), TargetRef.unit(source.iun))
	check(source._counter_value(UnitInfo.EMBER_COUNTER) == 0 and Match.pending_attacks.back().amount == 4, "Reset clears unspent Ember without changing queued Fire")

## Actual nonlethal Fire feeds Red Mage/Pyromancer and Soldier; immunity, misses, hostile sources and lethal wounds are distinct outcomes.
func test_fire_contact_payoffs() -> void:
	fixture()
	var red := add(SynergyCatalogue.tamia_red_mage(1), 0)
	var soldier := add(SynergyCatalogue.jerboa_soldier(1), 1)
	var enemy := plain(2, 2)
	check(CombatResolver.declare_fire(TargetRef.unit(red.iun), TargetRef.hex(2), 1, true, false, true), "Red Mage resolves nonlethal Fire")
	check(red._counter_value(UnitInfo.EMBER_COUNTER) == 2 and soldier._counter_value(UnitInfo.TEMP_MAGICAL_COUNTER) == 1, "Nonlethal Fire gives Ember and friendly Soldier Mshield")
	check(enemy.actual_life == 8 and events.filter(func(e: EffectEvent) -> bool: return e.action == &"wound").is_empty(), "Nonlethal Fire is Hit without partial Wound")
	var passive := Prop.new()
	passive.name = &"obsidian"
	passive.value = 1
	passive.increment = Enum.p_increment.FLAG
	passive.target = Enum.p_target.UNIT
	enemy.props.append(passive)
	CombatResolver.declare_fire(TargetRef.unit(red.iun), TargetRef.hex(2), 1, true, false, true)
	check(red._counter_value(UnitInfo.EMBER_COUNTER) == 0 and soldier._counter_value(UnitInfo.TEMP_MAGICAL_COUNTER) == 1, "Immune Fire consumes declared Ember but creates no contact payoff")
	CombatResolver.declare_fire(TargetRef.unit(red.iun), TargetRef.hex(3), 1, true, false, true)
	check(red._counter_value(UnitInfo.EMBER_COUNTER) == 0, "Empty-hex miss is not Hit without Wound")
	enemy.props.erase(passive)
	enemy.actual_life = 1
	CombatResolver.declare_fire(TargetRef.unit(red.iun), TargetRef.hex(2), 1, true, true, true)
	check(enemy.t_state == Enum.t_state.DEFEATED and red._counter_value(UnitInfo.EMBER_COUNTER) == 0, "Lethal Fire emits Wound and does not award failure Ember")
	check(soldier._counter_value(UnitInfo.TEMP_MAGICAL_COUNTER) == 2, "Lethal friendly Fire still gives Soldier one contact reward")
	fixture()
	var pyro := add(SynergyCatalogue.jerboa_pyromancer(1), 0)
	var receiver := plain(1, 1)
	var foe := plain(2, 2)
	var remote := plain(1, 4)
	CombatResolver.declare_fire(TargetRef.unit(pyro.iun), TargetRef.hex(2), 1, true, false, true)
	check(not choose(TargetRef.unit(pyro.iun)) and not choose(TargetRef.unit(foe.iun)) and not choose(TargetRef.unit(remote.iun)), "Pyromancer requires one exact adjacent friend")
	check(choose(TargetRef.unit(receiver.iun)) and receiver._counter_value(UnitInfo.EMBER_COUNTER) == 1, "Pyromancer gives one Ember to the chosen adjacent friend")
	contact(&"hit", foe, receiver, &"fire", 0)
	check(not Match.rules_runner.busy() and receiver._counter_value(UnitInfo.EMBER_COUNTER) == 1, "Another actor's Fire cannot activate Pyromancer")
	fixture()
	var fallen := add(SynergyCatalogue.tamia_red_mage(1), 0)
	soldier = add(SynergyCatalogue.jerboa_soldier(1), 1)
	plain(2, 2)
	CombatResolver.declare_fire(TargetRef.unit(fallen.iun), TargetRef.hex(2), 1, false, false, true)
	var queued: FireAttack = Match.pending_attacks.back()
	Match.defeat(TargetRef.unit(fallen.iun))
	CombatResolver.resolve_fire(queued)
	check(soldier._counter_value(UnitInfo.TEMP_MAGICAL_COUNTER) == 1 and fallen._counter_value(UnitInfo.EMBER_COUNTER) == 0, "A fallen friend's queued Fire still rewards Soldier, while the defeated mage cannot capture a new self trigger")

## Cannon publishes positive magical Wound to exact friendly recipients and preserves no-contact immunity exclusions.
func test_cannon_contact_payoffs() -> void:
	fixture()
	var cannoneer := add(SynergyCatalogue.jerboa_cannoneer(1), 0)
	var friend := plain(1, 1)
	var enemy := plain(2, 2)
	CombatResolver.declare_cannon(TargetRef.unit(cannoneer.iun), TargetRef.hex(2), 1, 3, true, false, true)
	check(friend.actual_life == 7 and friend._counter_value(UnitInfo.EMBER_COUNTER) == 1, "Friendly Cannon Wound awards Ember to that exact victim")
	check(enemy._counter_value(UnitInfo.EMBER_COUNTER) == 0 and cannoneer._counter_value(UnitInfo.EMBER_COUNTER) == 0, "Cannoneer does not award Ember to enemy victims or itself instead of the victim")
	friend._change_action_counter(UnitInfo.MAGICAL_COUNTER, 10)
	CombatResolver.declare_cannon(TargetRef.unit(cannoneer.iun), TargetRef.hex(2), 1, 3, true, false, true)
	check(friend._counter_value(UnitInfo.EMBER_COUNTER) == 1, "Zero-damage Cannon contact is not Wound")
	var hits := events.filter(func(e: EffectEvent) -> bool: return e.action == &"hit" and e.data.get("kind") == &"cannon")
	check(hits.size() == 4, "Two line attacks publish one Hit per contacted occupant, including zero damage")
	var blast := CannonAttack.new()
	blast.explosion = true
	blast.owner = 1
	blast.source_id = cannoneer.iun
	blast.target_hex = 1
	blast.amount = 1
	CombatResolver.resolve_cannon(blast)
	check(events.filter(func(e: EffectEvent) -> bool: return e.action == &"hit").size() == 4 \
		and events.any(func(e: EffectEvent) -> bool: return e.action == &"bomb_hit"), "Bomb blasts retain their separate contact event outside attack families")

## Blue Mage ignores out-of-turn Stun, the opposing player's legal hostile Stun, and own activity costs while amplifying prior friendly hostile Stun once.
func test_blue_mage() -> void:
	fixture()
	var blue := add(SynergyCatalogue.tamia_blue_mage(1), 0)
	var friend := plain(1, 1)
	var enemy := plain(2, 2)
	CombatResolver.stun(TargetRef.unit(friend.iun), TargetRef.unit(enemy.iun), 1, 2, true)
	check(enemy._counter_value(&"stun") == 1, "First Stun on an unstunned target has no Blue Mage bonus")
	CombatResolver.stun(TargetRef.unit(friend.iun), TargetRef.unit(enemy.iun), 1, 2, true)
	check(enemy._counter_value(&"stun") == 3 and not Match.rules_runner.halted, "Already-stunned hostile target gains exactly one extra counter without a loop")
	check(CombatResolver.stun(TargetRef.unit(blue.iun), TargetRef.unit(enemy.iun), 1, 2, true), "Blue Mage can use its own printed hostile Stun")
	check(enemy._counter_value(&"stun") == 4, "Blue Mage's own Stun receives no another-friend bonus")
	friend._change_action_counter(&"stun", 2)
	check(not CombatResolver.stun(TargetRef.unit(enemy.iun), TargetRef.unit(friend.iun), 1, 2, true) \
		and friend._counter_value(&"stun") == 2, "Out-of-turn enemy Stun is rejected before mutation")
	Match.active_player = 2
	check(CombatResolver.stun(TargetRef.unit(enemy.iun), TargetRef.unit(friend.iun), 1, 2, true), "Enemy actor can Stun legally on its own turn")
	check(friend._counter_value(&"stun") == 3, "Enemy Stun actor does not receive friendly Blue Mage support")
	Match.active_player = 1
	Action.pay_activity(TargetRef.unit(blue.iun), TargetRef.unit(blue.iun), true)
	check(blue._counter_value(&"stun") == 1, "Activity self-Stun never recursively earns Blue Mage counters")

## Courier transfers a chosen positive counter kind from either owner, caps X at two, rechecks range and pays S without A.
func test_courier() -> void:
	fixture()
	var courier := add(SynergyCatalogue.jerboa_courier(1), 1)
	var donor := plain(2, 0)
	var recipient := plain(1, 2)
	donor._change_action_counter(&"Soul", 4)
	check(Match.rules_runner.submit(courier.effects[1], TargetRef.unit(courier.iun)) and choose(TargetRef.unit(courier.iun)), "Courier pays [S] without spending player action")
	check(choose(TargetRef.property(TargetRef.unit(donor.iun), &"Soul")), "Courier may select an opposing counter donor in range")
	var current := Match.rules_runner.active.current
	check(current.status == PhraseExecution.Status.AMOUNT and current.amount_max == 2 and not current.choose_amount(3), "Counter amount picker enforces up to two")
	check(current.choose_amount(2), "Courier retains two selected Souls without removing them yet")
	check(donor._counter_value(&"Soul") == 4 and not choose(TargetRef.unit(donor.iun)), "Donor cannot also be destination, and selection has not spent its counters")
	check(choose(TargetRef.unit(recipient.iun)), "Courier commits the other exact recipient")
	check(donor._counter_value(&"Soul") == 2 and recipient._counter_value(&"Soul") == 2 \
		and Match.players[1].actions_remaining == 20 and courier._counter_value(&"stun") == 1, "Transfer conserves Soul and pays only one self-Stun")
	var far := plain(1, 5)
	check(not SynergyActions.transfer_counter(TargetRef.unit(courier.iun), TargetRef.unit(far.iun), donor.iun, &"Soul", 1), "Out-of-range destination cannot commit stale transfer")
	check(not SynergyActions.transfer_counter(TargetRef.unit(courier.iun), TargetRef.unit(recipient.iun), donor.iun, &"Soul", 3), "Transfer rejects oversized amounts even without the picker")

## Both sacrifice commands reject enemies and unpaid resources; Paladin sees Sacrifice rather than ordinary Die and can revive the victim.
func test_sacrifice() -> void:
	fixture()
	var halberdier := add(SynergyCatalogue.marmot_halberdier(1), 0)
	var paladin := add(SynergyCatalogue.marmot_paladin(1), 2)
	var victim := plain(1, 1)
	var enemy := plain(2, 3)
	check(Match.rules_runner.submit(halberdier.effects[1], TargetRef.unit(halberdier.iun)) and choose(TargetRef.unit(halberdier.iun)), "Halberdier collects activity before sacrifice payment")
	check(not choose(TargetRef.unit(enemy.iun)) and choose(TargetRef.unit(victim.iun)), "Sacrifice selection rejects enemies and accepts a friend within two")
	check(victim.t_state == Enum.t_state.DEFEATED and halberdier._counter_value(UnitInfo.PHYSICAL_COUNTER) == 0, "Paid sacrifice releases Paladin choice before the stat consequence")
	check(choose(TargetRef.unit(victim.iun)), "Paladin may revive the just-sacrificed friendly non-hero")
	check(victim.t_state == Enum.t_state.UNDEPLOYED and halberdier.counter_modifiers() == Vector2i(1, 1), "Revive followup completes before paid +1/+1 consequences")
	check(events.filter(func(e: EffectEvent) -> bool: return e.action == &"die").size() == 1 \
		and events.filter(func(e: EffectEvent) -> bool: return e.action == &"sacrifice").size() == 1, "One paid sacrifice emits one Die and one distinct Sacrifice")
	Match.defeat(TargetRef.unit(enemy.iun))
	check(not Match.rules_runner.busy(), "Ordinary enemy Die cannot trigger Paladin's sacrifice rule")
	fixture()
	var warrior := add(SynergyCatalogue.tamia_warrior(1), 0)
	var offering := plain(1, 1)
	var foe := plain(2, 2)
	check(Match.rules_runner.submit(warrior.effects[1], TargetRef.unit(warrior.iun)) and choose(TargetRef.unit(warrior.iun)) \
		and choose(TargetRef.unit(offering.iun)) and choose(TargetRef.hex(2)), "Tamia Warrior pays adjacent sacrifice then selects Instant Bow")
	check(offering.t_state == Enum.t_state.DEFEATED and foe.actual_life == 6 and Match.pending_bow_attacks.is_empty(), "Warrior's Bow resolves instantly with physical modifiers and does not queue another attack")
	check(not Match.rules_runner.command_available(warrior.effects[1], TargetRef.unit(warrior.iun)), "Inactive Warrior cannot pay another [AS] sacrifice")

## Duplicate victims fail before any activity/death mutation, and a sacrificed Paladin retains its own trigger before departure.
func test_sacrifice_preflight_and_departure() -> void:
	fixture()
	var source := add(SynergyCatalogue.marmot_halberdier(1), 0)
	var victim := plain(1, 1)
	var enemy := plain(2, 2)
	check(not SynergyActions.sacrifice(TargetRef.unit(source.iun), TargetRef.unit(enemy.iun)), "The Sacrifice verb itself also rejects enemy ownership")
	var payment := Effect.CostPhrase.new(Selectors.Self.new(), Verbs.sacrifice(),
		Selectors.Literal.new(TargetRef.Kind.UNIT, [TargetRef.unit(victim.iun)]))
	var effect := Effect.new(Effect.CostBundle.new([Collection.action_cost(), payment, payment]), null,
		SynergyRules.phrase(SynergyRules.counter(UnitInfo.PHYSICAL_COUNTER, 1), Selectors.Self.new(), true))
	check(not Match.rules_runner.command_available(effect, TargetRef.unit(source.iun)), "Availability rejects two payments using one victim when no second resource identity is chosen")
	var execution := effect.eval(TargetRef.unit(source.iun))
	execution.current.choose(TargetRef.unit(source.iun))
	execution.current.choose(TargetRef.unit(victim.iun))
	execution.current.choose(TargetRef.unit(victim.iun))
	check(execution.status == EffectExecution.Status.FAILED and source.active and victim.t_state == Enum.t_state.DEPLOYED \
		and source._counter_value(&"stun") == 0, "Duplicate sacrifice preflight pays neither activity nor death")
	fixture()
	source = add(SynergyCatalogue.marmot_halberdier(1), 0)
	var paladin := add(SynergyCatalogue.marmot_paladin(1), 1)
	var old_casualty := plain(1, -1)
	old_casualty.t_state = Enum.t_state.DEFEATED
	old_casualty.actual_life = 0
	check(Match.rules_runner.submit(source.effects[1], TargetRef.unit(source.iun)) and choose(TargetRef.unit(source.iun)) \
		and choose(TargetRef.unit(paladin.iun)), "Paladin itself is a legal friendly sacrifice")
	check(choose(TargetRef.unit(old_casualty.iun)) and old_casualty.t_state == Enum.t_state.UNDEPLOYED \
		and paladin.t_state == Enum.t_state.DEFEATED, "Sacrificed Paladin can still resolve its captured Revive for another friend")

## Sentinel suppresses all watchers of either owner's adjacent Deploy while preserving ordinary entry Stun and nonadjacent triggers.
func test_sentinel() -> void:
	fixture()
	var sentinel := add(SynergyCatalogue.chinchilla_sentinel(1), 0)
	var crossbow := add(SynergyCatalogue.grey_squirrel_crossbowman(2), 1)
	var knight := add(SynergyCatalogue.tamia_knight(1), 2)
	var watcher := plain(2, 4)
	watcher.trigger_effects.append(Effect.on_event(Effect.EventPhrase.observe(&"deploy", QuerySelector.new(),
		QuerySelector.new(TargetRef.Kind.HEX), TargetRef.Kind.UNIT, TargetRef.Kind.HEX),
		SynergyRules.phrase(SynergyRules.counter(&"Soul", 1), Selectors.Self.new(), true)))
	crossbow._change_action_counter(&"stun", 1)
	Match.action_event.emit(EffectEvent.new(&"deploy", TargetRef.unit(crossbow.iun), TargetRef.hex(1)))
	check(crossbow._counter_value(UnitInfo.PROJECTILE_COUNTER) == 0 and watcher._counter_value(&"Soul") == 0, "Adjacent enemy Deploy triggers neither its own ammo nor an external watcher")
	check(crossbow._counter_value(&"stun") == 1, "Suppression does not remove ordinary deployment Stun")
	Match.action_event.emit(EffectEvent.new(&"deploy", TargetRef.unit(knight.iun), TargetRef.hex(2)))
	check(knight._counter_value(&"stun") == 3 and watcher._counter_value(&"Soul") == 1, "Nonadjacent Deploy retains its own and external triggers")
	Action.return_to_hand(TargetRef.unit(sentinel.iun), TargetRef.unit(sentinel.iun))
	Match.action_event.emit(EffectEvent.new(&"deploy", TargetRef.unit(crossbow.iun), TargetRef.hex(1)))
	check(crossbow._counter_value(UnitInfo.PROJECTILE_COUNTER) == 2, "Off-board Sentinel cannot suppress later deployment")

## Pikeman grants one live action per source while bashing, but spending remains tracked through Bash loss/reentry and snapshots.
func test_pikeman_actions() -> void:
	fixture()
	var pikeman := add(SynergyCatalogue.grey_squirrel_pikeman(1), 0)
	var enemy := plain(2, 0)
	var bash := BashInfo.new()
	bash.attacker_id = pikeman.iun
	bash.defender_id = enemy.iun
	bash.target_hex = 0
	Match.bashes.append(bash)
	check(Match.players[1].actions_remaining == 21 and Match.players[2].actions_remaining == 20, "Bashing Pikeman contributes one action only to its owner")
	Match.players[1].actions_remaining -= 1
	bash.resolved = true
	check(Match.players[1].actions_remaining == 19, "Losing the live bonus preserves a spent action")
	bash.resolved = false
	check(Match.players[1].actions_remaining == 20 and Match.players[1].base_actions_remaining == 19, "Reentry restores only the live allowance, never refills spending")
	var snapshot := preload("res://scripts/runtime/match_snapshot.gd")
	var saved: Dictionary = snapshot._capture_state()
	Match.players[1].base_actions_remaining = 100
	snapshot._apply_state(saved)
	check(Match.players[1].base_actions_remaining == 19 and Match.players[1].actions_remaining == 20, "Snapshot retains action ledger independently from live Bash bonus")

## Test-only explicit rescue legality demonstrates the future sacrifice-trigger extension point without changing ordinary non-hero Revive.
func can_rescue_hero(_subject: TargetRef, target: TargetRef, destination: int) -> bool:
	var unit := Match.get_unit(target.id)
	return unit != null and unit.type == Enum.type.HERO and unit.t_state == Enum.t_state.DEFEATED \
		and unit.max_life > 0 and Match.get_hex(destination) != null

## Test-only consequence restores the captured hero through the existing effect-deployment authority path.
func rescue_hero(subject: TargetRef, target: TargetRef, destination: int) -> bool:
	return can_rescue_hero(subject, target, destination) and Match.deploy_from_effect(target.id, destination)

## A sacrificed hero is provisionally defeated while its causal trigger chooses a rescue; without rescue, or with Reset alone, loss follows settlement.
func test_hero_sacrifice_window() -> void:
	for mode in 3:
		fixture()
		var source := add(SynergyCatalogue.marmot_halberdier(1), 2)
		var hero := add(CardCatalogue.squirrel_king(1), 0)
		var watcher := plain(1, 1)
		if mode > 0:
			var heroes := QuerySelector.new()
			heroes.relative_owner = Enum.YOU
			heroes.type = Enum.type.HERO
			var consequence: Effect.ConsequencePhrase
			if mode == 1:
				var defeated := QuerySelector.new()
				defeated.relative_owner = Enum.YOU
				defeated.type = Enum.type.HERO
				defeated.state = Enum.t_state.DEFEATED
				var rescue := Effect.Verb.new(&"test_rescue", rescue_hero, can_rescue_hero,
					TargetRef.Kind.UNIT, TargetRef.Kind.UNIT, [RuleNumber.new(&"last_hex")])
				consequence = SynergyRules.phrase(rescue, defeated)
			else:
				consequence = SynergyRules.phrase(Verbs.reset_unit(), Selectors.Reference.new(Selectors.Anchor.EVENT_TARGET), true)
			watcher.trigger_effects.append(SynergyRules.observe(&"sacrifice", QuerySelector.new(), heroes, consequence))
		check(Match.rules_runner.submit(source.effects[1], TargetRef.unit(source.iun)) and choose(TargetRef.unit(source.iun)) \
			and choose(TargetRef.unit(hero.iun)), "Heroes are eligible friendly sacrifice payments")
		if mode == 1:
			check(Match.winner == 0 and hero.t_state == Enum.t_state.DEFEATED and Match.rules_runner.busy(), "Hero loss waits during a retained sacrifice rescue choice")
			check(choose(TargetRef.unit(hero.iun)) and hero.t_state == Enum.t_state.DEPLOYED \
				and hero.actual_life == hero.max_life and Match.winner == 0, "Explicit sacrifice rescue prevents final hero loss")
		else:
			check(Match.winner == 2 and hero.t_state == Enum.t_state.DEFEATED, "Unrescued or merely Reset sacrificed hero loses after causal work")
		check(Match.players[1].actions_remaining == 19, "A committed sacrifice action is charged once even when it ends the match")

## All 28 synergy definitions keep their stable block as twenty newer adventurers append; art mappings and cost text stay reviewable.
func test_registration_and_text() -> void:
	fixture()
	var additions := SynergyCatalogue.all_units(1)
	check(additions.size() == 28 and CardCatalogue.starter_army().size() == 172, "The 28 synergy cards remain in the expanded 86-card roster per owner")
	for unit in additions:
		check(BoardCharacter.supports(unit) and FileAccess.file_exists(BoardCharacter.portrait_path(unit)), unit.name + " uses imported PixelLab art")
		for line in EffectText.unit_lines(unit): check(not line.contains("Unrecognized"), unit.name + " has a supported rule description")
	var naturalist := SynergyCatalogue.grey_squirrel_naturalist(1)
	var archer := SynergyCatalogue.tamia_archer(1)
	check(EffectText.describe_effect(naturalist.effects[0], naturalist).contains("[lb]2S[rb]") \
		and EffectText.describe_effect(archer.effects[0], archer).contains("[lb]S[rb]"), "Cost text distinguishes [2S] and [S] from action spending")
