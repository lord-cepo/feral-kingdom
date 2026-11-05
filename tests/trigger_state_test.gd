extends Node

var checks := 0
var failures := 0

## Reports focused trigger/state assertions and exits so Godot can run this as an integration scene.
## CI/manual verification opens trigger_state_test.tscn after selection/fire/local-match scenes.
func _ready() -> void:
	test_continuous_cards()
	test_live_state_conditions()
	test_have_and_while_contributions()
	test_guerra_continuous_card_examples()
	test_ironhide_trigger()
	test_hushbringer_ruling()
	test_prism_engagement()
	print("Trigger/state integration: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)

## Builds a small stable-ID board and clears prior captured runner work.
## Both tests call this to isolate lifetime and modifier assertions.
func fixture() -> void:
	Match.reset_combat()
	Match.army.clear()
	Match.map.clear()
	Match.props.clear()
	for coordinate in [Vector2i.ZERO, Vector2i(1, 0)]:
		Match.map.append(HexInfo.new(Match.map.size(), coordinate, Enum.region.FRONT, Enum.side.NONE, 0))
	for unit in [CardCatalogue.alps_lone_wolf(1), CardCatalogue.pyromaniac_beetle(2), CardCatalogue.ironhide_boar_pup(1)]:
		unit.iun = Match.army.size()
		unit.ihx = Match.army.size() % 2
		unit.t_state = Enum.t_state.DEPLOYED
		Match.army.append(unit)
	Match.active_player = 1
	Match.turn_number = 1
	Match.phase = Match.Phase.ACTION

## Checks live bonuses change with observable life and never write stored counters.
## UnitInfo modifier getters call StateModifier and Condition synchronously.
func test_continuous_cards() -> void:
	fixture()
	var wolf := Match.army[0]
	var beetle := Match.army[1]
	wolf.actual_life -= 1
	check(wolf.physical_modifier == 3, "Wounded Lone Wolf gains +2 physical plus the live regional control bonus")
	check(wolf.physical_modifier == 3 and wolf.counter_modifiers() == Vector2i.ZERO,
		"Repeated state reads do not accumulate the contribution into counters")
	wolf.actual_life = wolf.max_life
	check(wolf.physical_modifier == 1, "Lone Wolf loses its +2 when healed and keeps only regional control")
	check(beetle.magical_modifier == 2 and beetle.counter_modifiers() == Vector2i.ZERO,
		"Pyromaniac Beetle's deployed magic bonus remains derived")

## Checks Hit capture, ordered counter grants, and duplicate occurrence suppression.
## Match.action_event calls RulesRunner.capture_event; repeat delivery of the same ID is ignored.
func test_ironhide_trigger() -> void:
	fixture()
	var event := EffectEvent.new(&"hit", TargetRef.unit(2), TargetRef.unit(1), {"damage": 0})
	var copied_details := event.data
	copied_details.damage = 4
	check(event.occurrence_id > 0 and event.data.damage == 0
		and event.turn_number == Match.turn_number and event.controller == Match.active_player,
		"Event history has identity/boundary metadata and does not expose its copied details for mutation")
	Match.action_event.emit(event)
	check(Match.get_unit(2).counter_modifiers() == Vector2i(1, 1),
		"Ironhide gains physical and magical counters after its Hit")
	Match.rules_runner.capture_event(event)
	check(Match.get_unit(2).counter_modifiers() == Vector2i(1, 1),
		"Delivering the same occurrence twice does not duplicate its trigger")
	var next_event := EffectEvent.new(&"hit", TargetRef.unit(2), TargetRef.unit(1))
	Match.action_event.emit(next_event)
	check(Match.get_unit(2).counter_modifiers() == Vector2i(2, 2),
		"A distinct Hit occurrence triggers the same rule again")

## Exercises generic “have” recipients, “while” conditions, passive grants, and Bow values.
## UnitInfo getters and CombatResolver-facing values share ContinuousEffect.applies_to().
func test_have_and_while_contributions() -> void:
	fixture()
	var friendly := QuerySelector.new(TargetRef.Kind.UNIT)
	friendly.relative_owner = Enum.YOU
	Match.army[2].continuous_effects.append(ContinuousEffect.have(friendly, [
		Contribution.bow_values(1, 1), Contribution.action_values(&"fire", [1, 1]),
		Contribution.action_values(&"move", [1]), Contribution.passive_flag(&"steady")
	], null, null, "Friendly Bow and Steady grant"))
	var ally := Match.army[0]
	var enemy := Match.army[1]
	check(ally.effective_bow_bonus() == Vector2i(1, 1) and ally.has_effective_flag(&"steady"),
		"A have rule exports Bow adjustments and passive flags to selected friendly units")
	check(ally.effective_action_values(&"fire", [1, 2]) == [2, 3]
		and ally.effective_action_values(&"move", [1]) == [2],
		"Continuous action values adjust named families and preserve each parameter index")
	Match.map.append(HexInfo.new(2, Vector2i(2, 0), Enum.region.FRONT, Enum.side.NONE, 0))
	Match.army[1].t_state = Enum.t_state.DEFEATED
	Match.army[1].ihx = -1
	var move_phrase := Effect.ConsequencePhrase.new(Selectors.Self.new(), Verbs.movement(1), DistanceSelector.within(1))
	var move_context := PhraseExecution.new()
	move_context.phrase = move_phrase
	move_context.source = TargetRef.unit(0)
	move_context.subject = TargetRef.unit(0)
	var expanded := DistanceSelector.within(1).resolve(move_context)
	check(TargetResolver.contains(expanded, TargetRef.hex(2))
		and CombatResolver.can_move(TargetRef.unit(0), TargetRef.hex(2), 1, false),
		"A Move contribution expands both preview candidates and committed range legality")
	Match.map.append(HexInfo.new(3, Vector2i(3, 0), Enum.region.FRONT, Enum.side.NONE, 0))
	var fire_phrase := Effect.ConsequencePhrase.new(Selectors.Self.new(), Verbs.fire(1), DistanceSelector.within(2))
	var fire_context := PhraseExecution.new()
	fire_context.phrase = fire_phrase
	fire_context.source = TargetRef.unit(0)
	fire_context.subject = TargetRef.unit(0)
	check(TargetResolver.contains(DistanceSelector.within(2).resolve(fire_context), TargetRef.hex(3)),
		"A Fire range contribution expands target preview for the named action")
	Match.army[1].t_state = Enum.t_state.DEPLOYED
	Match.army[1].ihx = 1
	check(CombatResolver.can_bow(TargetRef.unit(0), TargetRef.hex(1), 1, 0),
		"A live Bow range contribution is used by target legality, not only the display getter")
	check(enemy.effective_bow_bonus() == Vector2i.ZERO and not enemy.has_effective_flag(&"steady"),
		"A have rule does not export values to an opposing recipient")
	var wounded := ContinuousEffect.while_self(Condition.Wounded.new(), [Contribution.modifiers(2, 0)], "Wounded +2")
	Match.army[1].continuous_effects.append(wounded)
	var healthy_value := enemy.physical_modifier
	enemy.actual_life -= 1
	check(enemy.physical_modifier == healthy_value + 2,
		"A while rule contributes immediately when its condition becomes true")
	enemy.actual_life = enemy.max_life
	check(enemy.physical_modifier == healthy_value,
		"A while rule disappears when its condition becomes false without counter writes")
	check(ally.counter_modifiers() == Vector2i.ZERO and enemy.counter_modifiers() == Vector2i.ZERO,
		"Repeated derived reads do not store modifier, passive, or action grants")

## Covers intrinsic conditions needed by Guerra-style while rules and their live toggles.
## ContinuousEffect uses these predicates through the shared RuleContext recipient binding.
func test_live_state_conditions() -> void:
	fixture()
	var unit := Match.army[1]
	var ctx := RuleContext.new(TargetRef.unit(1))
	unit.active = false
	check(Condition.Active.new(false).test(ctx) and Condition.Deployed.new().test(ctx),
		"Inactive and deployed conditions read current unit state")
	var temporary := Match.get_property(TargetRef.property(TargetRef.unit(1), UnitInfo.TEMP_PHYSICAL_COUNTER))
	temporary.value = 1
	check(Condition.Shielded.new().test(ctx), "Shielded detects temporary protection counters")
	var bash := BashInfo.new()
	bash.attacker_id = 0
	bash.defender_id = 1
	Match.bashes.append(bash)
	check(Condition.Bashing.new().test(ctx) and Condition.BashingEnemy.new().test(ctx),
		"Bashing conditions match the recipient's current unresolved Bash identity")
	Match.army[0].type = Enum.type.HERO
	check(Condition.BashingEnemyHero.new().test(ctx), "BashingEnemyHero narrows the current Bash to an opposing Hero")

## Exercises implemented Guerra card patterns: White Wolf's exported aura and Canyon Ibex's while rule.
## CardCatalogue owns the definitions; UnitInfo reads resulting values from live state.
func test_guerra_continuous_card_examples() -> void:
	fixture()
	var wolf := CardCatalogue.white_wolf(1)
	wolf.iun = 2
	wolf.ihx = 0
	wolf.t_state = Enum.t_state.DEPLOYED
	wolf.active = false
	Match.army[2] = wolf
	check(Match.army[0].effective_bow_bonus() == Vector2i(1, 1),
		"White Wolf exports Bow values to adjacent friendlies while inactive")
	wolf.active = true
	check(Match.army[0].effective_bow_bonus() == Vector2i.ZERO,
		"White Wolf's live aura disappears as soon as its source becomes active")
	var ibex := CardCatalogue.canyon_ibex(1)
	ibex.iun = 0
	ibex.ihx = 0
	ibex.t_state = Enum.t_state.DEPLOYED
	Match.army[0] = ibex
	var bash := BashInfo.new()
	bash.attacker_id = 0
	bash.defender_id = 1
	Match.bashes.append(bash)
	check(ibex.physical_modifier == 3,
		"Canyon Ibex receives +2 physical while bashing plus derived regional control")

## Verifies the ruling filters trigger candidates while preserving the successful Die event.
## RulesRunner.capture_event() checks continuous policy before it creates trigger executions.
func test_hushbringer_ruling() -> void:
	fixture()
	var dying := Match.army[0]
	var die_pattern := Effect.EventPhrase.observe(&"die", Selectors.Self.new(),
		QuerySelector.new(TargetRef.Kind.HEX), TargetRef.Kind.UNIT, TargetRef.Kind.HEX)
	var gain := Effect.ConsequencePhrase.new(Selectors.Self.new(), Verbs.change_counter(1),
		Selectors.PropertyOf.new(Selectors.Self.new(), UnitInfo.PHYSICAL_COUNTER), Effect.Phrase.TargetMode.ALL)
	dying.trigger_effects.append(Effect.on_event(die_pattern, gain))
	var any_dying_unit := QuerySelector.new(TargetRef.Kind.UNIT)
	var any_die_hex := QuerySelector.new(TargetRef.Kind.HEX)
	var nearby_reaction := Effect.EventPhrase.observe(&"die", any_dying_unit, any_die_hex,
		TargetRef.Kind.UNIT, TargetRef.Kind.HEX)
	Match.army[2].trigger_effects.append(Effect.on_event(nearby_reaction, gain))
	var any_unit := QuerySelector.new(TargetRef.Kind.UNIT)
	Match.army[2].continuous_effects.append(ContinuousEffect.have(any_unit,
		[Contribution.hushbringer()], null, null, "Defeat causes no triggers"))
	var before := dying.counter_modifiers()
	var reaction_before := Match.army[2].counter_modifiers()
	var death := EffectEvent.new(&"die", TargetRef.unit(0), TargetRef.hex(0),
		{"last_hex": 0, "owner": dying.player})
	Match.rules_runner.capture_event(death)
	check(death.succeeded() and death.action == &"die",
		"The defeat event remains a successful, inspectable occurrence")
	check(dying.counter_modifiers() == before,
		"The Hushbringer ruling suppresses the defeated unit's own Die trigger")
	check(Match.army[2].counter_modifiers() == reaction_before,
		"The Hushbringer ruling also suppresses another card's reaction to that defeat")
	check(Match.rules_runner.work.is_empty() and Match.rules_runner.active == null,
		"The Hushbringer ruling prevents a trigger execution from being captured")
	Match.action_event.emit(EffectEvent.new(&"hit", TargetRef.unit(2), TargetRef.unit(1)))
	check(Match.army[2].counter_modifiers() == reaction_before + Vector2i(1, 1),
		"The defeat-only policy leaves unrelated Hit triggers eligible")

## Checks Prism Moth's target-stage Bash trigger and its separate Instant Bow definition.
## RulesRunner matches the defender identity before the Bash resolves or inflicts damage.
func test_prism_engagement() -> void:
	fixture()
	var moth := CardCatalogue.prism_moth(2)
	moth.iun = 2
	moth.ihx = 1
	moth.t_state = Enum.t_state.DEPLOYED
	Match.army[2] = moth
	var event := EffectEvent.new(&"bash", TargetRef.unit(0), TargetRef.unit(2), {"hex": 1}, &"target")
	Match.action_event.emit(event)
	check(moth.counter_modifiers() == Vector2i(1, 1),
		"Prism Moth gains both counters when an opponent declares a Bash against it")
	check(moth.effects.any(func(effect: Effect) -> bool:
		return effect.consequence.verb.name == &"bow" and effect.consequence.verb.user_params[2]),
		"Prism Moth's Bow definition carries the Instant setting")
	var unrelated := EffectEvent.new(&"bash", TargetRef.unit(0), TargetRef.unit(1), {"hex": 0}, &"target")
	Match.action_event.emit(unrelated)
	check(moth.counter_modifiers() == Vector2i(1, 1),
		"A Bash against another unit does not trigger Prism Moth")

## Records a named assertion and increments the scene's test totals.
## Focused integration routines call this; failures make the scene exit nonzero.
func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
