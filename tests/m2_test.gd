extends Node

var checks := 0
var failures := 0
var trace: Array[String] = []

## Exercises M2 through authoritative commands/events, including pauses between phase steps.
## Run directly with m2_test.tscn; failures return a nonzero exit code.
func _ready() -> void:
	test_command_ownership()
	test_capture_before_followups()
	test_subject_choice()
	test_cost_bundles()
	test_cost_followups()
	test_end_choice()
	test_death_snapshot()
	test_bash_hit()
	test_conditions()
	test_deploy_choice()
	test_combat_pause()
	test_nested_bundles()
	test_board_controls()
	print("M2 integration: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)

## Records a semantic assertion without aborting later independent scenarios.
func check(value: bool, description: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(description)

## Creates three deployed stable identities and enough local tokens for command tests.
func fixture() -> void:
	Match.reset_combat()
	Match.army.clear()
	Match.map.clear()
	trace.clear()
	for index in 3:
		Match.map.append(HexInfo.new(index, Vector2i(index, 0), Enum.region.FRONT, Enum.side.NONE, 0))
		var unit := UnitInfo.new()
		unit.iun = index
		unit.ihx = index
		unit.player = 1 if index < 2 else 2
		unit.actual_life = 4
		unit.max_life = 4
		unit.t_state = Enum.t_state.DEPLOYED
		unit.active = true
		Match.army.append(unit)
	Match.active_player = 1
	Match.phase = Match.Phase.ACTION
	Match.players[1].actions_remaining = 3
	Match.players[2].actions_remaining = 3

## Constructs a concrete persistent counter consequence using the existing shared property path.
func grant(amount: int = 1, mode: Effect.Phrase.TargetMode = Effect.Phrase.TargetMode.ALL) -> Effect.ConsequencePhrase:
	return Effect.ConsequencePhrase.new(Selectors.Self.new(), Verbs.change_counter(amount),
		Selectors.PropertyOf.new(Selectors.Self.new(), UnitInfo.PHYSICAL_COUNTER), mode)

## Returns SELF's selected modifier reference for pending choice submissions.
func physical(unit_id: int = 0) -> TargetRef:
	return TargetRef.property(TargetRef.unit(unit_id), UnitInfo.PHYSICAL_COUNTER)

## Builds a unit/unit occurrence pattern for focused trigger tests.
func pattern(action: StringName) -> Effect.EventPhrase:
	return Effect.EventPhrase.observe(action, Selectors.Self.new(), QuerySelector.new())

## Publishes a committed occurrence with no custom action implementation.
func emit_test(action: StringName) -> void:
	Match.action_event.emit(EffectEvent.new(action, TargetRef.unit(0), TargetRef.unit(2)))

## A retained player choice blocks Pass and another command, then spends its token once.
func test_command_ownership() -> void:
	fixture()
	var effect := Effect.new(null, null, grant(1, Effect.Phrase.TargetMode.CHOOSE_ONE))
	check(Match.rules_runner.submit(effect, TargetRef.unit(0)), "A command takes runner ownership")
	check(not Match.complete_action(1, 0), "Pass is rejected while a target choice is pending")
	check(not Match.rules_runner.submit(effect, TargetRef.unit(1)), "Another action cannot replace a pending choice")
	var execution := Match.rules_runner.active
	var phrase := execution.current
	check(phrase.choose(physical()), "The original choice resumes its command")
	check(Match.players[1].actions_remaining == 2 and not Match.rules_runner.busy(), "One complete command spends one token and releases ownership")
	check(not phrase.choose(physical()) and Match.players[1].actions_remaining == 2, "Repeated clicks cannot repay or recommit")
	Match.army[0].active = false
	check(Match.rules_runner.available(Collection.fire_DR(1, 2, false, false, true), TargetRef.unit(0)), "Inactive units can expose Tireless actions")
	check(not Match.rules_runner.available(Collection.fire_DR(1, 2), TargetRef.unit(0)), "Inactive units cannot expose ordinary self-Stun actions")

## Both rules match the same original counter state, even though the first changes it.
func test_capture_before_followups() -> void:
	fixture()
	var first := Effect.new(null, pattern(&"test"), grant())
	var second := Effect.new(null, pattern(&"test"), grant(2))
	second.condition = Condition.Compare.new(Selectors.PropertyOf.new(Selectors.Self.new(), UnitInfo.PHYSICAL_COUNTER), Condition.Compare.Op.EQ, 0)
	Match.army[0].trigger_effects.assign([first, second])
	emit_test(&"test")
	check(Match.get_property(physical()).value == 3, "All trigger conditions are captured before the first consequence")
	check(Match.rules_runner.diagnostics.is_empty(), "Nonmatches do not generate failure diagnostics")

## ALL selects targets only; a multiple-subject phrase must retain its execution for UI.
func test_subject_choice() -> void:
	fixture()
	var consequence := grant()
	consequence.subject = QuerySelector.new()
	Match.army[0].trigger_effects.append(Effect.new(null, pattern(&"test"), consequence))
	emit_test(&"test")
	check(Match.rules_runner.active != null and Match.rules_runner.active.current.status == PhraseExecution.Status.SUBJECT, "Automatic ALL still suspends for multiple subjects")
	check(not Match.complete_action(1, 0), "A trigger subject choice blocks phase advancement")
	Match.rules_runner.active.current.choose(TargetRef.unit(1))
	check(Match.get_property(physical()).value == 1 and not Match.rules_runner.busy(), "Subject choice finishes the retained triggered execution")
	check(Match.players[1].actions_remaining == 3, "Triggered effects do not spend standalone action tokens")

## Builds a repeated debit bundle so preflight must account for shared resource identity.
func bundle_effect() -> Effect:
	var cost := Effect.CostPhrase.new(Selectors.Self.new(), Verbs.decrement(2), Selectors.PropertyOf.new(Selectors.Self.new(), UnitInfo.MAGICAL_COUNTER))
	return Effect.new(Effect.CostBundle.new([cost, cost]), null, grant())

## Chooses both fixed costs; the first choice must not change any resource.
func choose_bundle() -> void:
	var target := TargetRef.property(TargetRef.unit(0), UnitInfo.MAGICAL_COUNTER)
	var before := Match.get_property(target).value
	Match.rules_runner.active.current.choose(target)
	check(Match.get_property(target).value == before, "Choosing the first bundle cost is read-only")
	Match.rules_runner.active.current.choose(target)

## Unaffordable cumulative payment changes nothing; an affordable bundle commits once.
func test_cost_bundles() -> void:
	fixture()
	var resource := Match.get_property(TargetRef.property(TargetRef.unit(0), UnitInfo.MAGICAL_COUNTER))
	resource.value = 3
	Match.rules_runner.submit(bundle_effect(), TargetRef.unit(0))
	choose_bundle()
	check(resource.value == 3 and Match.get_property(physical()).value == 0, "Unaffordable bundle has no partial payment or consequence")
	check(Match.players[1].actions_remaining == 3, "Failed unpaid bundle spends no token")
	resource.value = 4
	Match.rules_runner.submit(bundle_effect(), TargetRef.unit(0))
	choose_bundle()
	check(resource.value == 0 and Match.get_property(physical()).value == 1, "Affordable bundle commits both payments and its consequence")
	check(Match.players[1].actions_remaining == 2, "A bundle remains one standalone command")

## Cost triggers can pause before the paid parent's consequence; payment never repeats.
func test_cost_followups() -> void:
	fixture()
	Match.army[0].trigger_effects.append(Effect.new(null, pattern(&"stun"), grant(2, Effect.Phrase.TargetMode.CHOOSE_ONE)))
	var effect := Effect.new(Collection.action_cost(), null, grant(1))
	Match.rules_runner.submit(effect, TargetRef.unit(0))
	Match.rules_runner.active.current.choose(TargetRef.unit(0))
	check(Match.rules_runner.active.captured_trigger, "Cost followup owns UI before parent consequence")
	check(Match.get_property(physical()).value == 0, "Parent consequence has not run before its cost trigger")
	Match.rules_runner.active.current.choose(physical())
	check(Match.get_property(physical()).value == 3, "Cost trigger finishes before the restored parent's consequence")
	check(Match.get_property(TargetRef.property(TargetRef.unit(0), UnitInfo.STUN_COUNTER)).value == 1, "Resuming does not pay self-Stun again")

## Optional End effects ask before payment and retain the phase through every choice.
func test_end_choice() -> void:
	fixture()
	var players := QuerySelector.new(TargetRef.Kind.PLAYER)
	players.owner = Enum.owner.P1
	var event := Effect.EventPhrase.observe(&"end", players, players, TargetRef.Kind.PLAYER, TargetRef.Kind.PLAYER)
	var effect := Effect.new(Collection.action_cost(), event, grant())
	Match.army[0].trigger_effects.append(effect)
	Match.complete_action(1, 0)
	check(Match.phase == Match.Phase.END and Match.active_player == 1, "An optional End trigger holds the turn")
	check(Match.rules_runner.active.status == EffectExecution.Status.CONFIRMING and Match.army[0].active, "Optional acceptance precedes activity payment")
	Match.rules_runner.active.confirm(false)
	check(Match.active_player == 2 and Match.army[0].active, "Declining advances End without paying")
	fixture()
	Match.army[0].trigger_effects.append(effect)
	Match.complete_action(1, 0)
	Match.rules_runner.active.confirm(true)
	check(Match.phase == Match.Phase.END, "Accepted End cost still waits for its target")
	Match.rules_runner.active.current.choose(TargetRef.unit(0))
	check(Match.active_player == 2 and Match.get_property(physical()).value == 1, "Costed End trigger resolves legally before switching")
	check(not Match.army[0].active, "End trigger pays activity despite being outside Action")

## Spatial death matching captures the old position before Match removes the deployed source.
func test_death_snapshot() -> void:
	fixture()
	var event := Effect.EventPhrase.observe(&"die", Selectors.Self.new(), DistanceSelector.within(0), TargetRef.Kind.UNIT, TargetRef.Kind.HEX)
	var effect := Effect.new(null, event, grant())
	effect.condition = Condition.EventFact.new(&"last_hex", 0)
	Match.army[0].trigger_effects.append(effect)
	Match.defeat(TargetRef.unit(0))
	check(Match.army[0].ihx == -1 and Match.get_property(physical()).value == 1, "Death trigger survives loss of its original spatial anchor")

## Physical Bash contact now reaches the same printed Hit rule as Bow/Gore.
func test_bash_hit() -> void:
	fixture()
	Match.army[0].trigger_effects.append(Collection.ironhide_boar_pup_trigger())
	Match.army[2].ihx = 0
	var bash := BashInfo.new()
	bash.attacker_id = 0
	bash.defender_id = 2
	bash.target_hex = 0
	bash.responding_player = 2
	Match.bashes.append(bash)
	CombatResolver.resolve_bash(bash, 2)
	check(Match.get_property(physical()).value == 1, "Bash contact triggers Ironhide exactly once even if it dies in the exchange")

## Boolean conditions distinguish empty sets, domain errors and immutable historical facts.
func test_conditions() -> void:
	fixture()
	var empty := Selectors.Literal.new(TargetRef.Kind.UNIT, [])
	var ctx := RuleContext.new(TargetRef.unit(0))
	check(not Condition.Matches.new(empty).test(ctx), "ANY empty is false")
	check(Condition.Matches.new(empty, Condition.Matches.Mode.NONE).test(ctx), "NONE empty is true")
	check(not Condition.Matches.new(empty, Condition.Matches.Mode.ALL, QuerySelector.new()).test(ctx), "Nonempty ALL empty is false")
	var invalid := Condition.Compare.new(QuerySelector.new(), Condition.Compare.Op.EQ, 0)
	check(not Condition.Not.new(invalid).test(ctx) and not ctx.error.is_empty(), "NOT cannot turn a type error into a valid condition")
	var event := EffectEvent.new(&"test", TargetRef.unit(0), TargetRef.unit(2), {"nested": [TargetRef.unit(1)]})
	event.data.nested[0].id = 2
	check(event.data.nested[0].id == 1, "Nested history references cannot be edited through public event data")

## Deployment owns its token until the unit's on-deploy target choice is resolved.
func test_deploy_choice() -> void:
	fixture()
	Match.army[0].t_state = Enum.t_state.UNDEPLOYED
	Match.army[0].ihx = -1
	Match.army[0].type = Enum.type.HERO
	Match.army[0].deploy_regions = [Enum.region.FRONT]
	Match.army[1].actual_life = 6
	Match.players[1].has_deployed = false
	var event := Effect.EventPhrase.observe(&"deploy", Selectors.Self.new(), QuerySelector.new(TargetRef.Kind.HEX), TargetRef.Kind.UNIT, TargetRef.Kind.HEX)
	Match.army[0].trigger_effects.append(Effect.new(null, event, grant(1, Effect.Phrase.TargetMode.CHOOSE_ONE)))
	check(Match.deploy(0, 0), "A legal deployment captures its own trigger")
	check(Match.rules_runner.active != null and Match.players[1].actions_remaining == 3, "Deployment completion waits for its trigger choice")
	check(not Match.finish_action(1), "Public token completion cannot interrupt a pending trigger")
	Match.rules_runner.active.current.choose(physical())
	check(Match.players[1].actions_remaining == 2 and Match.get_property(physical()).value == 1, "Deploy finishes exactly once after its followup")

## An early combat trigger suspends later attacks, and new delayed attacks cannot join this window.
func test_combat_pause() -> void:
	fixture()
	var event := pattern(&"hit")
	Match.army[0].trigger_effects.append(Effect.new(null, event, grant(1, Effect.Phrase.TargetMode.CHOOSE_ONE)))
	CombatResolver.declare_bow(TargetRef.unit(0), TargetRef.hex(2), 1, 2, false, false)
	CombatResolver.declare_fire(TargetRef.unit(0), TargetRef.hex(2), 9, false, false)
	var fire := Match.pending_attacks[0]
	Match.active_player = 2
	Match.phase = Match.Phase.COMBAT_RESOLVE
	CombatResolver.resolve_window(2)
	check(Match.rules_runner.active != null and not fire.resolved, "Bow's triggered target choice suspends later Fire")
	check(Match.army[2].actual_life == 3, "Bow damage is finalized before its Hit followup starts")
	Match.rules_runner.active.current.cancel()
	check(Match.rules_runner.active != null, "Mandatory free trigger cannot be skipped with Escape")
	Match.rules_runner.active.current.choose(physical())
	check(fire.resolved and Match.army[2].t_state == Enum.t_state.DEFEATED, "Combat resumes at the following attack after the choice")
	fixture()
	var targets := Selectors.Literal.new(TargetRef.Kind.HEX, [TargetRef.hex(2)])
	var fire_phrase := Effect.ConsequencePhrase.new(Selectors.Self.new(), Verbs.fire(1), targets, Effect.Phrase.TargetMode.ALL)
	Match.army[0].trigger_effects.append(Effect.new(null, pattern(&"hit"), fire_phrase))
	CombatResolver.declare_bow(TargetRef.unit(0), TargetRef.hex(2), 1, 2, false, false)
	Match.active_player = 2
	Match.phase = Match.Phase.COMBAT_RESOLVE
	CombatResolver.resolve_window(2)
	check(Match.pending_attacks.size() == 1 and not Match.pending_attacks[0].resolved, "A triggered delayed Fire waits for a later window")

## Records a marker through a normal consequence verb for ordering assertions.
func record_marker(_source: TargetRef, _target: TargetRef, label: String) -> bool:
	trace.append(label)
	return true

## Builds a marker phrase without changing the rules runner or bypassing phrase execution.
func marker(label: String) -> Effect.ConsequencePhrase:
	var verb := Effect.Verb.new(&"marker", record_marker, Callable(), TargetRef.Kind.UNIT, TargetRef.Kind.UNIT, [label])
	return Effect.ConsequencePhrase.new(Selectors.Self.new(), verb, Selectors.Self.new(), Effect.Phrase.TargetMode.ALL)

## A whole consequence bundle finishes before nested events, then resumes the next sibling.
func test_nested_bundles() -> void:
	fixture()
	var steps := Effect.ConsequenceSequence.new([grant(), marker("bundle finished")])
	Match.army[0].trigger_effects.append(Effect.new(null, pattern(&"test"), steps))
	Match.army[0].trigger_effects.append(Effect.new(null, pattern(&"test"), marker("sibling")))
	var counter_event := Effect.EventPhrase.observe(&"change_counter", Selectors.Self.new(),
		Selectors.PropertyOf.new(Selectors.Self.new(), UnitInfo.PHYSICAL_COUNTER), TargetRef.Kind.UNIT, TargetRef.Kind.PROPERTY)
	Match.army[0].trigger_effects.append(Effect.new(null, counter_event, marker("nested")))
	emit_test(&"test")
	check(trace == ["bundle finished", "nested", "sibling"], "Nested followups respect consequence bundles and sibling order")

## Uses the real Board adapter to verify runner-owned phrase and optional confirmation routing.
## Disables only the graphical acknowledgement/animation gates so this focused routing test remains synchronous.
func test_board_controls() -> void:
	fixture()
	var board: GuerraBoard = load("res://scenes/board/board.tscn").instantiate()
	add_child(board)
	Match.rules_runner.trigger_acknowledgements_enabled = false
	Match.rules_runner.presentation_busy_query = Callable()
	var effect := Effect.new(null, pattern(&"test"), grant(1, Effect.Phrase.TargetMode.CHOOSE_ONE))
	effect.policy = Effect.Policy.OPTIONAL
	Match.army[0].trigger_effects.append(effect)
	emit_test(&"test")
	check(board.confirm_button.visible, "Board displays effect-level confirmation before a phrase exists")
	board.confirm_button.pressed.emit()
	check(board.selection == Match.rules_runner.active.current, "Board attaches the retained triggered phrase")
	board.selection.choose(physical())
	check(board.selection == null and board.effect_execution == null, "Board releases a completed managed execution")
	Match.army[0].trigger_effects.clear()
	Match.army[0].trigger_effects.append(Effect.new(null, pattern(&"stun"), grant(1, Effect.Phrase.TargetMode.CHOOSE_ONE)))
	Match.rules_runner.submit(Effect.new(Collection.action_cost(), null, grant()), TargetRef.unit(0))
	var parent := board.effect_execution
	board.selection.choose(TargetRef.unit(0))
	check(board.effect_execution != parent and board.effect_execution.captured_trigger, "Board switches to the cost followup's execution")
	board.selection.choose(physical())
	check(parent.status == EffectExecution.Status.SUCCEEDED and board.effect_execution == null, "Board restores then releases the paid parent without duplicate signal connections")
	board.free()
