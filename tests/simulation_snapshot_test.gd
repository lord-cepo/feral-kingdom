extends Node

const Harness = preload("res://scripts/runtime/headless_match.gd")
const SaveState = preload("res://scripts/runtime/match_snapshot.gd")

var harness := Harness.new()
var failures := 0
var checks := 0


## Runs the headless checkpoint fixture in its own scene. The runner uses the real
## deployment, trigger confirmation, target choice and phase continuation paths.
func _ready() -> void:
	_run.call_deferred()


## Checks that a checkpoint isolates mutable records and that the same decision
## suffix reconstructs a pending opponent-owned trigger on each branch.
func _run() -> void:
	var first := CardCatalogue.squirrel_king(1)
	var second := CardCatalogue.mole_artificer(2)
	var army: Array[UnitInfo] = [first, second]
	if not _check(harness.start(army, 1, 8), "Start the headless fixture"):
		_finish()
		return
	var opening := harness.decision()
	var rng := RandomNumberGenerator.new()
	rng.seed = 712
	for draw in 8:
		_check(harness.sample_option(rng) in opening.options, "Rollout sampler returns a legal opening deployment")
	_check(harness.decision() == opening, "Sampling leaves the live picker and action allowances intact")
	if not _check(harness.submit(1, opening.options[0]), "Deploy the first hero"):
		_finish()
		return

	var physical := TargetRef.property(TargetRef.unit(0), UnitInfo.PHYSICAL_COUNTER)
	Match.get_property(physical).value = 3
	_add_counter(Match.players[1].props, "player_counter", Enum.p_target.PLAYER)
	_add_counter(Match.map[0].props, "hex_counter", Enum.p_target.HEX)
	_add_counter(Match.props, "match_counter", Enum.p_target.STATIC)
	var grant := TimedGrant.modifiers(Match.allocate_timed_grant_id(), TargetRef.unit(0), [2, -1], 1, 99)
	first.timed_grants.append(grant)
	var queued := FireAttack.new()
	queued.source_id = first.iun
	queued.owner = first.player
	queued.origin_hex = first.ihx
	queued.target_hex = first.ihx
	queued.amount = 2
	queued.pierce = true
	queued.declared_turn = Match.turn_number
	queued.outcome = {"preview": {"amount": 2}}
	Match.pending_attacks.append(queued)

	var enemies := QuerySelector.new()
	enemies.relative_owner = Enum.OPP
	var pattern := Effect.EventPhrase.observe(&"deploy", enemies, QuerySelector.new(TargetRef.Kind.HEX),
		TargetRef.Kind.UNIT, TargetRef.Kind.HEX)
	var consequence := Effect.ConsequencePhrase.new(Selectors.Self.new(), Verbs.change_counter(1),
		Selectors.PropertyOf.new(Selectors.Self.new(), UnitInfo.PHYSICAL_COUNTER))
	var trigger := Effect.new(null, pattern, consequence)
	trigger.policy = Effect.Policy.OPTIONAL
	first.trigger_effects.append(trigger)
	var checkpoint := harness.checkpoint()
	if not _check(checkpoint != null, "Capture the settled boundary"):
		_finish()
		return
	var saved_state := JSON.stringify(SaveState._capture_state())
	var next_event := EffectEvent._next_occurrence_id
	var next_grant := Match._next_timed_grant_id
	var deploy := harness.decision()
	var suffix: Array[Dictionary] = [{"player": 2, "option": deploy.options[0]}]

	queued.outcome.preview.amount = 99
	grant.parameters[0] = 99
	Match.get_property(physical).value = 99
	Match.players[1].props[0].value = 99
	Match.map[0].props[0].value = 99
	Match.props[0].value = 99
	Match.turn_number = 99
	Match._next_timed_grant_id = 99
	EffectEvent._next_occurrence_id = 99
	var empty: Array[Dictionary] = []
	if not _check(harness.restore_snapshot(checkpoint, empty), "Restore the boundary after mutations"):
		_finish()
		return
	_check(JSON.stringify(SaveState._capture_state()) == saved_state, "Counters, grants, queued Fire and turn state round-trip")
	_check(Match.pending_attacks[0].outcome.preview.amount == 2, "Nested combat outcome is isolated from branch mutations")
	_check(EffectEvent._next_occurrence_id == next_event and Match._next_timed_grant_id == next_grant,
		"Both rules ID allocators rewind exactly")

	if not _check(harness.restore_snapshot(checkpoint, suffix), "Rebuild the optional trigger from the deployment choice"):
		_finish()
		return
	var confirm := harness.decision()
	if not _check(confirm.get("player") == 1 and Match.active_player == 2 and confirm.options.size() == 2,
			"The pending trigger belongs to the opponent of the active player"):
		_finish()
		return
	_check(harness.checkpoint() == null, "A busy runner retains the previous checkpoint and suffix")
	_check(harness.sample_option(rng) in confirm.options and harness.decision() == confirm,
		"Rollout sampler can draw from an opponent-owned trigger without confirming it")
	_check(harness.submit(1, {"kind": "confirm_effect", "accepted": false}), "Decline the trigger")
	var declined := JSON.stringify(SaveState._capture_state())

	suffix.append({"player": 1, "option": {"kind": "confirm_effect", "accepted": true}})
	if not _check(harness.restore_snapshot(checkpoint, suffix), "Restore and accept the same trigger"):
		_finish()
		return
	var target := harness.decision()
	if not _check(target.get("player") == 1 and target.options.size() == 1, "Rebuild the exact property picker"):
		_finish()
		return
	_check(harness.submit(1, target.options[0]), "Apply the retained consequence")
	_check(Match.get_property(physical).value == 4, "Accepted effect changes the counter once")

	suffix.pop_back()
	_check(harness.restore_snapshot(checkpoint, suffix) and harness.decision() == confirm, "Restore the first branch again")
	_check(harness.submit(1, {"kind": "confirm_effect", "accepted": false}), "Decline after exploring the accepted branch")
	_check(JSON.stringify(SaveState._capture_state()) == declined, "Sibling branch produces the same result in either order")
	_finish()


## Adds one runtime counter on a non-unit host for the checkpoint isolation fixture.
func _add_counter(properties: Array[Prop], key: String, host_kind: Enum.p_target) -> void:
	var counter := Prop.new()
	counter.name = key
	counter.increment = Enum.p_increment.COUNTER
	counter.target = host_kind
	counter.value = 7
	properties.append(counter)


## Records a fixture assertion and returns its result so setup can abort safely.
func _check(condition: bool, message: String) -> bool:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
	return condition


## Reports the fixture result to the repository's headless test runner.
func _finish() -> void:
	print("Simulation snapshot: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
