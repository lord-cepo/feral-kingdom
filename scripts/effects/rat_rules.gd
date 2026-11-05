## Object-authored rat catalogue rules, with runtime mutations owned by named verbs and the shared runner.
class_name RatRules
extends RefCounted

## Rat Dark Mage observes its own death, then asks for exactly one existing unit of either owner/state to Reset.
static func reset_on_death() -> Effect:
	var death := Effect.EventPhrase.observe(&"die", Selectors.Self.new(), QuerySelector.new(TargetRef.Kind.HEX), TargetRef.Kind.UNIT, TargetRef.Kind.HEX)
	return Effect.on_event(death, Effect.ConsequencePhrase.new(Selectors.Self.new(), Verbs.reset_unit(), QuerySelector.new()))

## Rat Musketeer observes any enemy death; the shared Revive legality limits its chosen recipient to a different friendly defeated non-hero.
static func recover_on_enemy_death() -> Effect:
	var enemy := QuerySelector.new()
	enemy.relative_owner = Enum.OPP
	var dead := QuerySelector.new()
	dead.relative_owner = Enum.YOU
	dead.state = Enum.t_state.DEFEATED
	var death := Effect.EventPhrase.observe(&"die", enemy, QuerySelector.new(TargetRef.Kind.HEX), TargetRef.Kind.UNIT, TargetRef.Kind.HEX)
	return Effect.on_event(death, Effect.ConsequencePhrase.new(Selectors.Self.new(), Verbs.revive(), dead))

## Rat Thief's Wound event freezes the victim identity; effect properties offer actions, triggers, states, auras and printed passives as individual choices.
static func copy_on_wound() -> Effect:
	var wound := Effect.EventPhrase.observe(&"wound", Selectors.Self.new(), QuerySelector.new())
	return Effect.on_event(wound, Effect.ConsequencePhrase.new(Selectors.Self.new(), Verbs.copy_effect(),
		Selectors.EffectsOf.new(Selectors.Reference.new(Selectors.Anchor.EVENT_TARGET))))

## Rat Warrior gains its own Soul counter for each friendly return-to-hand occurrence, including another unit's recovery consequence.
static func soul_on_return() -> Effect:
	var friendly := QuerySelector.new()
	friendly.relative_owner = Enum.YOU
	var returned := Effect.EventPhrase.observe(&"return_to_hand", QuerySelector.new(), friendly)
	return Effect.on_event(returned, Effect.ConsequencePhrase.new(Selectors.Self.new(), Verbs.change_counter(1),
		Selectors.PropertyOf.new(Selectors.Self.new(), &"Soul"), Effect.Phrase.TargetMode.ALL))

## Rat Warrior exchanges two Soul counters and ordinary activity for one owner deployment; CostBundle preflights both payments atomically.
static func soul_deployment() -> Effect:
	var owner := QuerySelector.new(TargetRef.Kind.PLAYER)
	owner.relative_owner = Enum.YOU
	var cost := Effect.CostBundle.new([Collection.action_cost(), Effect.CostPhrase.new(Selectors.Self.new(),
		Verbs.decrement(2), Selectors.PropertyOf.new(Selectors.Self.new(), &"Soul"))])
	var effect := Effect.new(cost, null, Effect.ConsequencePhrase.new(Selectors.Self.new(), Verbs.grant_deployments(1), owner, Effect.Phrase.TargetMode.ALL))
	effect.cost_label = &"C"
	effect.condition = Condition.All.new([Condition.Active.new(), Condition.CounterAtLeast.new(&"Soul", 2)])
	return effect

## Swordsman observes only a dodge where it was the Bash attacker and its original defender was the leaving participant.
## Flee explicitly observes the cancelled encounter; generic attack triggers continue to reject cancellations.
static func action_on_flee() -> Effect:
	var fled := Effect.EventPhrase.observe(&"bash", Selectors.Self.new(), QuerySelector.new(),
		TargetRef.Kind.UNIT, TargetRef.Kind.UNIT, &"resolved", {"dodged": true, "defender_fled": true})
	fled.observes_cancelled = true
	var owner := QuerySelector.new(TargetRef.Kind.PLAYER)
	owner.relative_owner = Enum.YOU
	return Effect.on_event(fled, Effect.ConsequencePhrase.new(Selectors.Self.new(), Verbs.next_turn_actions(1), owner, Effect.Phrase.TargetMode.ALL))
