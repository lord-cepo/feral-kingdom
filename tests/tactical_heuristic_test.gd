extends Node

const Heuristic = preload("res://scripts/runtime/tactical_heuristic.gd")
var checks := 0
var failures := 0


## Runs focused read-only ranking fixtures once the Match autoload is ready.
func _ready() -> void:
	_run.call_deferred()


## Exercises unreturned lethal Bash, inactivity, retaliation, and separate
## physical/magical damage rules, then checks a dodge against a queued attack.
func _run() -> void:
	Match.reset_combat()
	Match.army.clear()
	Match.map.clear()
	for index in 5:
		Match.map.append(HexInfo.new(index, Vector2i(index, 0), Enum.region.STARTING, Enum.side.P1, 0))
	var hero := _unit(1, 0, 20)
	hero.type = Enum.type.HERO
	var weak := _unit(1, -1, 1)
	var strong := _unit(1, -1, 5)
	var enemy := _unit(2, 4, 10)
	enemy.effects.append(Collection.movement(1))
	var heuristic := Heuristic.new()
	heuristic.weights.health = 10000.0
	var options := [
		{"kind": "deploy", "unit": strong.iun, "hex": 3},
		{"kind": "deploy", "unit": weak.iun, "hex": 1},
	]
	var decision := {"player": 1, "options": options}
	_check(heuristic.rank(decision) == [1], "Safety outranks a much larger health score")
	_check(strong.ihx == -1 and enemy.actual_life == 10, "Forecasting changes neither position nor life")
	enemy.active = false
	_check(heuristic.rank(decision) == [0, 1], "An inactive costed attacker does not threaten the deployment")

	strong.t_state = Enum.t_state.DEPLOYED
	strong.ihx = 3
	strong.effects.append(Collection.bow_DR(3, 1))
	enemy.active = true
	enemy.effects.assign([Collection.bow_DR(3, 1)])
	_check(_risk(heuristic, strong, true) == Heuristic.Exposure.UNANSWERED_HIT,
		"A unit that paid self-Stun cannot answer with its own costed Bow")
	_check(_risk(heuristic, strong, false) == Heuristic.Exposure.ANSWERED_HIT,
		"A ready unit can answer the ranged attacker")
	hero.effects.append(Collection.bow_DR(3, 4))
	_check(_risk(heuristic, strong, true) == Heuristic.Exposure.ANSWERED_HIT,
		"A different ready ally can answer the attacker")
	hero.active = false
	enemy.effects.assign([Collection.fire_DR(3, 1)])
	_check(_risk(heuristic, strong, true) == Heuristic.Exposure.SAFE,
		"Nonlethal Fire adds no partial injury")
	enemy.effects.assign([Collection.cannon_DR(3, 1)])
	_check(_risk(heuristic, strong, true) == Heuristic.Exposure.UNANSWERED_HIT,
		"Cannon can cause lasting magical injury despite the regional physical bonus")
	_check_pending_dodge(heuristic, hero, strong, enemy)
	_check_material_cost(heuristic)
	print("Tactical heuristic: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)


## Checks that a legal move avoids an already declared Bow and that a stale
## victim identity never creates a dodge preference for the current occupant.
func _check_pending_dodge(heuristic: Heuristic, ally: UnitInfo, victim: UnitInfo, enemy: UnitInfo) -> void:
	ally.active = true
	ally.effects.assign([Collection.movement(1)])
	victim.active = true
	victim.ihx = 2
	victim.effects.assign([Collection.movement(1)])
	enemy.effects.clear()
	var attack := BowAttack.new()
	attack.owner = enemy.player
	attack.source_id = enemy.iun
	attack.origin_hex = enemy.ihx
	attack.target_hex = victim.ihx
	attack.target_unit_id = victim.iun
	attack.amount = 3
	Match.pending_bow_attacks.append(attack)
	var decision := {"player": victim.player, "options": [
		{"kind": "effect", "unit": ally.iun, "slot": 0},
		{"kind": "effect", "unit": victim.iun, "slot": 0},
	]}
	_check(heuristic.rank(decision) == [1] and heuristic.can_avoid_pending,
		"Leaving the targeted hex takes priority over moving an unrelated ally")
	_check(victim.ihx == 2 and victim.actual_life == 5 and not attack.resolved,
		"Dodge ranking leaves the live position and attack intact")
	attack.target_unit_id = ally.iun
	heuristic.rank(decision)
	_check(not heuristic.can_avoid_pending, "A different original victim creates no need to dodge")
	Match.pending_bow_attacks.clear()


## Checks that the command ranker distinguishes material payments from
## ordinary self-Stun, including sacrifice bundled with self-Stun.
func _check_material_cost(heuristic: Heuristic) -> void:
	var ordinary := Collection.movement(1)
	var warrior := SynergyCatalogue.tamia_warrior(1)
	_check(heuristic._material_cost(ordinary) == 0.0, "Ordinary activity is not a material cost")
	_check(heuristic._material_cost(warrior.effects[1]) > 0.0,
		"Tamia's bundled sacrifice reduces the command's value before the cost picker")


## Builds a stable field or reserve identity for _run()'s read-only forecasts.
func _unit(owner: int, hex: int, life: int) -> UnitInfo:
	var unit := UnitInfo.new()
	unit.iun = Match.army.size()
	unit.player = owner
	unit.ihx = hex
	unit.t_state = Enum.t_state.DEPLOYED if hex >= 0 else Enum.t_state.UNDEPLOYED
	unit.actual_life = life
	unit.max_life = life
	Match.army.append(unit)
	return unit


## Refreshes the root cache and reads the same exposure tier used for ordering.
func _risk(heuristic: Heuristic, unit: UnitInfo, spent: bool) -> int:
	heuristic.rank({"player": unit.player, "options": []})
	return heuristic._worst_exposure(heuristic._profile(unit), unit.ihx, spent)


## Counts one forecast assertion for the focused test scene.
func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
