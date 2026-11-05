## Object-authored Wild rodent rules; reusable definitions delegate choices and ordering to the managed runner.
class_name WildRules
extends RefCounted

## Mara observes the disabled card's ownership after it enters defeated, never a deployed-only target query or the disabling actor's owner.
## Each friendly Disable permanently raises Mara's own Cannon damage; enemy Disable raises its own current/maximum life instead.
static func grow_on_disable(friendly: bool) -> Effect:
	var disabled := QuerySelector.new()
	disabled.relative_owner = Enum.YOU if friendly else Enum.OPP
	var event := Effect.EventPhrase.observe(&"disable", QuerySelector.new(), disabled)
	var gain := Verbs.upgrade_cannon(1, 0) if friendly else Verbs.up_life(1, 1)
	return Effect.on_event(event, Effect.ConsequencePhrase.new(Selectors.Self.new(), gain,
		Selectors.Self.new(), Effect.Phrase.TargetMode.ALL))

## Tamia pays normal activity/action, chooses one friendly non-hero in hand to Disable, then grants its owner one remaining deployment.
## The ordered sequence keeps Disable distinct from Die/Return and grants no action refund; no legal hand recipient means no available command.
static func disable_for_deployment() -> Effect:
	var hand := QuerySelector.new()
	hand.relative_owner = Enum.YOU
	hand.state = Enum.t_state.UNDEPLOYED
	hand.excluded_type = Enum.type.HERO
	var owner := QuerySelector.new(TargetRef.Kind.PLAYER)
	owner.relative_owner = Enum.YOU
	return Effect.new(Collection.action_cost(), null, Effect.ConsequenceSequence.new([
		Effect.ConsequencePhrase.new(Selectors.Self.new(), Verbs.disable(), hand),
		Effect.ConsequencePhrase.new(Selectors.Self.new(), Verbs.grant_deployments(1), owner, Effect.Phrase.TargetMode.ALL)]))

## Grey Squirrel pays activity but no player action to give one exact-distance-one friend +1 Bow damage through the current turn's End cleanup.
## Recipient-bound TimedGrant survives source departure, affects captured Bow values, and expires after End followups; it is not a permanent counter.
static func prepare_bow() -> Effect:
	var adjacent := Selectors.UnitsOn.new(DistanceSelector.new(1)).where(WoodlandRules.friends())
	return Collection.grant_action_values(&"bow", [1, 0], adjacent, false, true)

## Marmot's normal action selects a friendly UNIT at exactly distance one; adjacency excludes SELF and its entire distance-zero hex.
static func return_friend() -> Effect:
	var friends := QuerySelector.new()
	friends.relative_owner = Enum.YOU
	var targets := Selectors.UnitsOn.new(DistanceSelector.new(1)).where(friends)
	return Collection.with_action_policy(Effect.ConsequencePhrase.new(Selectors.Self.new(), Verbs.return_to_hand(), targets))

## Dormouse's Deploy trigger chooses exactly one adjacent unit of either owner; the event subject must be SELF.
## Exact distance one excludes the deploying card and every occupant on its own hex; no activity cost accompanies Deploy.
static func return_on_deploy() -> Effect:
	var deployed := Effect.EventPhrase.observe(&"deploy", Selectors.Self.new(), QuerySelector.new(TargetRef.Kind.HEX),
		TargetRef.Kind.UNIT, TargetRef.Kind.HEX)
	return Effect.on_event(deployed, Effect.ConsequencePhrase.new(Selectors.Self.new(), Verbs.return_to_hand(), DistanceSelector.new(1)))

## Jerboa observes only an enemy declaring Bash against SELF and returns that captured attacker, never a replacement occupant.
## Triggered Return requires no activity payment and the shared zone action cancels the abandoned encounter without Flee.
static func return_bash_attacker() -> Effect:
	var enemy := QuerySelector.new()
	enemy.relative_owner = Enum.OPP
	var attacked := Effect.EventPhrase.observe(&"bash", enemy, Selectors.Self.new(),
		TargetRef.Kind.UNIT, TargetRef.Kind.UNIT, &"target")
	return Effect.on_event(attacked, Effect.ConsequencePhrase.new(Selectors.Self.new(), Verbs.return_to_hand(),
		Selectors.Reference.new(Selectors.Anchor.EVENT_SUBJECT), Effect.Phrase.TargetMode.ALL))

## Chinchilla's own Deploy grants one remaining deployment to its owner, never an action or automatic placement.
static func deployment_on_deploy() -> Effect:
	var deployed := Effect.EventPhrase.observe(&"deploy", Selectors.Self.new(), QuerySelector.new(TargetRef.Kind.HEX),
		TargetRef.Kind.UNIT, TargetRef.Kind.HEX)
	var owner := QuerySelector.new(TargetRef.Kind.PLAYER)
	owner.relative_owner = Enum.YOU
	return Effect.on_event(deployed, Effect.ConsequencePhrase.new(Selectors.Self.new(), Verbs.grant_deployments(1),
		owner, Effect.Phrase.TargetMode.ALL))

## Hedgehog gains persistent physical and magical counters on actual received Hit, including zero damage and magical attacks.
## Own attacks, misses and immunity-prevented contact do not qualify; the captured victim identity survives lethal contact.
static func grow_on_received_hit() -> Effect:
	var hit := Effect.EventPhrase.observe(&"hit", QuerySelector.new(), Selectors.Self.new())
	var physical := Effect.ConsequencePhrase.new(Selectors.Self.new(), Verbs.change_counter(1),
		Selectors.PropertyOf.new(Selectors.Self.new(), UnitInfo.PHYSICAL_COUNTER), Effect.Phrase.TargetMode.ALL)
	var magical := Effect.ConsequencePhrase.new(Selectors.Self.new(), Verbs.change_counter(1),
		Selectors.PropertyOf.new(Selectors.Self.new(), UnitInfo.MAGICAL_COUNTER), Effect.Phrase.TargetMode.ALL)
	return Effect.on_event(hit, Effect.ConsequenceSequence.new([physical, magical]))

## Chinchilla's captured own-death trigger chooses another deployed friend for the shared Return-and-effect-deploy mutation.
## Choices remain UNIT identities across acknowledgements; a source already recovered by an earlier activation is ineligible.
static func replace_on_death() -> Effect:
	var death := Effect.EventPhrase.observe(&"die", Selectors.Self.new(), QuerySelector.new(TargetRef.Kind.HEX),
		TargetRef.Kind.UNIT, TargetRef.Kind.HEX)
	return Effect.on_event(death, Effect.ConsequencePhrase.new(Selectors.Self.new(), Verbs.return_and_deploy(), WoodlandRules.friends()))

## Lemming's own Deploy adds three extra Stun on top of the normal deployment counter, preserving other stored counters and inactivity.
static func stun_on_deploy() -> Effect:
	var deployed := Effect.EventPhrase.observe(&"deploy", Selectors.Self.new(), QuerySelector.new(TargetRef.Kind.HEX),
		TargetRef.Kind.UNIT, TargetRef.Kind.HEX)
	return Effect.on_event(deployed, Effect.ConsequencePhrase.new(Selectors.Self.new(), Verbs.change_counter(3),
		Selectors.PropertyOf.new(Selectors.Self.new(), UnitInfo.STUN_COUNTER), Effect.Phrase.TargetMode.ALL))

## Porcupine collects one friendly UNIT, a positive stored counter PROPERTY on that unit, then X, and ordinary activity before committing atomically.
## The paid counter amount at cost_1 grants exactly X Soul; definitions retain neither the chosen host nor amount.
static func harvest_counters(friendly: Selector) -> Effect:
	var choose_host := Effect.CostPhrase.new(Selectors.Self.new(), Verbs.choose_counter_unit(), friendly)
	var counters := Selectors.CountersOf.new(Selectors.Completed.new(&"cost_choice_0", &"targets", TargetRef.Kind.UNIT))
	var remove := Effect.CostPhrase.new(Selectors.Self.new(), Verbs.decrement_choice(), counters)
	var cost := Effect.CostBundle.new([choose_host, remove, Collection.action_cost()])
	var gain := Effect.Verb.new(&"change_counter", Action.change_counter, Action.can_change_counter,
		TargetRef.Kind.UNIT, TargetRef.Kind.PROPERTY, [RuleNumber.paid_amount(1)])
	var effect := Effect.new(cost, null, Effect.ConsequencePhrase.new(Selectors.Self.new(), gain,
		Selectors.PropertyOf.new(Selectors.Self.new(), &"Soul"), Effect.Phrase.TargetMode.ALL))
	effect.cost_label = &"AC"
	return effect

## Porcupine chooses a positive Soul payment, pays ordinary activity, then Stuns one chosen enemy with that frozen X duration.
## Omitted range is unlimited (-1); the deployed-enemy query and shared hostile-Stun resolver own eligibility and counter-preserving mutation.
static func stun_with_souls() -> Effect:
	var souls := Effect.CostPhrase.new(Selectors.Self.new(), Verbs.decrement_choice(),
		Selectors.PropertyOf.new(Selectors.Self.new(), &"Soul"))
	var cost := Effect.CostBundle.new([souls, Collection.action_cost()])
	var enemy := QuerySelector.new()
	enemy.relative_owner = Enum.OPP
	enemy.state = Enum.t_state.DEPLOYED
	var stun := Effect.Verb.new(&"stun", Action.stun, Action.can_stun,
		TargetRef.Kind.UNIT, TargetRef.Kind.UNIT, [RuleNumber.paid_amount(0), -1, false])
	var effect := Effect.new(cost, null, Effect.ConsequencePhrase.new(Selectors.Self.new(), stun,
		enemy))
	effect.cost_label = &"AC"
	return effect

## Flying Squirrel's [A2S] replaces ordinary one-Stun payment with two self-Stun, then chooses a normal Fly-3 destination.
## The payer must be active; ordinary route/landing checks apply and the enclosing command still spends one player action.
static func tiring_fly() -> Effect:
	var cost := Effect.CostPhrase.new(Selectors.Self.new(), Verbs.pay_activity(false, 2), Selectors.Self.new())
	var effect := Collection.with_action_policy(Effect.ConsequencePhrase.new(Selectors.Self.new(),
		Verbs.movement(3, true), DistanceSelector.within(3)), false, false, cost)
	effect.cost_label = &"A2S"
	return effect
