## Opt-in offline regressions for the relay adapter; never contacts the public server.
extends Node

var failures := 0
var checks := 0
var valid_keys: Array = []

## Test fixture entry is run only on explicit TEST requests; restore transport flags before exiting.
func _ready() -> void:
	_test_references()
	_test_armies()
	_test_ownership_and_rejection()
	_test_engine_boundary()
	_test_consumed_failure()
	NetworkSession.online = false
	NetworkSession.authenticated = false
	NetworkSession.room = {}
	NetworkSession.outbox.clear()
	print("Network adapter: %d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures > 0 else 0)

## Record independent assertions without stopping later eligibility/non-trigger checks.
func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(description)

## Stable references survive wire encoding; malformed and nested property hosts never become engine targets.
func _test_references() -> void:
	for ref in [TargetRef.unit(7), TargetRef.hex(3), TargetRef.player(2), TargetRef.match_host(), TargetRef.property(TargetRef.unit(5), &"physical")]:
		var decoded := NetworkSession.decode_ref(NetworkSession.encode_ref(ref))
		_check(decoded != null and decoded.same(ref), "Wire reference round trip preserves kind and identity")
	for invalid in [null, [], {"kind": "unit"}, {"kind": 0, "id": {}}, {"kind": 0, "id": 1.5}, {"kind": 3, "host": {"kind": 3}, "key": "physical"}]:
		_check(NetworkSession.decode_ref(invalid) == null, "Malformed reference rejected")

## Build matching legal armies with one hero; wrong sizes, duplicates, unknown keys and extra heroes are rejected.
func _test_armies() -> void:
	NetworkSession.room = {"settings": {"army_size": 8, "deployments": 8}}
	var keys: Array = []
	var heroes: Array = []
	for unit in CardCatalogue.all_units(1):
		if unit.type == Enum.type.HERO: heroes.append(unit.uuid.trim_suffix("-p1"))
		elif keys.size() < 7: keys.append(unit.uuid.trim_suffix("-p1"))
	keys.append(heroes[0])
	valid_keys = keys.duplicate()
	var army := NetworkSession.make_army([keys, keys])
	_check(army.size() == 16, "Legal saved armies construct both deterministic seats")
	_check(army.size() == 16 and army[0].player == 1 and army[8].player == 2, "Army ownership comes from assigned seats")
	_check(NetworkSession.make_army([keys.slice(0, 7), keys]).is_empty(), "Wrong size rejected")
	var bad := keys.duplicate()
	bad[0] = bad[1]
	_check(NetworkSession.make_army([bad, keys]).is_empty(), "Duplicate card rejected")
	bad[0] = "missing-card"
	_check(NetworkSession.make_army([bad, keys]).is_empty(), "Unknown card rejected")
	bad = keys.duplicate()
	bad[0] = heroes[1]
	_check(NetworkSession.make_army([bad, keys]).is_empty(), "Two heroes rejected")
	_check(NetworkSession.make_army([{}, keys]).is_empty(), "Malformed deck rejected")

## Authenticated seat and revision checks happen before payment; rejected guest actions cannot deploy or spend resources.
func _test_ownership_and_rejection() -> void:
	Match.army.clear()
	var unit := UnitInfo.new()
	unit.player = 1
	unit.iun = 0
	Match.army.append(unit)
	Match.active_player = 1
	NetworkSession.local_player = 1
	NetworkSession.online = true
	NetworkSession.game_loaded = true
	NetworkSession.authenticated = true
	NetworkSession.room = {"players": [{"connected": true}, {"connected": true}]}
	NetworkSession.revision = 4
	NetworkSession.context_id = 2
	var intent := {"kind": "deploy", "unit": 0, "hex": 0, "expected_revision": 4, "context_id": 2}
	_check(NetworkSession._intent_owner(intent) == 1, "Deployment belongs to the unit's active owner")
	NetworkSession._authorize(intent, 2)
	_check(NetworkSession.revision == 4 and unit.ihx == -1, "Guest cannot deploy host unit")
	intent.expected_revision = 3
	NetworkSession._authorize(intent, 1)
	_check(NetworkSession.revision == 4 and unit.ihx == -1, "Stale command does not mutate or advance revision")
	intent.unit = {}
	_check(not NetworkSession._valid_intent(intent), "Malformed command fields rejected before integer conversion")
	_check(not NetworkSession._valid_intent({"kind": "call_method"}), "Unknown command kind rejected")
	Match.active_player = 2
	_check(NetworkSession._intent_owner({"kind": "effect", "unit": 0}) == 0, "Inactive owner's action rejected")
	_check(NetworkSession._intent_owner({"kind": "ack", "player": 2}) == 2, "Acknowledgement must match authenticated sender's seat")

## Accepted deployment uses the real engine once; rejected destinations and guest-side input leave life/resources untouched.
func _test_engine_boundary() -> void:
	NetworkSession.online = false
	NetworkSession.room = {"settings": {"army_size": 8, "deployments": 8}, "players": [{"connected": true}, {"connected": true}]}
	var regions := RegionMap.new()
	regions._generate_hex_grid()
	regions.free()
	_check(Match.start_local_match(NetworkSession.make_army([valid_keys, valid_keys]), 1, 8), "Initialize real selected decks")
	NetworkSession.online = true
	var hero_id := 7
	var legal_hex := -1
	for tile in Match.map:
		if Match.can_deploy(hero_id, tile.hex_id):
			legal_hex = tile.hex_id
			break
	_check(legal_hex >= 0, "Host hero has a legal first deployment")
	var before := Match.players[1].deployments_remaining
	_check(not NetworkSession._execute({"kind": "deploy", "unit": hero_id, "hex": -1}), "Illegal destination rejected by existing engine")
	_check(Match.players[1].deployments_remaining == before, "Illegal intent spends no deployments")
	_check(NetworkSession._execute({"kind": "deploy", "unit": hero_id, "hex": legal_hex}), "Confirmed intent enters existing deployment rules")
	_check(Match.get_unit(hero_id).ihx == legal_hex and Match.players[1].deployments_remaining == before - 1, "Accepted deployment places exact identity and spends once")
	NetworkSession.local_player = 2
	NetworkSession.room.players[0].connected = false
	var after := Match.players[1].deployments_remaining
	_check(not Match.deploy(hero_id, legal_hex), "Disconnected guest input routes without optimistic mutation")
	_check(Match.players[1].deployments_remaining == after, "Rejected guest input does not spend resources again")

## A legal consumed choice can end FAILED after payment; the adapter must confirm that transition rather than silently dropping it.
func _test_consumed_failure() -> void:
	var ref := TargetRef.unit(7)
	var run := EffectExecution.new(null, ref)
	run.cost_paid = true
	var definition := Effect.ConsequencePhrase.new(Selectors.Self.new(), Effect.Verb.new(&"fixture_failure", func(_subject: TargetRef, _target: TargetRef) -> bool: return false, Callable(), TargetRef.Kind.UNIT, TargetRef.Kind.UNIT), Selectors.Self.new())
	var phrase := PhraseExecution.new()
	phrase.begin(definition, run)
	run.current = phrase
	Match.rules_runner.active = run
	_check(NetworkSession._execute({"kind": "choose", "ref": NetworkSession.encode_ref(ref)}), "Consumed failed choice is a confirmed engine transition")
	_check(phrase.status == PhraseExecution.Status.FAILED and run.cost_paid, "Failure state retains already-paid cost state")
	Match.rules_runner.active = null
