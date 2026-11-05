extends Node

var checks := 0
var failures := 0
var events: Array[EffectEvent] = []

## Headless scene runs each new rat rule, Disable, terminal legality and life provenance through shared production entry points.
func _ready() -> void:
	Match.action_event.connect(func(event: EffectEvent) -> void: events.append(event))
	test_reset()
	test_return_to_hand()
	test_return_choice_and_bash()
	test_stun_preserves_counters()
	test_dark_mage()
	test_wild_rat()
	test_musketeer()
	test_thief()
	test_warrior()
	test_pikeman()
	test_swordsman()
	test_disable()
	test_no_actions()
	test_life_provenance()
	test_copy_categories()
	test_swordsman_non_flee()
	test_disable_does_not_trigger_death()
	print("Rat effects: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)

## Board Return preserves acquired state, emits one friendly synergy, and rejects off-board/repeated choices without death/reset events.
func test_return_to_hand() -> void:
	fixture()
	var warrior := add(CardCatalogue.rat_warrior(1), 0)
	var friend := plain(1, 1)
	var enemy := plain(2, 2)
	friend.actual_life = 2
	counter(friend, &"physical").value = 3
	counter(friend, &"temp_magical").value = 4
	counter(friend, &"stun").value = 2
	var source := TargetRef.unit(warrior.iun)
	var target := TargetRef.unit(friend.iun)
	var definitions := friend.effects.duplicate()
	check(Action.return_to_hand(source, target), "Return accepts a deployed ally")
	check(friend.t_state == Enum.t_state.UNDEPLOYED and friend.ihx == -1 and not friend.active and friend.player == 1, "Return enters owner's hand inactive with stable identity")
	check(friend.actual_life == 2 and friend.max_life == 5 and friend.effects == definitions, "Return preserves wounds and abilities")
	check(counter(friend, &"physical").value == 3 and counter(friend, &"temp_magical").value == 4 and counter(friend, &"stun").value == 2, "Return preserves counters rather than resetting")
	check(counter(warrior, &"Soul").value == 1, "Real board Return awards one friendly Soul")
	check(not Action.return_to_hand(source, target) and counter(warrior, &"Soul").value == 1, "Repeated Return cannot publish another occurrence")
	check(Action.return_to_hand(source, TargetRef.unit(enemy.iun)) and enemy.player == 2, "Unrestricted Return accepts enemy and preserves its owner")
	check(counter(warrior, &"Soul").value == 1, "Enemy board Return does not award friendly Soul")
	enemy.t_state = Enum.t_state.DEFEATED
	check(not Action.can_return_to_hand(source, TargetRef.unit(enemy.iun)), "Return cannot recover a defeated unit")
	check(not Action.can_return_to_hand(source, TargetRef.hex(0)), "Return requires a unit identity")
	check(events.filter(func(event: EffectEvent) -> bool: return event.action == &"return_to_hand").size() == 2, "Exactly one event per successful board Return")
	check(not events.any(func(event: EffectEvent) -> bool: return event.action in [&"die", &"reset", &"revive", &"deploy", &"flee"]), "Return does not invent other zone actions or Flee")
	check(Action.can_return_to_hand(source, source), "Return can select self")
	var hero := plain(2, 3)
	hero.type = Enum.type.HERO
	check(Action.return_to_hand(source, TargetRef.unit(hero.iun)) and Match.winner == 0, "Returning a hero is not defeating it")

## Managed Return uses selector ownership, exact UNIT choice and standard cost policy; leaving a Bash cancels it without Flee.
func test_return_choice_and_bash() -> void:
	fixture()
	var actor := plain(1, 0)
	var ally := plain(1, 1)
	var enemy := plain(2, 1)
	var bash := BashInfo.new()
	bash.attacker_id = enemy.iun
	bash.defender_id = ally.iun
	bash.target_hex = 1
	Match.bashes.append(bash)
	var friendly := QuerySelector.new()
	friendly.relative_owner = Enum.YOU
	var consequence := Effect.ConsequencePhrase.new(Selectors.Self.new(), Verbs.return_to_hand(), friendly)
	var effect := Collection.with_action_policy(consequence)
	check(Match.rules_runner.submit(effect, TargetRef.unit(actor.iun)), "Authored Return submits through normal command path")
	check(choose(TargetRef.unit(actor.iun)), "Return pays ordinary activity cost")
	check(not choose(TargetRef.unit(enemy.iun)) and enemy.ihx == 1, "Friendly selector rejects enemy sharing the target hex")
	check(choose(TargetRef.unit(ally.iun)), "Return chooses the exact friendly participant")
	check(ally.t_state == Enum.t_state.UNDEPLOYED and enemy.t_state == Enum.t_state.DEPLOYED, "Return affects only selected identity on shared hex")
	check(bash.resolved and Match.bashes.is_empty(), "Return immediately cancels departed Bash")
	check(counter(actor, &"stun").value == 1 and Match.players[1].actions_remaining == 2, "Return pays one self-Stun and one player action")
	check(not events.any(func(event: EffectEvent) -> bool: return event.action == &"flee"), "Off-board departure does not trigger Flee")

## Hostile Stun changes activity and adds duration only; allies, off-board targets and invalid amounts never trigger it.
func test_stun_preserves_counters() -> void:
	fixture()
	var actor := plain(1, 0)
	var victim := add(CardCatalogue.rat_warrior(2), 1)
	var source := TargetRef.unit(actor.iun)
	var target := TargetRef.unit(victim.iun)
	var values := {&"physical": 2, &"magical": -1, &"temp_physical": 3, &"temp_magical": 4, &"Soul": 5}
	for key in values: counter(victim, key).value = values[key]
	counter(victim, &"stun").value = 1
	check(Action.stun(source, target, 2, 1, false), "Hostile Stun succeeds in range")
	check(not victim.active and counter(victim, &"stun").value == 3, "Stun deactivates and adds requested duration")
	for key in values: check(counter(victim, key).value == values[key], "Stun preserves %s" % key)
	check(Action.stun(source, target, 1, 1, false) and counter(victim, &"stun").value == 4, "Inactive recipient can receive additional Stun")
	var before := events.size()
	check(not Action.stun(source, source, 1, 1, false), "Stun rejects self/allied recipient")
	check(not Action.stun(source, target, 0, 1, false) and not Action.stun(source, target, 1, 0, false), "Zero amount and out-of-range Stun do not execute")
	victim.t_state = Enum.t_state.UNDEPLOYED
	victim.ihx = -1
	check(not Action.stun(source, target, 1, 1, false) and events.size() == before, "Off-board Stun and other rejected attempts emit nothing")

## Records semantic failures without preventing independent scenarios from running.
func check(value: bool, message: String) -> void:
	checks += 1
	if value: return
	failures += 1
	push_error(message)

## Resets runner work and resources; each scenario owns its identities and a straight five-hex board.
func fixture() -> void:
	Match.reset_combat()
	Match.rules_runner.trigger_acknowledgements_enabled = false
	Match.rules_runner.presentation_busy_query = Callable()
	Match.army.clear()
	Match.map.clear()
	events.clear()
	for index in 5:
		Match.map.append(HexInfo.new(index, Vector2i(index, 0), Enum.region.STARTING, Enum.side.P1, 0))
	for player in Match.players.values():
		player.actions_remaining = 3
		player.action_allowance = 1
		player.deployments_remaining = 3
		player.has_deployed = true
		player.next_turn_actions = 0

## Adds a printed card with a stable ID; negative hex means in hand, positive hex means active deployed.
func add(unit: UnitInfo, hex_id: int = 0) -> UnitInfo:
	unit.iun = Match.army.size()
	unit.ihx = hex_id
	unit.t_state = Enum.t_state.DEPLOYED if hex_id >= 0 else Enum.t_state.UNDEPLOYED
	unit.active = hex_id >= 0
	unit.ensure_implicit_walk()
	unit.capture_printed_state()
	Match.army.append(unit)
	return unit

## Supplies ordinary non-triggering targets so each scenario isolates the effect under test.
func plain(owner: int = 2, hex_id: int = 1) -> UnitInfo:
	var unit := UnitInfo.new()
	unit.player = owner
	unit.name = "Target %d" % Match.army.size()
	unit.uuid = "target-%d" % Match.army.size()
	unit.max_life = 5
	unit.actual_life = 5
	unit.deploy_regions = [Enum.region.STARTING]
	return add(unit, hex_id)

## Safely answers the runner's exact current choice; absent choices produce assertions rather than null dereferences.
func choose(ref: TargetRef) -> bool:
	var run := Match.rules_runner.active
	if run == null or run.current == null:
		check(false, "Expected a retained target choice")
		return false
	return run.current.choose(ref)

## Resolves stored counters through the same property identity used by effects.
func counter(unit: UnitInfo, key: StringName) -> Prop:
	return Match.get_property(TargetRef.property(TargetRef.unit(unit.iun), key))

## Reset restores printed definitions/resources in place and must not act as Revive or emit death/return.
func test_reset() -> void:
	fixture()
	var source := plain(1, 0)
	var target := add(CardCatalogue.rat_warrior(2), 1)
	target.max_life += 2
	target.actual_life = 1
	target.active = false
	counter(target, &"Soul").value = 4
	counter(target, &"physical").value = 2
	check(Action.reset_unit(TargetRef.unit(source.iun), TargetRef.unit(target.iun)), "Reset accepts enemy units")
	check(target.max_life == 3 and target.actual_life == 3 and target.ihx == 1 and not target.active, "Reset heals printed life without moving or activating")
	check(counter(target, &"Soul").value == 0 and counter(target, &"physical").value == 0, "Reset removes resource and modifier counters")
	target.t_state = Enum.t_state.DEFEATED
	target.ihx = -1
	check(Action.reset_unit(TargetRef.unit(source.iun), TargetRef.unit(target.iun)) and target.t_state == Enum.t_state.DEFEATED, "Reset does not revive a defeated target")
	check(not events.any(func(e: EffectEvent) -> bool: return e.action in [&"die", &"return_to_hand"]), "Reset creates neither Die nor Return")

## Dark Mage death retains a CHOOSE_ONE Reset after its source leaves the board, including enemy recipients.
func test_dark_mage() -> void:
	fixture()
	var mage := add(CardCatalogue.rat_dark_mage(1))
	var enemy := plain()
	enemy.actual_life = 1
	Match.defeat(TargetRef.unit(mage.iun))
	check(Match.rules_runner.busy() and mage.t_state == Enum.t_state.DEFEATED, "Dark Mage death waits for a Reset choice")
	check(choose(TargetRef.unit(enemy.iun)) and enemy.actual_life == 5, "Captured death source resets the chosen enemy")
	check(not Match.rules_runner.busy(), "Dark Mage trigger completes exactly once")

## Wild Rat amplifies friendly death abilities, stacks additively and never duplicates enemy deaths or emits extra Die events.
func test_wild_rat() -> void:
	fixture()
	add(CardCatalogue.wild_rat(1), 0)
	add(CardCatalogue.wild_rat(1), 1)
	var dying := add(CardCatalogue.pine_processionary(1), 2)
	var before := Match.players[1].deployments_remaining
	Match.defeat(TargetRef.unit(dying.iun))
	check(Match.players[1].deployments_remaining == before + 6, "Two friendly Wild Rats add two independent +2 deploy death activations")
	check(events.filter(func(e: EffectEvent) -> bool: return e.action == &"die").size() == 1, "Death amplification does not duplicate the death occurrence")
	var enemy := add(CardCatalogue.pine_processionary(2), 3)
	before = Match.players[2].deployments_remaining
	Match.defeat(TargetRef.unit(enemy.iun))
	check(Match.players[2].deployments_remaining == before + 2, "Friendly amplification does not affect opposing death triggers")
	check(Match.army[0].trigger_effects.is_empty(), "Wild Rat's amplifier is static, not its own death trigger")
	fixture()
	var amplifier := add(CardCatalogue.wild_rat(1))
	amplifier.trigger_effects.append(Collection.pine_processionary_trigger())
	before = Match.players[1].deployments_remaining
	Match.defeat(TargetRef.unit(amplifier.iun))
	check(Match.players[1].deployments_remaining == before + 4, "A copied death trigger is amplified on the dying amplifier before removal")

## Musketeer enemy-death watcher chooses only another friendly defeated nonhero and emits Return for Warrior watchers.
func test_musketeer() -> void:
	fixture()
	add(CardCatalogue.rat_musketeer(1), 0)
	var friend := plain(1, -1)
	friend.t_state = Enum.t_state.DEFEATED
	friend.actual_life = 0
	var enemy := plain(2, 2)
	Match.defeat(TargetRef.unit(enemy.iun))
	check(not choose(TargetRef.unit(enemy.iun)), "Musketeer cannot revive the opposing casualty")
	check(choose(TargetRef.unit(friend.iun)), "Musketeer chooses a friendly defeated unit")
	check(friend.t_state == Enum.t_state.UNDEPLOYED and friend.actual_life == friend.max_life and not friend.active, "Revive returns full-health inactive card to hand")
	check(events.filter(func(e: EffectEvent) -> bool: return e.action == &"return_to_hand").size() == 1, "Revive emits one Return occurrence")
	friend.type = Enum.type.HERO
	friend.t_state = Enum.t_state.DEFEATED
	check(not Action.can_revive(TargetRef.unit(0), TargetRef.unit(friend.iun)), "Revive excludes heroes")

## Thief Wound offers effect properties; copying keeps the donor definition and Reset removes the acquired effect.
func test_thief() -> void:
	fixture()
	var thief := add(CardCatalogue.rat_thief(1), 0)
	var victim := add(CardCatalogue.rat_warrior(2), 1)
	var option: EffectOption
	for candidate in victim.effect_options():
		if candidate.category == &"trigger_effects": option = candidate
	Match.action_event.emit(EffectEvent.new(&"wound", TargetRef.unit(thief.iun), TargetRef.unit(victim.iun), {"damage": 1}))
	check(option != null and choose(TargetRef.property(TargetRef.unit(victim.iun), option.name)), "Thief chooses one wounded target effect")
	check(thief.trigger_effects.size() == 2 and victim.trigger_effects.size() == 1, "Copy duplicates rather than stealing the donor's trigger")
	check(counter(thief, &"Soul") != null and counter(thief, &"Soul").value == 0, "Copied Soul rule gets a zero-valued resource, not donor counters")
	Action.reset_unit(TargetRef.unit(thief.iun), TargetRef.unit(thief.iun))
	check(thief.trigger_effects.size() == 1 and thief.copied_effects.is_empty(), "Reset removes acquired triggers and provenance")
	check(not Action.can_copy_effect(TargetRef.unit(thief.iun), TargetRef.unit(victim.iun)), "Copy requires a chosen effect property, not a whole unit")

## Warrior watches friendly Returns, not enemy Returns, and atomically spends two Soul plus activity and one player action.
func test_warrior() -> void:
	fixture()
	var warrior := add(CardCatalogue.rat_warrior(1), 0)
	var friend := plain(1, -1)
	var enemy := plain(2, -1)
	Match.action_event.emit(EffectEvent.new(&"return_to_hand", TargetRef.unit(enemy.iun), TargetRef.unit(enemy.iun)))
	check(counter(warrior, &"Soul").value == 0, "Enemy Return does not award Soul")
	for repeat in 2: Match.action_event.emit(EffectEvent.new(&"return_to_hand", TargetRef.unit(friend.iun), TargetRef.unit(friend.iun)))
	check(counter(warrior, &"Soul").value == 2, "Friendly Return awards one Soul per occurrence")
	var effect := warrior.effects[1]
	var before := Match.players[1].deployments_remaining
	check(Match.rules_runner.submit(effect, TargetRef.unit(warrior.iun)), "Warrior can submit payable Soul conversion")
	check(choose(TargetRef.unit(warrior.iun)), "Warrior chooses its activity payment")
	check(choose(TargetRef.property(TargetRef.unit(warrior.iun), &"Soul")), "Warrior chooses two-Soul payment")
	check(Match.players[1].deployments_remaining == before + 1 and Match.players[1].actions_remaining == 2, "Soul conversion grants one deployment and consumes exactly one action")
	check(counter(warrior, &"Soul").value == 0 and counter(warrior, &"stun").value == 1 and not warrior.active, "Both Soul and activity are paid once")
	check(not Match.rules_runner.command_available(effect, TargetRef.unit(warrior.iun)), "Unpayable Soul conversion is not a legal action")
	warrior.active = true
	counter(warrior, &"Soul").value = 1
	check(not Match.rules_runner.command_available(effect, TargetRef.unit(warrior.iun)) and warrior.active and counter(warrior, &"Soul").value == 1, "Insufficient Soul rejects without partial activity payment")

## Pikeman reads signed remaining-deployment difference live, without accumulating counters or increasing control strength.
func test_pikeman() -> void:
	fixture()
	var pike := add(CardCatalogue.rat_pikeman(1))
	Match.players[1].deployments_remaining = 5
	Match.players[2].deployments_remaining = 2
	check(pike.state_effects[0].evaluate(RuleContext.new(TargetRef.unit(pike.iun))).x == 3, "Pikeman gains positive deployment difference")
	Match.players[1].deployments_remaining = 0
	check(pike.state_effects[0].evaluate(RuleContext.new(TargetRef.unit(pike.iun))).x == -2, "Pikeman supports negative deployment difference")
	check(pike.counter_modifiers() == Vector2i.ZERO and pike.control_bonus == 0, "Derived difference changes neither counters nor control contribution")

## Swordsman tests actual Bash participant identities: only a living original defender leaving rewards a next-own-Start action.
func test_swordsman() -> void:
	fixture()
	var sword := add(CardCatalogue.rat_swordsman(1), 0)
	var enemy := plain(2, 1)
	check(CombatResolver.move_unit(TargetRef.unit(sword.iun), TargetRef.hex(1), 2, false, true), "Swordsman enters an enemy hex as attacker")
	check(sword.state_effects[0].evaluate(RuleContext.new(TargetRef.unit(sword.iun))).x == 1, "Bashing Swordsman gets its physical contribution")
	enemy.ihx = 2
	CombatResolver.cancel_dodged_bashes(enemy.iun)
	check(Match.players[1].next_turn_actions == 1, "Original defender leaving schedules one action")
	var cancelled: EffectEvent
	for event in events:
		if event.action == &"bash" and event.data.get("dodged", false): cancelled = event
	var ordinary := Effect.EventPhrase.observe(&"bash", Selectors.Self.new(), QuerySelector.new())
	check(cancelled != null and not ordinary.matches(RuleContext.new(TargetRef.unit(sword.iun), cancelled), cancelled), "Ordinary Bash triggers still reject the cancelled encounter")
	Match.start_turn(1)
	check(Match.players[1].actions_remaining == 2 and Match.players[1].next_turn_actions == 0, "Next Start consumes the bonus once")
	Match.start_turn(1)
	check(Match.players[1].actions_remaining == 1, "The action bonus does not recur")
	fixture()
	sword = add(CardCatalogue.rat_swordsman(1), 0)
	enemy = plain(2, 1)
	CombatResolver.move_unit(TargetRef.unit(sword.iun), TargetRef.hex(1), 2, false, true)
	sword.ihx = 0
	CombatResolver.cancel_dodged_bashes(sword.iun)
	check(Match.players[1].next_turn_actions == 0, "Attacker leaving never earns flee reward")

## Disable uses the normal off-board CHOOSE_ONE boundary, respects owner filters and is neither a death nor a Return.
func test_disable() -> void:
	fixture()
	var source := plain(1, 0)
	var enemy := plain(2, -1)
	var friend := plain(1, -1)
	var hand := QuerySelector.new()
	hand.state = Enum.t_state.UNDEPLOYED
	hand.relative_owner = Enum.OPP
	var effect := Effect.new(null, null, Effect.ConsequencePhrase.new(Selectors.Self.new(), Verbs.disable(), hand))
	check(Match.rules_runner.submit(effect, TargetRef.unit(source.iun)), "Disable offers an enemy-hand choice")
	check(not choose(TargetRef.unit(friend.iun)) and choose(TargetRef.unit(enemy.iun)), "Disable ownership stays in the selector")
	check(enemy.t_state == Enum.t_state.DEFEATED and enemy.actual_life == 5 and enemy.ihx == -1, "Disable preserves life and moves hand card to defeated")
	check(not Action.can_disable(TargetRef.unit(source.iun), TargetRef.unit(enemy.iun)) and not Action.can_disable(TargetRef.unit(source.iun), TargetRef.unit(source.iun)), "Already defeated and deployed targets are illegal")
	check(not events.any(func(e: EffectEvent) -> bool: return e.action in [&"die", &"return_to_hand"]), "Disable does not fire death or Return triggers")
	friend.type = Enum.type.HERO
	check(Action.disable(TargetRef.unit(source.iun), TargetRef.unit(friend.iun)) and Match.winner == 2, "Disabling a hero follows the hero-defeat loss rule")

## No-action loss includes deployments, unavailable target sets and pending-choice protection; legal commands do not mutate resources.
func test_no_actions() -> void:
	fixture()
	var unit := plain(1, 0)
	check(Match.has_legal_action() and unit.active and Match.players[1].actions_remaining == 3, "Legality probes find Walk without paying or deactivating")
	unit.active = false
	Match._check_no_legal_actions()
	check(Match.winner == 2, "No deployment and no usable command loses")
	fixture()
	unit = plain(1, 0)
	unit.active = false
	plain(1, -1)
	check(Match.has_legal_action(), "A legal hand deployment prevents loss")
	Match.players[1].deployments_remaining = 0
	check(not Match.has_legal_action(), "No remaining deployments removes that escape")
	Match.rules_runner.begin_boundary()
	Match._check_no_legal_actions()
	check(Match.winner == 0, "Pending rule boundary prevents premature defeat")
	Match.rules_runner.end_boundary()
	Match._check_no_legal_actions()
	check(Match.winner == 2, "Settled boundary permits no-action defeat")
	fixture()
	unit = plain(1, 0)
	unit.effects.clear()
	var empty := Selectors.Literal.new(TargetRef.Kind.UNIT, [])
	unit.effects.append(Effect.new(null, null, Effect.ConsequencePhrase.new(Selectors.Self.new(), Verbs.disable(), empty)))
	check(not Match.has_legal_action(), "An ability with no legal targets does not prevent defeat")

## Maximum-life effects retain their responsible unit, survive in-memory snapshot round trips and disappear on Reset.
func test_life_provenance() -> void:
	fixture()
	var source := plain(1, 0)
	var target := plain(2, 1)
	check(Action.up_life(TargetRef.unit(target.iun), TargetRef.unit(target.iun), 0, 2), "Existing life-upgrade verb acts on its deployed SELF")
	check(target.max_life == 7 and target.max_life_changes.size() == 1, "Maximum-life upgrade records its actual delta")
	check(target.max_life_breakdown().has("+2 " + target.name), "Breakdown names the responsible unit")
	var store = preload("res://scripts/runtime/match_snapshot.gd")
	var saved: Dictionary = store._capture_state()
	target.max_life_changes.clear()
	store._apply_state(saved)
	check(target.max_life_changes.size() == 1 and target.max_life == 7, "Snapshot restores life attribution without touching user's saved file")
	Action.reset_unit(TargetRef.unit(source.iun), TargetRef.unit(target.iun))
	check(target.max_life == 5 and target.max_life_changes.is_empty(), "Reset restores printed maximum and clears applied sources")

## Copy supports every advertised effect category, retaining donor definitions and independent recipient flags.
func test_copy_categories() -> void:
	fixture()
	var thief := add(CardCatalogue.rat_thief(1))
	var donor := add(CardCatalogue.rat_warrior(2), 1)
	donor.state_effects.append(StateModifier.permanent(2, 0, "Copied state"))
	donor.continuous_effects.append(ContinuousEffect.while_self(null, [Contribution.modifiers(0, 2)]))
	var flag := Prop.new()
	flag.name = "steady"
	flag.increment = Enum.p_increment.FLAG
	flag.value = 1
	donor.props.append(flag)
	var categories: Dictionary = {}
	for option in donor.effect_options():
		if categories.has(option.category): continue
		check(Action.copy_effect(TargetRef.unit(thief.iun), TargetRef.property(TargetRef.unit(donor.iun), option.name)), "Copy accepts category " + String(option.category))
		categories[option.category] = true
	check(categories.size() == 5, "Actions, triggers, states, continuous contributions and passives are all copy choices")
	check(thief.has_effective_flag(&"steady") and donor.has_effective_flag(&"steady"), "Passive Copy leaves original flag intact")
	Action.reset_unit(TargetRef.unit(thief.iun), TargetRef.unit(thief.iun))
	check(not thief.has_effective_flag(&"steady") and donor.has_effective_flag(&"steady"), "Reset removes only recipient's copied flag")

## Forced defender departure is Flee; death and Swordsman being the defender are excluded by encounter identities.
func test_swordsman_non_flee() -> void:
	fixture()
	var sword := add(CardCatalogue.rat_swordsman(1), 0)
	var enemy := plain(2, 1)
	CombatResolver.move_unit(TargetRef.unit(sword.iun), TargetRef.hex(1), 2, false, true)
	var pusher := plain(1, 0)
	check(CombatResolver.displace(TargetRef.unit(pusher.iun), TargetRef.unit(enemy.iun), 1, 1, false, true), "Forced displacement can move the original defender away")
	check(Match.players[1].next_turn_actions == 1, "Forced Flee earns the same next-turn reward")
	fixture()
	sword = add(CardCatalogue.rat_swordsman(1), 0)
	enemy = plain(2, 1)
	CombatResolver.move_unit(TargetRef.unit(sword.iun), TargetRef.hex(1), 2, false, true)
	Match.defeat(TargetRef.unit(enemy.iun))
	check(Match.players[1].next_turn_actions == 0, "Defender death is not Flee")
	fixture()
	sword = add(CardCatalogue.rat_swordsman(1), 1)
	enemy = plain(2, 0)
	CombatResolver.move_unit(TargetRef.unit(enemy.iun), TargetRef.hex(1), 2, false, true)
	enemy.ihx = 0
	CombatResolver.cancel_dodged_bashes(enemy.iun)
	check(Match.players[1].next_turn_actions == 0, "A defending Swordsman does not earn an attacker Flee reward")

## Disable never activates an enemy-death watcher; explicit player ownership and no-candidate outcomes use ordinary selectors.
func test_disable_does_not_trigger_death() -> void:
	fixture()
	var musketeer := add(CardCatalogue.rat_musketeer(1))
	var enemy := plain(2, -1)
	var friend := plain(1, -1)
	friend.t_state = Enum.t_state.DEFEATED
	var query := QuerySelector.new()
	query.owner = Enum.owner.P2
	query.state = Enum.t_state.UNDEPLOYED
	var ctx := RuleContext.new(TargetRef.unit(musketeer.iun))
	var resolved := TargetResolver.resolve(query, TargetRef.Kind.UNIT, ctx)
	check(resolved.error.is_empty() and resolved.candidates.size() == 1 and resolved.candidates[0].id == enemy.iun, "Disable can use an explicit player selector")
	Action.disable(TargetRef.unit(musketeer.iun), TargetRef.unit(enemy.iun))
	check(not Match.rules_runner.busy() and friend.t_state == Enum.t_state.DEFEATED, "Disabled enemy does not activate Musketeer Revive")
