extends Node

var failures := 0
var checks := 0
var shots: Array = []
var records: Array[TargetRef] = []

class WrongDomainResult extends Selector:
	## Declares HEX for the fallback regression; resolve() deliberately violates that contract.
	func output_kind(_ctx: RuleContext = null) -> int:
		return TargetRef.Kind.HEX

	## Returns a valid first target followed by a malformed result to check that a match cannot hide the error.
	func resolve(_ctx: RuleContext) -> Array[TargetRef]:
		return [TargetRef.hex(1), TargetRef.unit(1)]

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func reset_board() -> void:
	Match.reset_combat()
	Match.army.clear()
	Match.map.clear()
	Match.props.clear()
	shots.clear()
	records.clear()
	for coordinate in [Vector2i.ZERO, Vector2i(1, 0), Vector2i(1, -1), Vector2i(3, 0)]:
		Match.map.append(HexInfo.new(Match.map.size(), coordinate, Enum.region.FRONT, Enum.side.NONE, 0))
	add_unit(1, 0, "Source")
	add_unit(1, 1, "Ally")
	add_unit(2, 1, "Enemy")
	Match.map[1].owner = Enum.owner.BOTH

func add_unit(player: int, tile: int, title: String) -> TargetRef:
	var info := UnitInfo.new()
	info.player = player
	info.ihx = tile
	info.iun = Match.army.size()
	info.name = title
	info.t_state = Enum.t_state.DEPLOYED if tile >= 0 else Enum.t_state.UNDEPLOYED
	Match.army.append(info)
	return TargetRef.unit(info.iun)

func begin(phrase: Effect.Phrase, source: TargetRef = TargetRef.unit(0)) -> PhraseSelection:
	var execution := PhraseSelection.new()
	execution.begin_standalone(phrase, source)
	return execution

func deactivate(target: Selector, mode: Effect.Phrase.TargetMode = Effect.Phrase.TargetMode.CHOOSE_ONE) -> Effect.ConsequencePhrase:
	return Effect.ConsequencePhrase.new(Selectors.Self.new(), Verbs.deactivate(), target, mode)

func damage(target: Selector, mode: Effect.Phrase.TargetMode = Effect.Phrase.TargetMode.CHOOSE_ONE) -> Effect.ConsequencePhrase:
	return Effect.ConsequencePhrase.new(Selectors.Self.new(), Verbs.damage(2), target, mode)

func recorder(kind: TargetRef.Kind) -> Effect.Verb:
	return Effect.Verb.new(&"record", record, Callable(), TargetRef.Kind.UNIT, kind)

func record(_subject: TargetRef, target: TargetRef) -> bool:
	records.append(target)
	return true

## Runs the selector regressions, including selected-identity revalidation and board integration.
func _ready() -> void:
	Match.fire.connect(func(s: TargetRef, t: TargetRef, amount: int) -> void: shots.append([s, t, amount]))
	test_native_and_conversion()
	test_selected_membership()
	test_native_existence()
	test_single_activity_preview()
	test_fixed_command_targets()
	test_context_and_identity()
	test_properties()
	test_all_and_reentrancy()
	test_effect_runner()
	test_consequence_sequence()
	test_fire_stickers()
	await test_board()
	print("Selection integration: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)

func test_native_and_conversion() -> void:
	reset_board()
	var ring := DistanceSelector.new(1)
	var units := begin(deactivate(ring))
	check(ring.output_kind(units) == TargetRef.Kind.HEX, "Distance remains natively HEX")
	check(units.candidates.size() == 2, "Hex to unit expansion includes both occupants, not empty tiles")
	check(units.candidates[0].kind == TargetRef.Kind.UNIT, "Converted candidates are UNIT references")
	check(units.choose(TargetRef.unit(2)), "User can select the enemy separately")
	check(not Match.army[2].active and Match.army[1].active, "Only one selected occupant is deactivated")
	check(not units.choose(TargetRef.unit(1)), "Completed selection rejects another click")
	var tiles := begin(damage(ring))
	check(tiles.candidates.size() == 2 and tiles.candidates[0].kind == TargetRef.Kind.HEX, "Damage keeps hex targets including empty tiles")
	check(shots.is_empty(), "CHOOSE_ONE waits for user input")
	check(tiles.choose(TargetRef.hex(2)), "Empty legal tile can receive damage")
	check(shots.size() == 1 and shots[0][2] == 2, "Damage preserves combat signal parameters")
	var only_self := begin(deactivate(Selectors.Self.new()))
	check(only_self.status == PhraseExecution.Status.TARGET and Match.army[0].active, "Even a single target waits for choice")
	only_self.cancel()
	check(Match.army[0].active, "Cancellation never executes a pending action")
	var incompatible := begin(damage(Selectors.Self.new()))
	check(incompatible.status == PhraseExecution.Status.FAILED and not incompatible.error.is_empty(), "UNIT to HEX requires explicit projection")
	var empty_wrong := Selectors.Literal.new(TargetRef.Kind.PLAYER, [])
	var mismatch := begin(deactivate(empty_wrong))
	check(not mismatch.error.is_empty(), "An empty result does not conceal a kind mismatch")
	var empty_valid := begin(deactivate(Selectors.Literal.new(TargetRef.Kind.HEX, [TargetRef.hex(2)])))
	check(empty_valid.status == PhraseExecution.Status.FAILED and empty_valid.error.is_empty(), "Empty tile conversion is no candidates, not a type error")
	var explicit_hex := begin(damage(Selectors.HexOf.new(Selectors.Self.new())))
	check(explicit_hex.candidates.size() == 1 and explicit_hex.candidates[0].id == 0, "Explicit HexOf projects source")
	explicit_hex.cancel()
	Match.army[2].active = true
	var enemy := begin(deactivate(Selectors.UnitsOn.new(ring).where(Selectors.EnemyOfSelf.new())))
	check(enemy.candidates.size() == 1 and enemy.candidates[0].id == 2, "Unit ownership filter works on shared hex")
	enemy.cancel()
	var bad_group := begin(deactivate(ring.and_with(QuerySelector.new())))
	check(not bad_group.error.is_empty(), "Cross-domain intersection fails before querying")
	var repeated := Selectors.Literal.new(TargetRef.Kind.HEX, [TargetRef.hex(1), TargetRef.hex(1)])
	var unique := begin(deactivate(repeated))
	check(unique.candidates.size() == 2, "Repeated tiles do not duplicate units")
	unique.cancel()
	var union := begin(damage(ring.or_with(Selectors.HexOf.new(Selectors.Self.new()))))
	check(union.candidates.size() == 3, "Same-domain union deduplicates")
	union.cancel()
	check(DistanceSelector.hex_distance(Vector2i.ZERO, Vector2i(1, -1)) == 1, "Axial geometry uses x+y axis")
	var within := begin(damage(DistanceSelector.within(1)))
	check(within.candidates.size() == 3, "Within includes center while exact ring excludes it")
	within.cancel()

## Compares direct membership with the full picker and checks the live adaptations used by commit.
func test_selected_membership() -> void:
	reset_board()
	var ctx := RuleContext.new(TargetRef.unit(0), EffectEvent.new(&"move", TargetRef.unit(0), TargetRef.hex(3)))
	var towards := DistanceSelector.within(3)
	towards.direction = Enum.direction.TOWARDS
	towards.reference = Selectors.Anchor.EVENT_TARGET
	var away := DistanceSelector.within(3)
	away.direction = Enum.direction.AWAY
	away.reference = Selectors.Anchor.EVENT_TARGET
	for selector: Selector in [DistanceSelector.new(1), DistanceSelector.within(1), towards, away, Selectors.BowTargets.new(1)]:
		var all := TargetResolver.resolve(selector, TargetRef.Kind.HEX, ctx)
		for tile in Match.map:
			var hex := TargetRef.hex(tile.hex_id)
			var one := TargetResolver.resolve(selector, TargetRef.Kind.HEX, ctx, hex)
			check(one.error.is_empty() and (not one.candidates.is_empty()) == TargetResolver.contains(all.candidates, hex),
				"Single-hex membership agrees with the full spatial selector")
	var selected := TargetRef.unit(2)
	var ring := DistanceSelector.new(1)
	check(TargetResolver.resolve(ring, TargetRef.Kind.UNIT, ctx, selected).candidates.size() == 1,
		"Single-target adaptation keeps the selected participant on a shared Bash hex")
	Match.army[2].t_state = Enum.t_state.UNDEPLOYED
	check(TargetResolver.resolve(ring, TargetRef.Kind.UNIT, ctx, selected).candidates.is_empty(),
		"Single-target adaptation rejects a reserve unit even with an old position")
	var property := Selectors.PropertyOf.new(Selectors.Self.new(), UnitInfo.STUN_COUNTER)
	check(TargetResolver.resolve(property, TargetRef.Kind.PROPERTY, ctx,
		TargetRef.property(TargetRef.unit(0), UnitInfo.STUN_COUNTER)).candidates.size() == 1,
		"Single-property membership preserves SELF and the stable counter key")
	check(TargetResolver.resolve(property, TargetRef.Kind.PROPERTY, ctx,
		TargetRef.property(TargetRef.unit(1), UnitInfo.STUN_COUNTER)).candidates.is_empty(),
		"A counter with the same key on a different unit cannot replace the selected property")
	var malformed := TargetResolver.resolve(WrongDomainResult.new(), TargetRef.Kind.HEX, ctx, TargetRef.hex(1))
	check(not malformed.error.is_empty() and malformed.candidates.is_empty(),
		"Fallback validates the whole native result even when it finds the requested hex")

## Checks the availability scan's early exit and its fallback for selectors
## that require domain conversion or validation of every result.
func test_native_existence() -> void:
	reset_board()
	var ctx := RuleContext.new(TargetRef.unit(0))
	var seen: Array[int] = []
	var accept := func(ref: TargetRef) -> bool:
		seen.append(ref.id)
		return ref.id == 1
	var found := TargetResolver.any_matching(DistanceSelector.within(3), TargetRef.Kind.HEX, ctx, accept)
	check(found == Selector.Membership.INCLUDED and seen == [0, 1],
		"Native existence stops at the first hex that passes legality")
	check(TargetResolver.any_matching(DistanceSelector.within(3), TargetRef.Kind.UNIT, ctx, accept)
		== Selector.Membership.UNKNOWN, "Existence retains full resolution for HEX-to-UNIT adaptation")
	check(TargetResolver.any_matching(WrongDomainResult.new(), TargetRef.Kind.HEX, ctx, accept)
		== Selector.Membership.UNKNOWN, "Custom selectors retain full validation")
	check(TargetResolver.any_matching(DistanceSelector.new(-1), TargetRef.Kind.HEX, ctx, accept)
		== Selector.Membership.EXCLUDED, "Definition validation precedes the existence scan")

## Checks that the direct SELF activity preview publishes the same retained
## selection to its consequence and leaves all live resources alone.
func test_single_activity_preview() -> void:
	reset_board()
	Match.active_player = 1
	Match.phase = Match.Phase.ACTION
	Match.players[1].actions_remaining = 1
	var source := TargetRef.unit(0)
	var unit := Match.get_unit(0)
	var stun := Match.get_property(TargetRef.property(source, UnitInfo.STUN_COUNTER))
	var consequence := Effect.ConsequencePhrase.new(Selectors.Self.new(), recorder(TargetRef.Kind.UNIT),
		Selectors.Completed.new(&"cost_0", &"targets", TargetRef.Kind.UNIT))
	var effect := Effect.new(Collection.action_cost(), null, consequence)
	check(Match.rules_runner.command_available(effect, source), "The consequence can read the retained SELF cost target")
	check(unit.active and stun.value == 0 and Match.players[1].actions_remaining == 1 and records.is_empty(),
		"Availability spends no resources and runs no consequence")
	unit.active = false
	check(not Match.rules_runner.command_available(effect, source), "An inactive unit cannot pay self-Stun")
	unit.active = true
	unit.props.erase(stun)
	check(not Match.rules_runner.command_available(effect, source), "A missing Stun counter makes the payment unavailable")

## Uses the same target-first submission as the board. A fixed SELF shield
## resolves immediately, while a one-result spatial selector still asks.
func test_fixed_command_targets() -> void:
	reset_board()
	Match.active_player = 1
	Match.phase = Match.Phase.ACTION
	Match.players[1].actions_remaining = 3
	var source := TargetRef.unit(0)
	var shield := Collection.shield_DR(2)
	check(Match.rules_runner.submit(shield, source, true), "The fixed-target Shield starts")
	check(Match.rules_runner.active == null and Match.army[0]._counter_value(UnitInfo.TEMP_PHYSICAL_COUNTER) == 2
		and Match.army[1]._counter_value(UnitInfo.TEMP_PHYSICAL_COUNTER) == 0
		and Match.players[1].actions_remaining == 2, "Shield pays once and only protects SELF without a click")
	var command := Effect.new(null, null, Effect.ConsequencePhrase.new(Selectors.Self.new(),
		recorder(TargetRef.Kind.HEX), DistanceSelector.within(0)))
	check(Match.rules_runner.submit(command, source, true) and Match.rules_runner.active != null
		and Match.rules_runner.active.current.candidates.size() == 1 and records.is_empty(),
		"A spatial query with one result still opens the target picker")
	if Match.rules_runner.active != null: Match.rules_runner.active.cancel()

func test_context_and_identity() -> void:
	reset_board()
	var definition := damage(DistanceSelector.within(1))
	var a := begin(definition)
	var b := begin(definition, TargetRef.unit(1))
	check(a.subject.id == 0 and b.subject.id == 1, "Shared definitions have isolated pending actors")
	check(a.effect_execution.source.id == 0 and b.effect_execution.source.id == 1, "Shared SELF selector has no mutable context")
	var ref := TargetRef.unit(1)
	Match.army[1].ihx = 2
	check(ref.same(TargetRef.unit(1)) and ref.hex_id() == 2, "Unit identity survives movement and position is current")
	a.cancel()
	b.cancel()
	var moved := begin(deactivate(DistanceSelector.new(1)))
	Match.army[1].ihx = 3
	check(not moved.choose(ref), "Moved target outside range is rejected at commit")
	check(Match.army[1].active, "Stale choice causes no mutation")
	var removed := begin(deactivate(DistanceSelector.new(1)))
	Match.army[2] = null
	check(not removed.choose(TargetRef.unit(2)), "Removed unit cannot execute")
	var reserve := add_unit(2, -1, "Reserve")
	check(reserve.valid() and not reserve.has_hex(), "Off-board unit remains a valid identity")
	var spatial := begin(damage(DistanceSelector.within(1)), reserve)
	check(spatial.status == PhraseExecution.Status.FAILED, "Off-board anchor has no spatial results")
	var subject_query := QuerySelector.new()
	var multi := begin(Effect.ConsequencePhrase.new(subject_query, recorder(TargetRef.Kind.PLAYER), QuerySelector.new(TargetRef.Kind.PLAYER)))
	check(multi.status == PhraseExecution.Status.SUBJECT, "Multiple subjects prompt before targets")
	check(multi.choose(TargetRef.unit(1)) and multi.status == PhraseExecution.Status.TARGET, "Choosing subject advances to targets")
	check(multi.choose(TargetRef.player(2)), "Player target uses common reference path")
	var directional := DistanceSelector.within(3)
	directional.direction = Enum.direction.TOWARDS
	directional.reference = Selectors.Anchor.EVENT_TARGET
	var no_anchor := begin(damage(directional))
	check(no_anchor.status == PhraseExecution.Status.FAILED, "Missing directional anchor yields no candidates")
	var ctx := EffectExecution.new(null, TargetRef.unit(0), EffectEvent.new(&"move", TargetRef.unit(0), TargetRef.hex(3)))
	var phrase_ctx := PhraseExecution.new()
	phrase_ctx.begin(damage(directional), ctx)
	check(phrase_ctx.candidates.size() == 2, "Towards keeps only candidates closer to event anchor")
	phrase_ctx.cancel()

func test_properties() -> void:
	reset_board()
	var counter := Prop.new()
	counter.name = "poison"
	counter.increment = Enum.p_increment.COUNTER
	counter.value = 3
	Match.army[0].props.append(counter)
	var prop_ref := TargetRef.property(TargetRef.unit(0), &"poison")
	var definition := Effect.ConsequencePhrase.new(Selectors.Self.new(), Verbs.decrement(), Selectors.PropertyOf.new(Selectors.Self.new(), &"poison"))
	var selection := begin(definition)
	check(selection.candidates.size() == 1 and selection.candidates[0].same(prop_ref), "Property selection identifies host and key")
	Match.army[0].props.push_front(Prop.new())
	check(selection.choose(prop_ref) and counter.value == 2, "Reordering properties preserves selected identity")
	check(prop_ref.has_hex() and prop_ref.hex_id() == 0, "Hosted property can be displayed on its tile")
	var flag := Prop.new()
	flag.name = "shield"
	flag.increment = Enum.p_increment.FLAG
	Match.players[1].props = [flag]
	var host := Selectors.Literal.new(TargetRef.Kind.PLAYER, [TargetRef.player(1)])
	var set_flag := begin(Effect.ConsequencePhrase.new(Selectors.Self.new(), Verbs.set_flag(true), Selectors.PropertyOf.new(host, &"shield")))
	check(set_flag.choose(TargetRef.property(TargetRef.player(1), &"shield")) and flag.value == 1, "Flags on players use explicit property references")
	var wrong := begin(Effect.ConsequencePhrase.new(Selectors.Self.new(), Verbs.decrement(), Selectors.PropertyOf.new(host, &"shield")))
	check(wrong.status == PhraseExecution.Status.FAILED, "Counter verb rejects flags")
	var absent := begin(Effect.ConsequencePhrase.new(Selectors.Self.new(), Verbs.decrement(), Selectors.PropertyOf.new(host, &"missing")))
	check(absent.status == PhraseExecution.Status.FAILED, "Missing property yields no target")
	var global_counter := Prop.new()
	global_counter.name = "round"
	global_counter.increment = Enum.p_increment.COUNTER
	global_counter.value = 4
	Match.props.append(global_counter)
	check(TargetRef.property(TargetRef.match_host(), &"round").valid(), "Global properties have a match host")
	var nested := Selectors.PropertyOf.new(Selectors.PropertyOf.new(host, &"shield"), &"nested")
	check(not nested.validate().is_empty(), "Nested property hosts are rejected")

func test_all_and_reentrancy() -> void:
	reset_board()
	var all_units := begin(deactivate(DistanceSelector.new(1), Effect.Phrase.TargetMode.ALL))
	check(all_units.status == PhraseExecution.Status.SUCCEEDED and all_units.outcomes.size() == 2, "ALL runs the adapted unit set")
	check(not Match.army[1].active and not Match.army[2].active, "ALL affects each occupant once")
	var optional := damage(DistanceSelector.new(1), Effect.Phrase.TargetMode.ALL)
	optional.optional = true
	var pending := begin(optional)
	check(pending.status == PhraseExecution.Status.CONFIRMING and shots.is_empty(), "Optional ALL requires separate confirmation")
	pending.confirm(false)
	check(shots.is_empty(), "Declining optional ALL does nothing")
	var confirmed := begin(optional)
	confirmed.confirm(true)
	check(shots.size() == 2, "Confirmed ALL damages both tiles")
	confirmed.confirm(true)
	check(shots.size() == 2, "Repeated confirmation does not run twice")
	reset_board()
	var custom := Effect.Verb.new(&"mutate", func(_actor: TargetRef, target: TargetRef) -> bool:
		records.append(target)
		if target.id == 1:
			Match.army[2].ihx = 3
			add_unit(2, 1, "New arrival")
		return true, Callable(), TargetRef.Kind.UNIT, TargetRef.Kind.UNIT)
	var batch := begin(Effect.ConsequencePhrase.new(Selectors.Self.new(), custom, DistanceSelector.new(1), Effect.Phrase.TargetMode.ALL))
	check(records.size() == 1 and records[0].id == 1, "ALL freezes membership and skips a target moved by an earlier action")
	check(batch.outcomes.size() == 2 and not batch.outcomes[1].success, "Batch records skipped outcomes")
	reset_board()
	var reentrant := PhraseSelection.new()
	reentrant.changed.connect(func() -> void:
		if reentrant.status == PhraseExecution.Status.COMMITTING:
			check(not reentrant.choose(TargetRef.unit(1)), "Commit rejects reentrant choice"))
	reentrant.begin_standalone(deactivate(DistanceSelector.new(1)), TargetRef.unit(0))
	reentrant.choose(TargetRef.unit(1))
	reentrant.changed.disconnect(reentrant.changed.get_connections()[0].callable)
	check(not Match.army[1].active, "Reentrant callback completes normally")

func test_effect_runner() -> void:
	reset_board()
	var deferred := EffectExecution.new(Effect.new(Collection.action_cost(), null,
		deactivate(DistanceSelector.new(1))), TargetRef.unit(0))
	deferred.defer_cost_until_target = true
	deferred.start()
	check(deferred.status == EffectExecution.Status.CONSEQUENCE and Match.army[0].active
		and not deferred.cost_paid, "Action target choices appear before the activity cost")
	check(deferred.current.choose(TargetRef.unit(2)), "Player can choose the action target from its preview")
	check(deferred.status == EffectExecution.Status.SUCCEEDED and deferred.cost_paid
		and not Match.army[0].active and not Match.army[2].active,
		"Choosing a target pays the single SELF cost and commits that same target")
	reset_board()
	var run := EffectExecution.new(Collection.fire_DR(2, 1), TargetRef.unit(0))
	run.start()
	check(run.status == EffectExecution.Status.COST and Match.army[0].active, "Effect waits to pay its cost")
	var cost_phase := run.current
	check(cost_phase.choose(TargetRef.unit(0)), "Cost commits after a user choice")
	check(run.cost_paid and run.status == EffectExecution.Status.CONSEQUENCE, "Successful cost advances to consequence")
	check(run.current != cost_phase and run.current.effect_execution == cost_phase.effect_execution, "Phrase executions share parent, not choices")
	check(run.current.targets.is_empty() and cost_phase.targets.size() == 1, "Cost target does not leak into consequence")
	var previous := TargetResolver.resolve(Selectors.Completed.new(&"cost", &"targets", TargetRef.Kind.UNIT), TargetRef.Kind.UNIT, run.current)
	check(previous.candidates.size() == 1 and previous.candidates[0].id == 0, "Completed selectors explicitly reference prior phrase choices")
	check(run.current.choose(TargetRef.hex(1)) and run.status == EffectExecution.Status.SUCCEEDED, "Consequence completes the activation")
	check(run.results.has("cost") and run.results.has("consequence"), "Completed phase results are retained")
	reset_board()
	var cancelled := EffectExecution.new(Collection.fire_DR(2, 1), TargetRef.unit(0))
	cancelled.start()
	cancelled.cancel()
	check(Match.army[0].active and not cancelled.cost_paid, "Cancellation before payment leaves cost untouched")
	var after_cost := EffectExecution.new(Collection.fire_DR(2, 1), TargetRef.unit(0))
	after_cost.start()
	after_cost.current.choose(TargetRef.unit(0))
	after_cost.cancel()
	check(after_cost.cost_paid and not Match.army[0].active and shots.is_empty(), "Cancellation after payment preserves paid cost")
	reset_board()
	var event_pattern := Effect.EventPhrase.new(Selectors.Self.new(), Verbs.deactivate(), QuerySelector.new())
	var triggered := Effect.new(null, event_pattern, damage(DistanceSelector.new(1)))
	Match.army[1].active = false
	var event := EffectEvent.new(&"deactivate", TargetRef.unit(0), TargetRef.unit(1), {"from_hex": 1})
	var run_event := EffectExecution.new(triggered, TargetRef.unit(0), event)
	run_event.start()
	check(run_event.status == EffectExecution.Status.CONSEQUENCE, "Event matches participants despite post-action inactive target")
	check(event.data.from_hex == 1, "Event retains explicit historical data")
	run_event.cancel()
	var wrong_event := EffectExecution.new(triggered, TargetRef.unit(0), EffectEvent.new(&"damage", TargetRef.unit(0), TargetRef.hex(1)))
	wrong_event.start()
	check(wrong_event.status == EffectExecution.Status.FAILED, "Unmatched event never executes consequence")
	var invalid_cost := Effect.CostPhrase.new(Selectors.Self.new(), Verbs.deactivate(), DistanceSelector.new(1), Effect.Phrase.TargetMode.ALL)
	var unsupported := EffectExecution.new(Effect.new(invalid_cost, null, null), TargetRef.unit(0))
	unsupported.start()
	check(unsupported.status == EffectExecution.Status.FAILED and Match.army[2].active, "Unsupported multi-target cost fails before mutation")

## Verifies ordered phrase continuation, named results, cancellation, and preflight.
## _ready() calls this as part of the selection integration scene.
func test_consequence_sequence() -> void:
	reset_board()
	var physical := Effect.ConsequencePhrase.new(Selectors.Self.new(), Verbs.change_counter(1),
		Selectors.PropertyOf.new(Selectors.Self.new(), UnitInfo.PHYSICAL_COUNTER))
	var magical := Effect.ConsequencePhrase.new(Selectors.Self.new(), Verbs.change_counter(2),
		Selectors.PropertyOf.new(Selectors.Self.new(), UnitInfo.MAGICAL_COUNTER))
	var definition := Effect.new(null, null, Effect.ConsequenceSequence.new([physical, magical]))
	var run := EffectExecution.new(definition, TargetRef.unit(0))
	run.start()
	check(run.status == EffectExecution.Status.CONSEQUENCE and run.current.phrase == physical,
		"Ordered effect begins at its first consequence")
	check(run.current.choose(TargetRef.property(TargetRef.unit(0), UnitInfo.PHYSICAL_COUNTER)),
		"The first consequence waits for the normal target choice")
	check(run.status == EffectExecution.Status.CONSEQUENCE and run.current.phrase == magical,
		"Completing a phrase resumes the sequence at its next step")
	check(run.results.has("step_0") and run.results["step_0"].success,
		"Completed steps are addressable by ordered step key")
	check(run.current.choose(TargetRef.property(TargetRef.unit(0), UnitInfo.MAGICAL_COUNTER)),
		"The resumed phrase uses the same shared SELF")
	check(run.status == EffectExecution.Status.SUCCEEDED and Match.army[0].physical_modifier == 1
		and Match.army[0].magical_modifier == 2, "Both ordered counter changes resolve exactly once")
	check(run.results["consequence"].outcomes.size() == 2,
		"Aggregate consequence result records each target outcome")
	reset_board()
	var interrupted := EffectExecution.new(definition, TargetRef.unit(0))
	interrupted.start()
	interrupted.current.choose(TargetRef.property(TargetRef.unit(0), UnitInfo.PHYSICAL_COUNTER))
	interrupted.cancel()
	check(interrupted.status == EffectExecution.Status.CANCELLED
		and Match.army[0].physical_modifier == 1 and Match.army[0].magical_modifier == 0,
		"Cancelling a resumed sequence preserves earlier work and skips later steps")
	var no_steps: Array[Effect.ConsequencePhrase] = []
	var invalid := EffectExecution.new(Effect.new(null, null,
		Effect.ConsequenceSequence.new(no_steps)), TargetRef.unit(0))
	invalid.start()
	check(invalid.status == EffectExecution.Status.FAILED and Match.army[0].physical_modifier == 1,
		"Invalid sequences fail preflight without undoing earlier completed steps")

## Verifies Tireless, Action-free, Instant, and Pierce remain separate Fire properties.
## _ready() calls this as a focused rules regression in the selection integration scene.
func test_fire_stickers() -> void:
	reset_board()
	Match.players[1].actions_remaining = 0
	var free_fire := Collection.fire_DR(1, 1, true, true, true, true)
	var phrase := free_fire.consequence as Effect.ConsequencePhrase
	check(free_fire.cost == null and phrase.tireless and phrase.action_free,
		"Tireless removes default activity payment and Action-free is kept on the phrase")
	check(phrase.verb.user_params == [1, true, true, true],
		"Fire definition retains damage, Instant, Pierce, and token exemption")
	var run := EffectExecution.new(free_fire, TargetRef.unit(0))
	run.start()
	check(run.status == EffectExecution.Status.CONSEQUENCE,
		"Tireless Fire skips the generated activity cost")
	check(run.current.choose(TargetRef.hex(1)) and run.status == EffectExecution.Status.SUCCEEDED,
		"Action-free Instant Pierce can commit with no action tokens")
	check(Match.army[0].active and Match.players[1].actions_remaining == 0
		and Match.pending_attacks.is_empty(), "Free instant Fire preserves activity and spends no token")
	reset_board()
	Match.players[1].actions_remaining = 0
	var action_free_only := EffectExecution.new(Collection.fire_DR(1, 1, false, false, false, true), TargetRef.unit(0))
	action_free_only.start()
	check(action_free_only.status == EffectExecution.Status.COST, "Action-free still starts with activity payment")
	check(action_free_only.current.choose(TargetRef.unit(0)), "Active SELF can pay activity without an action token")
	check(not Match.army[0].active and Match.get_property(TargetRef.property(TargetRef.unit(0), UnitInfo.STUN_COUNTER)).value == 1,
		"Action-free payment still adds Stun and makes SELF inactive")
	check(action_free_only.current.choose(TargetRef.hex(1))
		and action_free_only.status == EffectExecution.Status.SUCCEEDED,
		"Action-free consequence can resolve after paying activity with no tokens")
	reset_board()
	Match.players[1].actions_remaining = 0
	var tireless_only := EffectExecution.new(Collection.fire_DR(1, 1, false, false, true, false), TargetRef.unit(0))
	tireless_only.start()
	check(tireless_only.status == EffectExecution.Status.FAILED and Match.army[0].active,
		"Tireless alone does not bypass action-token legality")

func test_board() -> void:
	reset_board()
	var board: GuerraBoard = load("res://scenes/board/board.tscn").instantiate()
	add_child(board)
	board.select_phrase(deactivate(DistanceSelector.new(1)), TargetRef.unit(0))
	board._on_cell_pressed(Vector2i(1, 0))
	check(board.choices.size() == 2 and board.choice_menu.item_count == 2, "Board opens menu for two units sharing a hex")
	board._on_choice_pressed(1)
	check(not Match.army[2].active and Match.army[1].active, "Board menu commits only selected unit")
	board.select_phrase(damage(DistanceSelector.new(1)), TargetRef.unit(0))
	board._on_cell_pressed(Vector2i(1, -1))
	check(shots.size() == 1 and shots[0][1].id == 2, "Board click selects native hex target")
	board.select_phrase(Effect.ConsequencePhrase.new(Selectors.Self.new(), recorder(TargetRef.Kind.PLAYER), QuerySelector.new(TargetRef.Kind.PLAYER)), TargetRef.unit(0))
	board._show_offboard_choices()
	check(board.offboard_button.visible and board.choices.size() == 2, "Off-board button exposes player choices")
	board._on_choice_pressed(1)
	check(records.back().same(TargetRef.player(2)), "Player menu reaches common action path")
	board.select_effect(Collection.fire_DR(2, 1), TargetRef.unit(0))
	board._on_cell_pressed(Vector2i.ZERO)
	check(board.effect_execution.cost_paid and board.selection == board.effect_execution.current, "Board follows cost-to-consequence transition")
	var escape := InputEventAction.new()
	escape.action = "board_cancel"
	escape.pressed = true
	board._unhandled_input(escape)
	check(board.effect_execution.status == EffectExecution.Status.CANCELLED, "Escape cancels current effect selection")
	await get_tree().physics_frame
	await get_tree().physics_frame
	var query := PhysicsPointQueryParameters2D.new()
	query.position = board.axial_to_screen(Vector2i.ZERO)
	query.collide_with_areas = true
	check(not board.get_world_2d().direct_space_state.intersect_point(query).is_empty(), "Hex click collision is active")
	board.queue_free()
	await get_tree().process_frame
