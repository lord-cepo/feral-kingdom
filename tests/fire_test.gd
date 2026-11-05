extends Node

var checks := 0
var failures := 0
var events: Array[EffectEvent] = []
var phases: Array = []

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func fixture() -> void:
	Match.reset_combat()
	Match.army.clear()
	Match.map.clear()
	events.clear()
	phases.clear()
	for coordinate in [Vector2i.ZERO, Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0)]:
		Match.map.append(HexInfo.new(Match.map.size(), coordinate, Enum.region.FRONT, Enum.side.NONE, 0))
	add_unit(1, 0, 5)
	add_unit(2, 1, 3)

func add_unit(player: int, tile: int, life: int) -> UnitInfo:
	var unit := UnitInfo.new()
	unit.iun = Match.army.size()
	unit.ihx = tile
	unit.player = player
	unit.max_life = life
	unit.actual_life = life
	unit.t_state = Enum.t_state.DEPLOYED
	Match.army.append(unit)
	return unit

func set_counter(id: int, key: StringName, value: int) -> void:
	Match.get_property(TargetRef.property(TargetRef.unit(id), key)).value = value

## Adds one named flag to a unit for combat-passive scenarios.
## Bash integration cases call this for Fast, First Strike, and other passive rules.
func set_flag(id: int, key: StringName) -> void:
	var flag := Prop.new()
	flag.name = key
	flag.increment = Enum.p_increment.FLAG
	flag.value = 1
	Match.get_unit(id).props.append(flag)

func fire(amount: int, instant: bool = false, pierce: bool = false, tile: int = 1) -> PhraseSelection:
	var run := PhraseSelection.new()
	var phrase := Effect.ConsequencePhrase.new(Selectors.Self.new(), Verbs.fire(amount, instant, pierce), DistanceSelector.within(3))
	run.begin_standalone(phrase, TargetRef.unit(0))
	check(run.choose(TargetRef.hex(tile)), "Fire declaration succeeds")
	return run

func defender_response() -> void:
	check(Match.complete_action(1), "Attacking turn completes")
	check(Match.complete_action(2), "Defender response completes")

func _ready() -> void:
	Match.action_event.connect(func(event: EffectEvent) -> void: events.append(event))
	Match.phase_changed.connect(func(phase: int, player: int) -> void: phases.append([phase, player]))
	test_modifiers()
	test_delayed_fire()
	test_shields()
	test_dodges()
	test_instant_and_immunity()
	test_bow_and_cannon()
	test_bombs()
	test_gore_displacement_and_bash()
	test_events_and_victory()
	test_phase_guards()
	print("Fire integration: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)

func test_modifiers() -> void:
	fixture()
	var unit := Match.army[1]
	check(unit.props.size() == 5 and unit.counter_modifiers() == Vector2i.ZERO, "Each unit starts with four modifier counters and one Stun counter")
	set_counter(1, &"physical", 2)
	set_counter(1, &"magical", -1)
	set_counter(1, &"temp_physical", 3)
	set_counter(1, &"temp_magical", 2)
	check(unit.modifier == Vector2i(5, 1), "Permanent and temporary counters sum independently")
	var hero := add_unit(2, 2, 4)
	hero.type = Enum.type.HERO
	unit.state_effects.append(StateModifier.adjacent_to_hero(1, 2))
	check(unit.physical_modifier == 7 and unit.magical_modifier == 3, "Control and live state contributions are added to counters")
	check(unit.physical_modifier == 7 and unit.counter_modifiers() == Vector2i(5, 1), "Repeated queries never accumulate derived bonuses into counters")
	var second_hero := add_unit(1, 0, 4)
	second_hero.type = Enum.type.HERO
	check(unit.physical_modifier == 6, "Two adjacent heroes satisfy one condition, not two bonuses")
	hero.ihx = 3
	second_hero.t_state = Enum.t_state.DEFEATED
	check(unit.modifier == Vector2i(6, 1), "State bonus disappears while the live control bonus remains")
	var change := PhraseSelection.new()
	change.begin_standalone(Effect.ConsequencePhrase.new(Selectors.Self.new(), Verbs.change_counter(-3),
		Selectors.PropertyOf.new(Selectors.Self.new(), &"magical")), TargetRef.unit(1))
	check(change.choose(TargetRef.property(TargetRef.unit(1), &"magical")), "An effect can change a modifier counter")
	check(unit.magical_modifier == -2, "Modifier counters support signed values")
	Match.map[1].control = Enum.control.P2
	check(ControlResolver.region_owner(Match.map[1]) == 2 and unit.physical_modifier == 6, "Controlled units retain the derived regional physical bonus")

func test_delayed_fire() -> void:
	fixture()
	fire(2)
	check(Match.pending_attacks.size() == 1 and Match.army[1].actual_life == 3, "Fire queues without life loss")
	var attack := Match.pending_attacks[0]
	check(Match.complete_action(1, 1) and Match.active_player == 1, "Remaining action tokens keep the action window open")
	check(not attack.resolved, "Extra attacking action does not resolve own Fire")
	check(Match.complete_action(1) and Match.active_player == 2, "Turn advances to defender")
	check(not attack.resolved, "Own combat phase cannot resolve own Fire")
	check(Match.complete_action(2, 1) and not attack.resolved, "Defender retains response time while actions remain")
	Match.complete_action(2)
	check(attack.resolved and attack.outcome.status == "survived", "Fire resolves in defender's combat window")
	check(Match.army[1].actual_life == 3, "Nonlethal Fire causes no partial damage")
	check(Match.pending_attacks.is_empty(), "Resolved attacks leave the queue")
	check(phases.has([Match.Phase.COMBAT_RESOLVE, 2]) and Match.phase == Match.Phase.ACTION, "Combat is followed by End, Start, and Action")
	fixture()
	fire(3)
	defender_response()
	check(Match.army[1].t_state == Enum.t_state.DEFEATED and Match.army[1].ihx == -1, "Lethal Fire defeats and removes the unit from its tile")
	check(TargetRef.unit(1).valid() and not TargetRef.unit(1).has_hex(), "Defeat preserves stable unit identity")

func test_shields() -> void:
	fixture()
	fire(4)
	set_counter(1, &"magical", 1)
	set_counter(1, &"temp_magical", 1)
	set_counter(1, &"physical", 20)
	set_counter(1, &"temp_physical", 10)
	defender_response()
	check(Match.army[1].actual_life == 3, "Modifier granted after declaration prevents lethal Fire")
	check(Match.army[1].magical_modifier == 1, "Only temporary magical protection is consumed")
	check(Match.army[1].physical_modifier == 30, "Fire neither uses nor consumes physical protection")
	fixture()
	set_counter(1, &"physical", 100)
	fire(3)
	defender_response()
	check(Match.army[1].actual_life == 0, "Physical modifier does not reduce Fire")
	fixture()
	var shielding := PhraseSelection.new()
	shielding.begin_standalone(Effect.ConsequencePhrase.new(Selectors.Self.new(), Verbs.mshield(2), Selectors.Self.new()), TargetRef.unit(1))
	check(shielding.choose(TargetRef.unit(1)) and Match.army[1].magical_modifier == 2, "Mshield writes temp_magical")
	fire(3)
	fire(3)
	defender_response()
	check(Match.army[1].t_state == Enum.t_state.DEFEATED, "First Fire spends temporary shield; second Fire can kill")
	fixture()
	var hero := add_unit(2, 2, 5)
	hero.type = Enum.type.HERO
	Match.army[1].state_effects.append(StateModifier.adjacent_to_hero(0, 1))
	fire(3)
	fire(3)
	defender_response()
	check(Match.army[1].actual_life == 3 and Match.army[1].magical_modifier == 1, "Continuous protection persists through multiple attacks")
	fixture()
	set_counter(1, &"magical", -1)
	fire(2)
	defender_response()
	check(Match.army[1].actual_life == 0, "Negative magical modifier increases lethal threshold")

func test_dodges() -> void:
	fixture()
	fire(9)
	var attack := Match.pending_attacks[0]
	Match.army[1].ihx = 2
	var replacement := add_unit(2, 1, 1)
	defender_response()
	check(Match.army[1].actual_life == 3 and replacement.actual_life == 1, "JS semantics: moving dodges Fire and a replacement is not hit")
	check(attack.outcome.status == "missed", "Dodged Fire records a miss")
	fixture()
	fire(9, false, false, 2)
	Match.army[1].ihx = 2
	defender_response()
	check(Match.army[1].actual_life == 0, "Originally empty target hex can catch an arriving enemy")
	fixture()
	add_unit(1, 1, 5)
	fire(3)
	Match.defeat(TargetRef.unit(0))
	defender_response()
	check(Match.army[1].actual_life == 0 and Match.army[2].actual_life == 5, "Fire survives source defeat and hits only opponent on shared hex")
	fixture()
	check(not Action.fire(TargetRef.unit(0), TargetRef.hex(0), 3), "Fire rejects a friendly-only occupied hex")
	check(not Action.fire(TargetRef.unit(0), TargetRef.hex(1), -1), "Negative Fire damage is rejected")

func test_instant_and_immunity() -> void:
	fixture()
	fire(3, true)
	check(Match.pending_attacks.is_empty() and Match.army[1].actual_life == 0, "Instant Fire uses the same resolver immediately")
	fixture()
	var immunity := Prop.new()
	immunity.name = "obsidian"
	immunity.increment = Enum.p_increment.FLAG
	immunity.value = 1
	Match.army[1].props.append(immunity)
	set_counter(1, &"temp_magical", 3)
	fire(9, true)
	check(Match.army[1].actual_life == 3 and Match.army[1].magical_modifier == 3, "Obsidian blocks contact without consuming magical shield")
	fire(3, true, true)
	check(Match.army[1].actual_life == 0 and Match.army[1].magical_modifier == 0, "Piercing Fire ignores Obsidian and modifier but consumes temp_magical")

## Exercises delayed/instant Bow and line Cannon, including captured targets and shield rules.
## _ready() runs this after the Fire-specific cases in the combat integration scene.
func test_bow_and_cannon() -> void:
	fixture()
	var bow_run := EffectExecution.new(Collection.bow_DR(2, 3), TargetRef.unit(0))
	bow_run.start()
	check(bow_run.current.choose(TargetRef.unit(0)), "Bow pays its ordinary activity cost")
	check(bow_run.current.choose(TargetRef.hex(1)) and Match.pending_bow_attacks.size() == 1,
		"Bow queues a physical attack after target selection")
	defender_response()
	check(Match.army[1].actual_life == 1 and Match.pending_bow_attacks.is_empty(),
		"Bow deals lasting physical life damage in the opposing combat window")

	fixture()
	set_counter(1, UnitInfo.PHYSICAL_COUNTER, 1)
	set_counter(1, UnitInfo.TEMP_PHYSICAL_COUNTER, 1)
	var shielded_bow := PhraseSelection.new()
	shielded_bow.begin_standalone(Effect.ConsequencePhrase.new(Selectors.Self.new(),
		Verbs.bow(3, 3), DistanceSelector.within(3)), TargetRef.unit(0))
	check(shielded_bow.choose(TargetRef.hex(1)), "Bow declaration accepts an opposing unit")
	defender_response()
	check(Match.army[1].actual_life == 2 and Match.army[1].physical_modifier == 1,
		"Bow subtracts physical modifiers and consumes only temporary physical protection")
	check(events.any(func(event: EffectEvent) -> bool: return event.action == &"hit")
		and events.any(func(event: EffectEvent) -> bool: return event.action == &"wound"),
		"Bow emits Hit on contact and Wound only for positive life loss")

	fixture()
	set_counter(1, UnitInfo.TEMP_PHYSICAL_COUNTER, 2)
	var titanium := Prop.new()
	titanium.name = &"titanium"
	titanium.increment = Enum.p_increment.FLAG
	titanium.value = 1
	Match.army[1].props.append(titanium)
	var blocked := PhraseSelection.new()
	blocked.begin_standalone(Effect.ConsequencePhrase.new(Selectors.Self.new(), Verbs.bow(9, 3),
		DistanceSelector.within(3)), TargetRef.unit(0))
	blocked.choose(TargetRef.hex(1))
	defender_response()
	check(Match.army[1].actual_life == 3 and Match.army[1].physical_modifier == 2,
		"Titanium prevents Bow contact and preserves temporary physical protection")
	fixture()
	var dodge := PhraseSelection.new()
	dodge.begin_standalone(Effect.ConsequencePhrase.new(Selectors.Self.new(), Verbs.bow(9, 3),
		DistanceSelector.within(3)), TargetRef.unit(0))
	dodge.choose(TargetRef.hex(1))
	Match.army[1].ihx = 2
	var replacement := add_unit(2, 1, 1)
	defender_response()
	check(Match.army[1].actual_life == 3 and replacement.actual_life == 1,
		"Bow follows captured victim identity and never hits a replacement")

	fixture()
	var cannon_run := EffectExecution.new(Collection.cannon_DR(3, 3), TargetRef.unit(0))
	cannon_run.start()
	check(cannon_run.current.choose(TargetRef.unit(0)), "Cannon pays its ordinary activity cost")
	check(cannon_run.current.choose(TargetRef.hex(3)) and Match.pending_cannon_attacks.size() == 3,
		"Cannon captures each playable hex along its selected straight line")
	set_counter(1, UnitInfo.MAGICAL_COUNTER, 1)
	set_counter(1, UnitInfo.TEMP_MAGICAL_COUNTER, 1)
	defender_response()
	check(Match.army[1].actual_life == 2 and Match.army[1].magical_modifier == 1,
		"Cannon deals ordinary magic life damage and consumes only temporary magic protection")
	check(Match.pending_cannon_attacks.is_empty(), "Resolved Cannon line records leave the queue")

	fixture()
	Match.map.append(HexInfo.new(Match.map.size(), Vector2i(1, 1), Enum.region.FRONT, Enum.side.NONE, 0))
	check(not CombatResolver.can_cannon(TargetRef.unit(0), TargetRef.hex(4), 2, 3),
		"Cannon rejects endpoints that are in range but not axially aligned")
	var friendly_in_line := add_unit(1, 2, 3)
	var cannon := PhraseSelection.new()
	cannon.begin_standalone(Effect.ConsequencePhrase.new(Selectors.Self.new(), Verbs.cannon(2, 3),
		DistanceSelector.within(3)), TargetRef.unit(0))
	check(cannon.choose(TargetRef.hex(3)), "Cannon accepts a legal aligned endpoint")
	defender_response()
	check(friendly_in_line.actual_life == 1,
		"Neutral Cannon lines damage friendly units as well as enemies")
	fixture()
	var obsidian := Prop.new()
	obsidian.name = &"obsidian"
	obsidian.increment = Enum.p_increment.FLAG
	obsidian.value = 1
	Match.army[1].props.append(obsidian)
	set_counter(1, UnitInfo.TEMP_MAGICAL_COUNTER, 2)
	var ordinary_cannon := PhraseSelection.new()
	ordinary_cannon.begin_standalone(Effect.ConsequencePhrase.new(Selectors.Self.new(),
		Verbs.cannon(9, 1, true), DistanceSelector.within(1)), TargetRef.unit(0))
	ordinary_cannon.choose(TargetRef.hex(1))
	check(Match.army[1].actual_life == 3 and Match.army[1].magical_modifier == 2,
		"Obsidian blocks Cannon contact and preserves temporary magic protection")
	var piercing_cannon := PhraseSelection.new()
	piercing_cannon.begin_standalone(Effect.ConsequencePhrase.new(Selectors.Self.new(),
		Verbs.cannon(2, 1, true, true), DistanceSelector.within(1)), TargetRef.unit(0))
	piercing_cannon.choose(TargetRef.hex(1))
	check(Match.army[1].actual_life == 1 and Match.army[1].magical_modifier == 0,
		"Piercing Cannon bypasses Obsidian/modifiers, deals damage, and consumes temp magic")

	fixture()
	var instant_bow := PhraseSelection.new()
	instant_bow.begin_standalone(Effect.ConsequencePhrase.new(Selectors.Self.new(),
		Verbs.bow(1, 3, true), DistanceSelector.within(3)), TargetRef.unit(0))
	check(instant_bow.choose(TargetRef.hex(1)) and Match.army[1].actual_life == 2
		and Match.pending_bow_attacks.is_empty(), "Instant Bow resolves immediately through the same resolver")

## Exercises inert Bomb placement, merge, Fire lighting, delayed chains, and defuse.
## _ready() runs it with the ranged attacks in the combat integration scene.
func test_bombs() -> void:
	fixture()
	check(CombatResolver.throw_bomb(TargetRef.unit(0), TargetRef.hex(1), 2, 1, false),
		"A legal Bomb throw places an inert bomb")
	check(CombatResolver.throw_bomb(TargetRef.unit(0), TargetRef.hex(1), 3, 1, true),
		"A second throw merges into the inert bomb")
	check(Match.bombs.size() == 1 and Match.bombs[0].damage == 5 and Match.bombs[0].pierce,
		"Bomb merges sum damage and preserve Pierce")
	var defuse := EffectExecution.new(Collection.defuse_bomb(1), TargetRef.unit(0))
	defuse.start()
	check(defuse.current.choose(TargetRef.unit(0)), "Defuse pays the normal activity cost")
	check(defuse.current.choose(TargetRef.hex(1)) and Match.bombs.is_empty(),
		"Defuse removes the bomb without exploding it")

	fixture()
	CombatResolver.throw_bomb(TargetRef.unit(0), TargetRef.hex(1), 2, 1, false)
	fire(9, false, false, 1)
	check(Match.bombs.is_empty() and Match.pending_attacks.is_empty()
		and not Match.pending_cannon_attacks.is_empty(), "Fire lights a bomb instead of queuing ordinary Fire")
	defender_response()
	check(Match.army[0].actual_life == 3 and Match.army[1].actual_life == 1,
		"Delayed bomb blast damages both players with magic damage")

	fixture()
	CombatResolver.throw_bomb(TargetRef.unit(0), TargetRef.hex(1), 2, 1, true)
	set_flag(1, &"obsidian")
	set_counter(1, UnitInfo.TEMP_MAGICAL_COUNTER, 2)
	fire(9, false, false, 1)
	defender_response()
	check(Match.army[1].actual_life == 3 and Match.army[1].magical_modifier == 2,
		"A Bomb's stored Pierce merges with the Bomb but the lighting attack controls blast Pierce")

	fixture()
	Match.map.append(HexInfo.new(Match.map.size(), Vector2i(1, -1), Enum.region.FRONT, Enum.side.NONE, 0))
	CombatResolver.throw_bomb(TargetRef.unit(0), TargetRef.hex(1), 1, 1, false)
	fire(9, false, false, 1)
	Match.army[1].ihx = 3
	var replacement := add_unit(2, 1, 3)
	defender_response()
	check(replacement.actual_life == 2 and Match.army[1].actual_life == 3,
		"A Bomb blast resolves against current occupants, including on an adjacent hex")

	fixture()
	CombatResolver.throw_bomb(TargetRef.unit(0), TargetRef.hex(1), 2, 1, false)
	CombatResolver.throw_bomb(TargetRef.unit(0), TargetRef.hex(2), 1, 2, false)
	fire(9, false, false, 1)
	defender_response()
	check(Match.bomb_at(2) == null and Match.pending_cannon_attacks.any(
		func(attack: CannonAttack) -> bool: return attack.owner == 2 and attack.explosion),
		"A chain-lit bomb is removed and its fresh blast waits for a later response window")
	var chained := Match.pending_cannon_attacks.filter(
		func(attack: CannonAttack) -> bool: return attack.owner == 2 and attack.explosion)
	defender_response()
	check(chained.any(func(attack: CannonAttack) -> bool: return attack.resolved),
		"A chain blast resolves only after the owner of the new chain had a response window")

## Covers Gore leap/hits, Push/Pull unit displacement, Bomb displacement, and Bash timing.
## _ready() runs this in the combat integration scene after ranged attacks and Bombs.
func test_gore_displacement_and_bash() -> void:
	fixture()
	var gore := PhraseSelection.new()
	gore.begin_standalone(Collection.gore_DR(2, 3).consequence, TargetRef.unit(0))
	check(gore.choose(TargetRef.hex(2)),
		"Gore accepts an aligned destination and leaps immediately")
	check(Match.army[0].ihx == 2 and Match.pending_gore_attacks.size() == 1,
		"Gore captures an enemy on its path for delayed physical damage")
	defender_response()
	check(Match.army[1].actual_life == 1 and Match.pending_gore_attacks.is_empty(),
		"Gore resolves physical damage in the opposing combat window")

	fixture()
	var canceled_gore := PhraseSelection.new()
	canceled_gore.begin_standalone(Collection.gore_DR(3, 2).consequence, TargetRef.unit(0))
	canceled_gore.choose(TargetRef.hex(2))
	Match.defeat(TargetRef.unit(0))
	defender_response()
	check(Match.army[1].actual_life == 3,
		"Defeating the Gore source cancels its queued path damage")

	fixture()
	var push := PhraseSelection.new()
	push.begin_standalone(Effect.ConsequencePhrase.new(Selectors.Self.new(), Verbs.push(1, 2),
		Selectors.UnitsOn.new(DistanceSelector.within(2))), TargetRef.unit(0))
	check(push.choose(TargetRef.unit(1))
		and Match.army[1].ihx == 2, "Push moves the selected enemy away along an axial line")

	fixture()
	Match.army[1].ihx = 3
	var pull := PhraseSelection.new()
	pull.begin_standalone(Effect.ConsequencePhrase.new(Selectors.Self.new(), Verbs.pull(2, 3),
		Selectors.UnitsOn.new(DistanceSelector.within(3))), TargetRef.unit(0))
	check(pull.choose(TargetRef.unit(1))
		and Match.army[1].ihx == 1, "Pull moves the selected enemy toward SELF")

	fixture()
	CombatResolver.throw_bomb(TargetRef.unit(0), TargetRef.hex(1), 2, 1, false)
	var bomb_push := PhraseSelection.new()
	bomb_push.begin_standalone(Effect.ConsequencePhrase.new(Selectors.Self.new(),
		Verbs.push_bomb(1, 1), DistanceSelector.within(1)), TargetRef.unit(0))
	check(bomb_push.choose(TargetRef.hex(1)) and Match.bomb_at(2) != null,
		"Push can displace an inert Bomb to a playable hex")
	CombatResolver.throw_bomb(TargetRef.unit(0), TargetRef.hex(2), 1, 2, true)
	check(Match.bombs.size() == 1 and Match.bombs[0].damage == 3 and Match.bombs[0].pierce,
		"Displaced Bombs merge their damage and Pierce")
	var bomb_pull := PhraseSelection.new()
	bomb_pull.begin_standalone(Effect.ConsequencePhrase.new(Selectors.Self.new(),
		Verbs.pull_bomb(1, 2), DistanceSelector.within(2)), TargetRef.unit(0))
	check(bomb_pull.choose(TargetRef.hex(2)) and Match.bomb_at(1) != null,
		"Pull can move the merged Bomb toward SELF")
	fixture()
	Match.army[1].type = Enum.type.TEMPLE
	check(not CombatResolver.can_displace(TargetRef.unit(0), TargetRef.unit(1), 1, 2, false),
		"Temples cannot be forcibly displaced")

	fixture()
	add_unit(1, 2, 5)
	var bash_push := PhraseSelection.new()
	bash_push.begin_standalone(Effect.ConsequencePhrase.new(Selectors.Self.new(), Verbs.push(1, 1),
		Selectors.UnitsOn.new(DistanceSelector.within(1))), TargetRef.unit(0))
	check(bash_push.choose(TargetRef.unit(1))
		and Match.bashes.size() == 1, "Pushing a unit into an enemy creates a pending Bash")
	defender_response()
	check(Match.army[1].t_state == Enum.t_state.DEFEATED and Match.army[2].ihx == 2
		and Match.bashes.is_empty(), "Bash resolves after the defender's response and leaves the stronger unit")

	fixture()
	add_unit(1, 2, 5)
	add_unit(2, 3, 3)
	var dodge_setup := PhraseSelection.new()
	dodge_setup.begin_standalone(Effect.ConsequencePhrase.new(Selectors.Self.new(), Verbs.push(1, 1),
		Selectors.UnitsOn.new(DistanceSelector.within(1))), TargetRef.unit(0))
	dodge_setup.choose(TargetRef.unit(1))
	Match.start_turn(2)
	var dodge := PhraseSelection.new()
	dodge.begin_standalone(Effect.ConsequencePhrase.new(Selectors.Self.new(), Verbs.push(1, 1),
		Selectors.UnitsOn.new(DistanceSelector.within(1))), TargetRef.unit(3))
	check(dodge.choose(TargetRef.unit(1)) and Match.army[1].ihx == 1,
		"The defending player can displace a Bash participant to dodge")
	Match.complete_action(2)
	check(Match.bashes.is_empty() and Match.army[1].actual_life == 3
		and Match.army[2].actual_life == 5, "A Bash dodge cancels combat damage")

	fixture()
	add_unit(1, 2, 3)
	var first_strike_push := PhraseSelection.new()
	first_strike_push.begin_standalone(Effect.ConsequencePhrase.new(Selectors.Self.new(), Verbs.push(1, 1),
		Selectors.UnitsOn.new(DistanceSelector.within(1))), TargetRef.unit(0))
	first_strike_push.choose(TargetRef.unit(1))
	set_flag(1, &"first-strike")
	defender_response()
	check(Match.army[1].actual_life == 1 and Match.army[2].actual_life == 1
		and Match.bashes.size() == 1, "First Strike applies damage before retaliation and can leave the Bash engaged")

	fixture()
	add_unit(1, 2, 3)
	set_flag(2, &"steady")
	set_counter(1, UnitInfo.PHYSICAL_COUNTER, 2)
	set_counter(2, UnitInfo.PHYSICAL_COUNTER, -1)
	var steady_push := PhraseSelection.new()
	steady_push.begin_standalone(Effect.ConsequencePhrase.new(Selectors.Self.new(), Verbs.push(1, 1),
		Selectors.UnitsOn.new(DistanceSelector.within(1))), TargetRef.unit(0))
	steady_push.choose(TargetRef.unit(1))
	defender_response()
	check(Match.army[1].t_state == Enum.t_state.DEFEATED
		and Match.army[2].t_state == Enum.t_state.DEFEATED,
		"Steady suppresses the opposing Bash modifier and permits a tie")

	fixture()
	add_unit(1, 2, 6)
	set_flag(1, &"titanium")
	set_counter(1, UnitInfo.TEMP_PHYSICAL_COUNTER, 2)
	set_counter(2, UnitInfo.TEMP_PHYSICAL_COUNTER, 1)
	var titanium_push := PhraseSelection.new()
	titanium_push.begin_standalone(Effect.ConsequencePhrase.new(Selectors.Self.new(), Verbs.push(1, 1),
		Selectors.UnitsOn.new(DistanceSelector.within(1))), TargetRef.unit(0))
	titanium_push.choose(TargetRef.unit(1))
	defender_response()
	check(Match.army[1].actual_life == 3 and Match.army[1].physical_modifier == 2
		and Match.army[2].physical_modifier == 1 and Match.bashes.size() == 1,
		"Titanium prevents received Bash damage, preserves its shield, and leaves a surviving Bash pending")

	fixture()
	set_flag(1, &"fast")
	var fast_gore := PhraseSelection.new()
	fast_gore.begin_standalone(Collection.gore_DR(1, 1).consequence, TargetRef.unit(0))
	fast_gore.choose(TargetRef.hex(1))
	check(Match.bashes.size() == 1 and Match.bashes[0].responding_player == 1,
		"Fast schedules a new Bash for its creator's current Combat window")
	Match.complete_action(1)
	check(Match.bashes.is_empty() and Match.army[1].t_state == Enum.t_state.DEFEATED,
		"Fast Bash resolves in its creator's Combat window")

func test_events_and_victory() -> void:
	fixture()
	fire(1)
	check(events.size() == 1 and events[0].action == &"fire" and events[0].stage == &"target", "Declaration announces target stage only")
	var attack := Match.pending_attacks[0]
	var pattern := Effect.EventPhrase.new(Selectors.Self.new(), Verbs.fire(1), DistanceSelector.within(3))
	var ctx := PhraseSelection.new()
	ctx.begin_standalone(Effect.ConsequencePhrase.new(Selectors.Self.new(), Verbs.fire(1), DistanceSelector.within(3)), TargetRef.unit(0))
	check(not pattern.matches(ctx, events[0]), "Ordinary Fire event patterns wait for resolution")
	defender_response()
	var resolved_fire := events.filter(func(event: EffectEvent) -> bool: return event.action == &"fire" and event.stage == &"resolved")
	check(not resolved_fire.is_empty() and pattern.matches(ctx, resolved_fire.back()), "Nonlethal contact emits Fire resolved")
	var event_count := events.size()
	CombatResolver.resolve_fire(attack)
	check(events.size() == event_count, "Repeated resolver call is a no-op")
	ctx.cancel()
	fixture()
	Match.army[1].type = Enum.type.HERO
	fire(3)
	defender_response()
	check(Match.winner == 1 and Match.phase == Match.Phase.COMBAT_RESOLVE, "Hero defeat ends the match at combat")
	check(events.any(func(event: EffectEvent) -> bool: return event.action == &"die" and event.data.last_hex == 1), "Death event retains last occupied hex")
	check(not Match.complete_action(1), "No further turn advance after victory")

func test_phase_guards() -> void:
	fixture()
	check(not Match.complete_action(2), "Wrong player cannot finish the current action")
	var callback := func(_phase: int, _player: int) -> void:
		check(not Match.complete_action(Match.active_player), "Phase transition rejects reentrant turn completion")
	Match.phase_changed.connect(callback)
	Match.complete_action(1)
	Match.phase_changed.disconnect(callback)
	check(Match.turn_number == 1 and Match.active_player == 2, "One completion advances one turn only")
