## Object-authored squirrel, mole and mouse rules; definitions stay reusable and all choices belong to executions.
class_name WoodlandRules
extends RefCounted

## Shared friendly deployed query keeps ownership wording and recipient legality consistent across healing and upgrades.
static func friends() -> QuerySelector:
	var result := QuerySelector.new()
	result.relative_owner = Enum.YOU
	result.state = Enum.t_state.DEPLOYED
	return result

## AC effects collect normal activity and one explicit health payment before any consequence; lethal payments remain legal.
static func life_cost(actual: int, maximum: int = 0) -> Effect.CostBundle:
	return Effect.CostBundle.new([Collection.action_cost(), Effect.CostPhrase.new(Selectors.Self.new(),
		Verbs.pay_life(actual, maximum), Selectors.Self.new())])

## Explorer captures the actual positive current/max components and awards its own physical/magic counters independently.
static func grow_with_friends() -> Effect:
	var event := Effect.EventPhrase.observe(&"life_increase", friends(), QuerySelector.new())
	var physical := Effect.Verb.new(&"change_counter", Action.change_counter, Action.can_change_counter,
		TargetRef.Kind.UNIT, TargetRef.Kind.PROPERTY, [RuleNumber.new(&"actual", "X")])
	var magical := Effect.Verb.new(&"change_counter", Action.change_counter, Action.can_change_counter,
		TargetRef.Kind.UNIT, TargetRef.Kind.PROPERTY, [RuleNumber.new(&"maximum", "Y")])
	return Effect.on_event(event, Effect.ConsequenceSequence.new([
		Effect.ConsequencePhrase.new(Selectors.Self.new(), physical, Selectors.PropertyOf.new(Selectors.Self.new(), UnitInfo.PHYSICAL_COUNTER), Effect.Phrase.TargetMode.ALL),
		Effect.ConsequencePhrase.new(Selectors.Self.new(), magical, Selectors.PropertyOf.new(Selectors.Self.new(), UnitInfo.MAGICAL_COUNTER), Effect.Phrase.TargetMode.ALL)]))

## Doctor spends current life plus activity and chooses one friendly deployed recipient for +1 current/+1 maximum life.
static func doctor_heal() -> Effect:
	return Effect.new(life_cost(1), null, Effect.ConsequencePhrase.new(Selectors.Self.new(), Verbs.up_life(1, 1), friends()))

## Wild Red Squirrel fires an Instant Bow with damage captured from a friendly positive maximum-life increase; current-only heals do not qualify.
static func bow_on_growth() -> Effect:
	var event := Effect.EventPhrase.observe(&"life_increase", friends(), QuerySelector.new())
	var bow := Effect.Verb.new(&"bow", Action.bow, Action.can_bow, TargetRef.Kind.UNIT, TargetRef.Kind.HEX,
		[RuleNumber.new(&"maximum"), 2, true, false, false])
	return Effect.on_event(event, Effect.ConsequencePhrase.new(Selectors.Self.new(), bow, Selectors.BowTargets.new(2)), Condition.EventPositive.new(&"maximum"))

## Wild Beaver leaves Bomb 2 on the resolved move's captured origin, automatically; later movement or trigger delays cannot move that origin.
static func bomb_after_walk() -> Effect:
	var event := Effect.EventPhrase.observe(&"move", Selectors.Self.new(), QuerySelector.new(TargetRef.Kind.HEX), TargetRef.Kind.UNIT, TargetRef.Kind.HEX)
	return Effect.on_event(event, Effect.ConsequencePhrase.new(Selectors.Self.new(), Verbs.bomb_throw(2, 1000000),
		Selectors.EventHex.new(&"origin_hex"), Effect.Phrase.TargetMode.ALL), null, null, Effect.Policy.MANDATORY)

## Miner reacts once per friendly Bomb contact, including zero damage, preserving its exact recipient through a lethal hit without implicit revival.
static func heal_bomb_victim() -> Effect:
	var event := Effect.EventPhrase.observe(&"bomb_hit", QuerySelector.new(), friends())
	return Effect.on_event(event, Effect.ConsequencePhrase.new(Selectors.Self.new(), Verbs.up_life(1, 1),
		Selectors.Reference.new(Selectors.Anchor.EVENT_TARGET), Effect.Phrase.TargetMode.ALL))

## A defending Wild Mole Rat first leaves Bomb 2 on its Bash hex, then chooses one free movement destination using its own movement ability.
static func bomb_and_flee() -> Effect:
	var enemy := QuerySelector.new()
	enemy.relative_owner = Enum.OPP
	var event := Effect.EventPhrase.observe(&"bash", enemy, Selectors.Self.new(), TargetRef.Kind.UNIT, TargetRef.Kind.UNIT, &"target")
	return Effect.on_event(event, Effect.ConsequenceSequence.new([
		Effect.ConsequencePhrase.new(Selectors.Self.new(), Verbs.bomb_throw(2, 0), Selectors.HexOf.new(Selectors.Self.new()), Effect.Phrase.TargetMode.ALL),
		Effect.ConsequencePhrase.new(Selectors.Self.new(), Verbs.flee(), Selectors.FleeDestinations.new())]))

## Sorcerer pays current/max life plus activity, then grants permanent Bow damage/range counters to one chosen friend.
static func sorcerer_upgrade() -> Effect:
	return Effect.new(life_cost(1, 1), null, Effect.ConsequencePhrase.new(Selectors.Self.new(), Verbs.upgrade_bow(1, 1), friends()))

## Wild Mouse's C pays one extra action on the captured opponent's next turn and receives two Soul without self-Stun.
static func borrow_souls() -> Effect:
	var enemy := QuerySelector.new(TargetRef.Kind.PLAYER)
	enemy.relative_owner = Enum.OPP
	var cost := Effect.CostPhrase.new(Selectors.Self.new(), Verbs.pay_next_turn_action(), enemy)
	return Effect.new(cost, null, Effect.ConsequencePhrase.new(Selectors.Self.new(), Verbs.change_counter(2),
		Selectors.PropertyOf.new(Selectors.Self.new(), &"Soul"), Effect.Phrase.TargetMode.ALL))

## Soul-spending AC collects one Soul plus activity atomically; both Upgrade and Reset reuse this payment definition shape.
static func soul_cost() -> Effect.CostBundle:
	return Effect.CostBundle.new([Collection.action_cost(), Effect.CostPhrase.new(Selectors.Self.new(),
		Verbs.decrement(1), Selectors.PropertyOf.new(Selectors.Self.new(), &"Soul"))])

## Upgrade first chooses a friend, then one numeric ability on that exact unit through a completed-result PROPERTY projection.
static func soul_upgrade() -> Effect:
	var targets := Selectors.UpgradeUnits.new()
	targets.relative_owner = Enum.YOU
	return Effect.new(soul_cost(), null, Effect.ConsequenceSequence.new([
		Effect.ConsequencePhrase.new(Selectors.Self.new(), Verbs.choose_upgrade_unit(), targets),
		Effect.ConsequencePhrase.new(Selectors.Self.new(), Verbs.upgrade_ability(1, 0),
			Selectors.UpgradeOptions.new(Selectors.Completed.new(&"step_0", &"targets", TargetRef.Kind.UNIT)))]))

## Wild Mouse may spend one Soul plus activity to Reset any existing unit using the shared unrestricted Reset action.
static func soul_reset() -> Effect:
	return Effect.new(soul_cost(), null, Effect.ConsequencePhrase.new(Selectors.Self.new(), Verbs.reset_unit(), QuerySelector.new()))

## Guinea Pig spends current life plus activity to increase its own maximum only; a lethal payment does not revive the defeated payer.
static func guinea_growth() -> Effect:
	return Effect.new(life_cost(1), null, Effect.ConsequencePhrase.new(Selectors.Self.new(), Verbs.up_life(0, 1), Selectors.Self.new(), Effect.Phrase.TargetMode.ALL))

## Attack contact by a friendly deployed Wild-named unit heals this Guinea Pig once; shared physical/magical Hit uses the same name query.
static func heal_on_wild_hit() -> Effect:
	var wild := friends()
	wild.name_contains = "wild"
	var hit := Effect.EventPhrase.observe(&"hit", wild, QuerySelector.new())
	return Effect.on_event(hit, Effect.ConsequencePhrase.new(Selectors.Self.new(), Verbs.up_life(1, 0), Selectors.Self.new(), Effect.Phrase.TargetMode.ALL))

## Mouse Warrior watches an enemy entering its hex as Bash attacker, then stuns that exact actor and gains a permanent physical counter.
## CardCatalogue.mouse_warrior installs this target-stage trigger; already being in a Bash does not repeatedly activate it.
static func retaliate_on_bash() -> Effect:
	var enemy := QuerySelector.new()
	enemy.relative_owner = Enum.OPP
	var entered := Effect.EventPhrase.observe(&"bash", enemy, Selectors.Self.new(),
		TargetRef.Kind.UNIT, TargetRef.Kind.UNIT, &"target")
	var attacker := Selectors.Reference.new(Selectors.Anchor.EVENT_SUBJECT)
	var stun := Effect.ConsequencePhrase.new(Selectors.Self.new(), Verbs.stun(1, 0), attacker, Effect.Phrase.TargetMode.ALL)
	var physical := Effect.ConsequencePhrase.new(Selectors.Self.new(), Verbs.change_counter(1),
		Selectors.PropertyOf.new(Selectors.Self.new(), UnitInfo.PHYSICAL_COUNTER), Effect.Phrase.TargetMode.ALL)
	return Effect.on_event(entered, Effect.ConsequenceSequence.new([stun, physical]))
