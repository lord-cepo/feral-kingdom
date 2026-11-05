## Focused behavior regressions for the eight Wild rodents; execute this scene only on an explicit TEST request.
extends Node

var checks := 0
var failures := 0
var events: Array[EffectEvent] = []

## Headless test-scene entry point exercises production verbs, cost choices, captured events and source-owned continuous state.
func _ready() -> void:
	Match.action_event.connect(func(event: EffectEvent) -> void: events.append(event))
	test_marmot()
	test_jerboa()
	test_dormouse()
	test_chinchilla()
	test_lemming()
	test_porcupine_harvest()
	test_porcupine_stun()
	test_numeric_cancellation_and_revalidation()
	test_independent_amount_bindings()
	test_paid_amount_survives_followups()
	test_hedgehog()
	test_flying_squirrel()
	test_roster_and_art()
	test_name_groups_and_wording()
	test_legacy_name_copy_migration()
	print("Wild Return units: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)

## Reports semantic failures while allowing independent card scenarios to complete.
func check(value: bool, message: String) -> void:
	checks += 1
	if value: return
	failures += 1
	push_error(message)

## Starts an isolated stable-ID board with headless acknowledgement/animation gates disabled and ample local resources.
func fixture() -> void:
	Match.reset_combat()
	Match.rules_runner.trigger_acknowledgements_enabled = false
	Match.rules_runner.presentation_busy_query = Callable()
	Match.army.clear()
	Match.map.clear()
	events.clear()
	for index in 6: Match.map.append(HexInfo.new(index, Vector2i(index, 0), Enum.region.STARTING, Enum.side.P1, 0))
	for player in Match.players.values():
		player.actions_remaining = 10
		player.action_allowance = 10
		player.deployments_remaining = 3
		player.has_deployed = true
		player.next_turn_actions = 0

## Adds a printed card with stable identity and implicit movement; a negative position means hand without deployment or event side effects.
func add(unit: UnitInfo, hex_id: int) -> UnitInfo:
	unit.iun = Match.army.size()
	unit.ihx = hex_id
	unit.t_state = Enum.t_state.DEPLOYED if hex_id >= 0 else Enum.t_state.UNDEPLOYED
	unit.active = hex_id >= 0
	unit.ensure_implicit_walk()
	unit.capture_printed_state()
	Match.army.append(unit)
	return unit

## Supplies a non-triggering body so tests isolate ownership, zone and identity restrictions from other catalogue engines.
func plain(owner: int, hex_id: int) -> UnitInfo:
	var unit := UnitInfo.new()
	unit.player = owner
	unit.name = "Test body"
	unit.uuid = "test-%d" % Match.army.size()
	unit.max_life = 5
	unit.actual_life = 5
	return add(unit, hex_id)

## Resolves counters by their production host/key identity rather than mutable property-array order.
func counter(unit: UnitInfo, key: StringName) -> Prop:
	return Match.get_property(TargetRef.property(TargetRef.unit(unit.iun), key))

## Submits one retained target identity through the production picker; missing choices fail the assertion without null access.
func choose(ref: TargetRef) -> bool:
	var run := Match.rules_runner.active
	return run != null and run.current != null and run.current.choose(ref)

## Submits a number through the execution's bounded amount stage rather than directly mutating any counter or reusable definition.
func amount(value: int) -> bool:
	var run := Match.rules_runner.active
	return run != null and run.current != null and run.current.choose_amount(value)

## Marmot pays normal action/activity, returns another nearby friend and preserves upgrades/counters; self, enemies and distant friends are absent.
func test_marmot() -> void:
	fixture()
	var marmot := add(CardCatalogue.wild_marmot(1), 0)
	var friend := plain(1, 1)
	var enemy := plain(2, 2)
	var distant := plain(1, 4)
	counter(friend, &"physical").value = 3
	check(Match.rules_runner.submit(marmot.effects[1], TargetRef.unit(marmot.iun)), "Marmot submits Return")
	check(choose(TargetRef.unit(marmot.iun)), "Marmot pays one activity")
	check(not choose(TargetRef.unit(marmot.iun)) and not choose(TargetRef.unit(enemy.iun)) and not choose(TargetRef.unit(distant.iun)), "Marmot excludes self/enemy/distant identities")
	check(choose(TargetRef.unit(friend.iun)), "Marmot selects adjacent friend")
	check(friend.t_state == Enum.t_state.UNDEPLOYED and counter(friend, &"physical").value == 3, "Marmot Return preserves target counters")
	check(counter(marmot, &"stun").value == 1 and Match.players[1].actions_remaining == 9, "Marmot pays exactly one Stun/action")

## Jerboa's defensive declaration returns only the enemy attacker, cancels Bash and emits no Flee; outgoing Bash never qualifies.
func test_jerboa() -> void:
	fixture()
	var jerboa := add(CardCatalogue.wild_jerboa(1), 1)
	var enemy := plain(2, 0)
	Match.active_player = 2
	check(CombatResolver.move_unit(TargetRef.unit(enemy.iun), TargetRef.hex(1), 1, false, true), "Enemy enters Jerboa's hex")
	check(enemy.t_state == Enum.t_state.UNDEPLOYED and jerboa.ihx == 1 and Match.bashes.is_empty(), "Jerboa Returns exact attacker and cancels Bash")
	check(counter(jerboa, &"stun").value == 0 and not events.any(func(event: EffectEvent) -> bool: return event.action == &"flee"), "Defensive Return is free and not Flee")
	fixture()
	jerboa = add(CardCatalogue.wild_jerboa(1), 0)
	enemy = plain(2, 1)
	CombatResolver.move_unit(TargetRef.unit(jerboa.iun), TargetRef.hex(1), 1, false, true)
	check(enemy.t_state == Enum.t_state.DEPLOYED and jerboa.t_state == Enum.t_state.DEPLOYED, "Jerboa's own outgoing Bash does not Return its defender")

## Dormouse captures only its own Deploy and selects exactly distance-one units of either owner; no self/same-hex/distant choice is offered.
func test_dormouse() -> void:
	for owner in [1, 2]:
		fixture()
		var mouse := add(CardCatalogue.wild_dormouse(1), 1)
		var neighbor := plain(owner, 2)
		var same_hex := plain(2, 1)
		var distant := plain(1, 4)
		Match.action_event.emit(EffectEvent.new(&"deploy", TargetRef.unit(distant.iun), TargetRef.hex(4)))
		check(not Match.rules_runner.busy(), "Other unit's Deploy does not trigger Dormouse")
		Match.action_event.emit(EffectEvent.new(&"deploy", TargetRef.unit(mouse.iun), TargetRef.hex(1)))
		check(not choose(TargetRef.unit(mouse.iun)) and not choose(TargetRef.unit(same_hex.iun)) and not choose(TargetRef.unit(distant.iun)), "Dormouse exact adjacency excludes distance zero and distant targets")
		check(choose(TargetRef.unit(neighbor.iun)) and neighbor.t_state == Enum.t_state.UNDEPLOYED, "Dormouse Returns either-owner adjacent unit")
		check(counter(mouse, &"stun").value == 0, "Dormouse Deploy trigger adds no activity payment")

## Chinchilla's death replacement bypasses format/region/control costs, emits Deploy again and preserves the returned ally's state.
## Wild Rat's duplicate cannot perform another replacement once the source has recovered; Disable is not an own-death trigger.
func test_chinchilla() -> void:
	fixture()
	var chinchilla := add(CardCatalogue.wild_chinchilla(1), 0)
	var friend := plain(1, 4)
	var enemy := plain(2, 5)
	add(CardCatalogue.wild_rat(1), 1)
	Match.map[4].region = Enum.region.FRONT
	Match.map[4].side = Enum.side.P2
	counter(friend, &"magical").value = 3
	var actions := Match.players[1].actions_remaining
	var deployments := Match.players[1].deployments_remaining
	Match.defeat(TargetRef.unit(chinchilla.iun), 2)
	check(not choose(TargetRef.unit(enemy.iun)), "Chinchilla cannot replace an enemy")
	check(choose(TargetRef.unit(friend.iun)), "Chinchilla chooses one deployed friend after death")
	check(chinchilla.t_state == Enum.t_state.DEPLOYED and chinchilla.ihx == 4 and chinchilla.actual_life == chinchilla.max_life, "Chinchilla recovers at full health on former friendly hex despite Front/enemy side")
	check(not chinchilla.active and counter(chinchilla, &"stun").value == 1, "Effect deployment enters inactive with normal Stun")
	check(friend.t_state == Enum.t_state.UNDEPLOYED and counter(friend, &"magical").value == 3, "Replacement Returns friend without Reset")
	check(Match.players[1].actions_remaining == actions and Match.players[1].deployments_remaining == deployments + 1, "Special deployment spends no resources and its Deploy grants one deployment")
	check(events.filter(func(event: EffectEvent) -> bool: return event.action == &"return_to_hand").size() == 1, "Doubled own-death rule cannot Return another card after recovery")
	fixture()
	chinchilla = add(CardCatalogue.wild_chinchilla(1), -1)
	friend = plain(1, 1)
	Action.disable(TargetRef.unit(friend.iun), TargetRef.unit(chinchilla.iun))
	check(chinchilla.t_state == Enum.t_state.DEFEATED and friend.t_state == Enum.t_state.DEPLOYED and not Match.rules_runner.busy(), "Disable does not trigger Chinchilla death replacement")

## Lemming's actual legal opposite-side deployment retains its ordinary Stun plus three ETB counters, and other Deploys never add more.
func test_lemming() -> void:
	fixture()
	var anchor := plain(1, 0)
	anchor.type = Enum.type.HERO
	Match.map[0].region = Enum.region.INTERMEDIATE
	Match.map[0].side = Enum.side.P2
	Match.map[1].region = Enum.region.INTERMEDIATE
	Match.map[1].side = Enum.side.P2
	var lemming := add(CardCatalogue.wild_lemming(1), -1)
	check(Match.deploy(lemming.iun, 1), "Lemming deploys in controlled opposing Intermediate")
	check(counter(lemming, &"stun").value == 4 and not lemming.active, "Lemming has four total deployment Stun")
	Match.action_event.emit(EffectEvent.new(&"deploy", TargetRef.unit(anchor.iun), TargetRef.hex(0)))
	check(counter(lemming, &"stun").value == 4, "Another card's Deploy does not add Stun to Lemming")
	fixture()
	lemming = add(CardCatalogue.wild_lemming(1), 0)
	var enemy := plain(2, 5)
	var friend := plain(1, 1)
	enemy.actual_life = 1
	check(Match.rules_runner.submit(lemming.effects[0], TargetRef.unit(lemming.iun)) and choose(TargetRef.unit(lemming.iun)), "Recovered Lemming pays normal activity for Instant Fire")
	check(not choose(TargetRef.hex(friend.ihx)) and not choose(TargetRef.hex(3)), "Lemming Fire targets enemy units rather than friendly or empty hexes")
	check(choose(TargetRef.hex(enemy.ihx)) and enemy.t_state == Enum.t_state.DEFEATED and Match.pending_attacks.is_empty(), "Lemming's unlimited Fire 1 resolves instantly against a distant enemy")

## Porcupine's first AC picks unit→kind→X before atomic activity/removal; flags, negative/empty counters and enemies cannot be chosen.
func test_porcupine_harvest() -> void:
	fixture()
	var porcupine := add(CardCatalogue.wild_porcupine(1), 0)
	var friend := add(CardCatalogue.wild_hedgehog(1), 5)
	var enemy := plain(2, 1)
	var reserve := plain(1, -1)
	counter(reserve, &"stun").value = 5
	counter(friend, &"temp_physical").value = 4
	counter(friend, &"magical").value = -2
	counter(enemy, &"physical").value = 5
	check(Match.rules_runner.command_available(porcupine.effects[1], TargetRef.unit(porcupine.iun)), "Dependent harvest is available through normal read-only query")
	check(Match.rules_runner.submit(porcupine.effects[1], TargetRef.unit(porcupine.iun)), "Porcupine submits harvest")
	check(not choose(TargetRef.unit(enemy.iun)) and not choose(TargetRef.unit(reserve.iun)) and choose(TargetRef.unit(friend.iun)), "Harvest chooses any-distance deployed friend, excluding enemy and hand")
	check(not choose(TargetRef.property(TargetRef.unit(friend.iun), &"magical")) and not choose(TargetRef.property(TargetRef.unit(friend.iun), &"wild")), "Harvest excludes negative counters and flags")
	check(choose(TargetRef.property(TargetRef.unit(friend.iun), &"temp_physical")), "Harvest selects exact counter kind")
	check(not amount(0) and not amount(5) and counter(friend, &"temp_physical").value == 4, "Out-of-bounds X never pays")
	check(amount(3) and counter(friend, &"temp_physical").value == 4, "Confirming X alone does not mutate before activity choice")
	check(choose(TargetRef.unit(porcupine.iun)), "Final activity choice commits complete harvest cost")
	check(counter(friend, &"temp_physical").value == 1 and counter(porcupine, &"Soul").value == 3 and counter(porcupine, &"stun").value == 1, "Harvest removes X, grants X Soul and pays one self-Stun")
	check(Match.players[1].actions_remaining == 9, "Whole harvest spends one action rather than one per picker step")

## Soul-to-Stun binds the confirmed positive payment, retains all unrelated enemy counters, and requires a hostile deployed recipient.
func test_porcupine_stun() -> void:
	fixture()
	var porcupine := add(CardCatalogue.wild_porcupine(1), 0)
	var enemy := plain(2, 5)
	var friend := plain(1, 1)
	counter(porcupine, &"Soul").value = 4
	counter(enemy, &"temp_magical").value = 2
	var controller := preload("res://scripts/ui/local_match_controller.gd").new()
	check(controller._stun_target_error(porcupine.effects[2], porcupine.iun).is_empty(), "HUD Stun preflight binds unpaid X without blocking the valid command")
	controller.free()
	check(Match.rules_runner.command_available(porcupine.effects[2], TargetRef.unit(porcupine.iun)), "Variable Soul-to-Stun is available before X has been selected")
	check(Match.rules_runner.submit(porcupine.effects[2], TargetRef.unit(porcupine.iun)), "Porcupine submits Soul-to-Stun")
	check(choose(TargetRef.property(TargetRef.unit(porcupine.iun), &"Soul")) and amount(3), "Soul payment asks positive X")
	check(choose(TargetRef.unit(porcupine.iun)), "Soul-to-Stun collects standard activity")
	check(not choose(TargetRef.unit(friend.iun)) and choose(TargetRef.unit(enemy.iun)), "Soul-to-Stun chooses enemy rather than friendly unit")
	check(counter(porcupine, &"Soul").value == 1 and counter(enemy, &"stun").value == 3 and not enemy.active, "Soul-to-Stun uses paid X exactly")
	check(counter(enemy, &"temp_magical").value == 2, "Variable Stun preserves target protection")

## Cancelling a numeric picker and changing resources before commit never partially pays; shared definitions do not remember a previous X.
func test_numeric_cancellation_and_revalidation() -> void:
	fixture()
	var porcupine := add(CardCatalogue.wild_porcupine(1), 0)
	var friend := plain(1, 1)
	counter(friend, &"stun").value = 3
	var effect := porcupine.effects[1]
	Match.rules_runner.submit(effect, TargetRef.unit(porcupine.iun))
	choose(TargetRef.unit(friend.iun))
	choose(TargetRef.property(TargetRef.unit(friend.iun), &"stun"))
	Match.rules_runner.active.cancel()
	check(porcupine.active and counter(friend, &"stun").value == 3 and Match.players[1].actions_remaining == 10, "Cancelling AMOUNT retains every resource")
	Match.rules_runner.submit(effect, TargetRef.unit(porcupine.iun))
	choose(TargetRef.unit(friend.iun))
	choose(TargetRef.property(TargetRef.unit(friend.iun), &"stun"))
	amount(3)
	counter(friend, &"stun").value = 1
	var execution := Match.rules_runner.active
	choose(TargetRef.unit(porcupine.iun))
	check(execution.status == EffectExecution.Status.FAILED, "Cumulative preflight rejects a now-unaffordable chosen X")
	check(porcupine.active and counter(porcupine, &"Soul").value == 0 and counter(friend, &"stun").value == 1, "Failed preflight makes no partial mutation")
	check(effect.cost.phrases[1].verb.user_params[0] is RuleNumber, "Definition retains symbolic X rather than a selected amount")

## Two direct activations share one definition while paused at different numeric choices; each keeps its own host, X and paid results.
func test_independent_amount_bindings() -> void:
	fixture()
	var first := add(CardCatalogue.wild_porcupine(1), 0)
	var second := add(CardCatalogue.wild_porcupine(1), 3)
	var friend_a := plain(1, 1)
	var friend_b := plain(1, 4)
	counter(friend_a, &"stun").value = 4
	counter(friend_b, &"temp_magical").value = 5
	var shared := first.effects[1]
	var run_a := shared.eval(TargetRef.unit(first.iun))
	check(run_a.current.choose(TargetRef.unit(friend_a.iun)), "First shared activation chooses its own host")
	check(run_a.current.choose(TargetRef.property(TargetRef.unit(friend_a.iun), &"stun")), "First activation retains its counter identity")
	var run_b := shared.eval(TargetRef.unit(second.iun))
	check(run_b.current.choose(TargetRef.unit(friend_b.iun)), "Overlapping activation independently chooses another host")
	check(run_b.current.choose(TargetRef.property(TargetRef.unit(friend_b.iun), &"temp_magical")), "Second activation retains a different counter kind")
	check(run_b.current.choose_amount(3) and run_b.current.choose(TargetRef.unit(second.iun)), "Second activation pays X=3 first")
	check(run_a.current.choose_amount(2) and run_a.current.choose(TargetRef.unit(first.iun)), "Paused first activation still pays its own X=2")
	check(counter(first, &"Soul").value == 2 and counter(second, &"Soul").value == 3, "Shared definition grants independent paid amounts to each source")
	check(counter(friend_a, &"stun").value == 2 and counter(friend_b, &"temp_magical").value == 2, "Independent hosts lose exactly their chosen amounts")

## A cost-triggered Soul grant resolves before harvest's consequence, but cannot replace the execution's captured amount paid.
func test_paid_amount_survives_followups() -> void:
	fixture()
	var porcupine := add(CardCatalogue.wild_porcupine(1), 0)
	var friend := plain(1, 1)
	counter(friend, &"stun").value = 4
	var property := TargetRef.property(TargetRef.unit(friend.iun), &"stun")
	var removal := Effect.EventPhrase.observe(&"decrement", Selectors.Self.new(),
		Selectors.Literal.new(TargetRef.Kind.PROPERTY, [property]), TargetRef.Kind.UNIT, TargetRef.Kind.PROPERTY)
	porcupine.trigger_effects.append(Effect.on_event(removal, Effect.ConsequencePhrase.new(Selectors.Self.new(),
		Verbs.change_counter(5), Selectors.PropertyOf.new(Selectors.Self.new(), &"Soul"), Effect.Phrase.TargetMode.ALL)))
	Match.rules_runner.submit(porcupine.effects[1], TargetRef.unit(porcupine.iun))
	choose(TargetRef.unit(friend.iun))
	choose(property)
	amount(2)
	choose(TargetRef.unit(porcupine.iun))
	check(counter(porcupine, &"Soul").value == 7 and counter(friend, &"stun").value == 2, "Cost followup grants five Soul, then captured X grants exactly two more")

## Received Hit, including zero damage, grants +1/+1; outgoing contact, bare Fire records and cancelled contact do not qualify.
func test_hedgehog() -> void:
	fixture()
	var hedgehog := add(CardCatalogue.wild_hedgehog(1), 0)
	var enemy := plain(2, 1)
	var source := TargetRef.unit(enemy.iun)
	var target := TargetRef.unit(hedgehog.iun)
	Match.action_event.emit(EffectEvent.new(&"hit", source, target, {"damage": 0}))
	check(counter(hedgehog, &"physical").value == 1 and counter(hedgehog, &"magical").value == 1, "Received zero-damage physical Hit grants persistent +1/+1")
	Match.action_event.emit(EffectEvent.new(&"hit", target, source, {"damage": 1}))
	Match.action_event.emit(EffectEvent.new(&"fire", source, TargetRef.hex(0)))
	Match.action_event.emit(EffectEvent.new(&"hit", source, target, {"cancelled": true}))
	check(counter(hedgehog, &"physical").value == 1 and counter(hedgehog, &"magical").value == 1, "Outgoing, bare Fire and cancelled events do not trigger received Hit")
	Match.action_event.emit(EffectEvent.new(&"hit", source, target, {"kind": &"fire", "damage": 0, "wounded": false}))
	check(counter(hedgehog, &"physical").value == 2 and counter(hedgehog, &"magical").value == 2, "Actual magical contact now also triggers received Hit under the approved shared contact ruling")

## Flying Squirrel pays two (not three) self-Stun plus one action and derives +3/+0 only during a real unresolved Bash.
func test_flying_squirrel() -> void:
	fixture()
	var squirrel := add(CardCatalogue.wild_flying_squirrel(1), 0)
	var enemy := plain(2, 3)
	var context := RuleContext.new(TargetRef.unit(squirrel.iun))
	check(squirrel.state_effects[0].evaluate(context) == Vector2i.ZERO, "Squirrel has no Bash contribution outside Bash")
	check(Match.rules_runner.submit(squirrel.effects[0], TargetRef.unit(squirrel.iun)), "Squirrel submits explicit Fly cost")
	check(choose(TargetRef.unit(squirrel.iun)) and choose(TargetRef.hex(3)), "Squirrel pays replacement cost then Flies three")
	check(counter(squirrel, &"stun").value == 2 and Match.players[1].actions_remaining == 9, "Fly replaces ordinary Stun with exactly two and spends one action")
	check(squirrel.state_effects[0].evaluate(context) == Vector2i(3, 0), "Real Bash derives +3 physical and no magical bonus")
	Action.return_to_hand(TargetRef.unit(enemy.iun), TargetRef.unit(enemy.iun))
	check(squirrel.state_effects[0].evaluate(context) == Vector2i.ZERO, "Departed Bash immediately removes derived +3")
	check(not Match.rules_runner.command_available(squirrel.effects[0], TargetRef.unit(squirrel.iun)), "Inactive squirrel cannot pay another Fly cost")

## Every new factory supplies its requested life/region/Wild trait and imported character frames; appending preserves prior roster IDs.
func test_roster_and_art() -> void:
	var factories := [&"wild_marmot", &"wild_jerboa", &"wild_dormouse", &"wild_chinchilla", &"wild_lemming", &"wild_porcupine", &"wild_hedgehog", &"wild_flying_squirrel"]
	var health := [2, 1, 2, 1, 2, 3, 2, 1]
	var regions := [[Enum.region.STARTING], [Enum.region.INTERMEDIATE], [Enum.region.FRONT],
		[Enum.region.STARTING, Enum.region.INTERMEDIATE], [Enum.region.INTERMEDIATE],
		[Enum.region.STARTING, Enum.region.INTERMEDIATE], [Enum.region.INTERMEDIATE], [Enum.region.STARTING]]
	var catalogue := CardCatalogue.new()
	var roster := CardCatalogue.starter_army()
	for index in factories.size():
		var unit: UnitInfo = catalogue.call(factories[index], 1)
		check(unit.actual_life == health[index] and unit.name.to_lower().contains("wild") and not unit.has_flag(&"wild"), "%s has printed life and name-derived Wild membership" % unit.name)
		check(unit.deploy_regions == regions[index] and unit.deployment_enemy_side == (factories[index] == &"wild_lemming"), "%s has the requested deployment regions and side" % unit.name)
		check(BoardCharacter.supports(unit) and ResourceLoader.exists(BoardCharacter.portrait_path(unit)), "%s has mapped PixelLab portrait" % unit.name)
		check(roster.any(func(candidate: UnitInfo) -> bool: return candidate.uuid == unit.uuid), "%s is available in starter roster" % unit.name)

## Name groups follow case-insensitive live names, not flags/copies; printed modifier/grant text uses neutral/purple and applied M/N uses magenta.
func test_name_groups_and_wording() -> void:
	fixture()
	var unit := plain(1, 0)
	unit.name = "Scout of the WiLd Squirrel"
	var query := QuerySelector.new()
	query.name_contains = "wild"
	var context := RuleContext.new(TargetRef.unit(unit.iun))
	check(query.matches(context.source, context), "Wild matches inside mixed-case names rather than only a prefix")
	query.name_contains = "squirrel"
	check(query.matches(context.source, context), "Species groups use the same name query")
	unit.name = "Mouse Scout"
	check(not query.matches(context.source, context), "Renamed unit leaves squirrel group immediately")
	query.name_contains = "mouse"
	check(query.matches(context.source, context), "Renamed unit joins mouse group without properties")
	var tag := Prop.new()
	tag.name = &"wild"
	tag.increment = Enum.p_increment.FLAG
	tag.value = 1
	unit.props.append(tag)
	query.name_contains = "wild"
	check(not query.matches(context.source, context), "A legacy/copyable Wild flag cannot grant Wild name membership")
	check(not "\n".join(EffectText.unit_lines(unit)).contains("Wild."), "Legacy Wild flags do not print as effects")
	check(EffectText._modifiers(1, 2) == "+1/[color=#c084fc]+2[/color]", "Printed physical/magic pair uses normal/purple colors")
	check(not EffectText._action_grant(&"bow", [1, 1]).contains("#ef70df"), "Printed upgrade grant has no applied-value magenta")
	check(EffectText.action_value(2, 1).contains("#ef70df") and not EffectText.action_value(1, 1).contains("#ef70df"), "Only actual changed action values receive magenta")
	check(EffectText._condition(Condition.Bashing.new(), "this unit", unit).contains("is [img"), "Bashing condition uses the Bash icon")
	check(not EffectText._query(WoodlandRules.friends(), unit).contains("deployed"), "Friendly target wording omits implicit deployed scope")
	check(RuleGuide.decorate("friendly unit").contains("guide:friendly") and RuleGuide.description("friendly").contains("deployed"), "Friendly hover restores the precise zone explanation")
	check(EffectText._anchor(Selectors.Anchor.EVENT_SUBJECT) == "it" and EffectText._anchor(Selectors.Anchor.EVENT_TARGET) == "target", "Short pronouns preserve event subject/object identity")
	check(not EffectText._condition(Condition.BashingEnemy.new(), "this unit", unit).contains("enemy"), "Bash condition omits the implicit enemy qualifier")
	check(EffectText.describe_effect(WoodlandRules.bomb_and_flee(), unit).contains("Flee") and not EffectText.describe_effect(WoodlandRules.bomb_and_flee(), unit).contains("using this unit"), "Flee rules text leaves movement explanation in the glossary")
	check(EffectText.describe_effect(WoodlandRules.grow_with_friends(), unit).contains("at least one is positive"), "Explorer's compact life event preserves positivity qualification")
	var snapshot := preload("res://scripts/runtime/match_snapshot.gd")
	check(snapshot._restore_props([{"name": "wild", "increment": int(Enum.p_increment.FLAG), "value": 1, "target": int(Enum.p_target.UNIT)}]).is_empty(), "Old saved Wild flags are discarded")

## Version-two snapshots can contain a copied Wild flag at the old printed slot now occupied by Soul; migrate it without granting/copying Soul.
func test_legacy_name_copy_migration() -> void:
	fixture()
	var porcupine := add(CardCatalogue.wild_porcupine(1), 0)
	var other := plain(1, 1)
	counter(porcupine, &"Soul").value = 3
	var snapshot := preload("res://scripts/runtime/match_snapshot.gd")
	var saved: Dictionary = snapshot._capture_state()
	saved.version = 2
	saved.units[0].props.append({"name": "wild", "increment": int(Enum.p_increment.FLAG), "value": 1, "target": int(Enum.p_target.UNIT)})
	saved.units[1].copied_effects = [{"unit": 0, "category": "props", "index": 5}]
	check(snapshot._is_compatible_snapshot(saved), "Old Wild flag copies do not invalidate the saved match")
	snapshot._apply_state(saved)
	check(not porcupine.has_flag(&"wild") and counter(porcupine, &"Soul").value == 3 and other.copied_effects.is_empty(), "Legacy name flags/copies disappear while real resources survive")
