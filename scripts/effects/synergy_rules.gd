## Reusable object-authored helpers for the approved PixelLab roster, with no activation data on definitions.
class_name SynergyRules
extends RefCounted

## Player's remaining-action getter derives deployed-source action allowances without writing resources or capturing effects.
static func player_action_bonus(owner: int) -> int:
	if owner not in [1, 2]: return 0
	var amount := 0
	for unit in Match.army:
		if unit == null or unit.player != owner or unit.t_state != Enum.t_state.DEPLOYED: continue
		for aura in unit.continuous_effects:
			if aura == null: continue
			for output in aura.contributions:
				if output != null and output.kind == Contribution.Kind.PLAYER_ACTIONS and aura.applies_to(unit.iun, unit.iun):
					amount += output.actions
	return amount

## Blue Mage tests another actor's pre-action Stun history; its raw bonus does not emit another Stun or recurse.
class AlreadyStunned extends Condition:
	## Capture excludes SELF as actor, activity payments and first applications, then reads the victim's frozen prior Stun.
	func test(ctx: RuleContext) -> bool:
		return ctx != null and ctx.source != null and ctx.triggering_event != null and ctx.triggering_event.subject != null \
			and not ctx.source.same(ctx.triggering_event.subject) and bool(ctx.triggering_event.data.get("hostile", false)) \
			and int(ctx.triggering_event.data.get("previous_stun", 0)) > 0

## Counter awards use UNIT recipients so a missing resource can be created without pretending it was an existing PROPERTY.
static func counter(key: StringName, amount: int) -> Effect.Verb:
	return Effect.Verb.new(&"add_counter", SynergyActions.add_counter, SynergyActions.can_add_counter,
		TargetRef.Kind.UNIT, TargetRef.Kind.UNIT, [key, amount])

## Roster factories declare zero-valued printed resources; Reset restores zero rather than re-running Deploy.
static func resource(unit: UnitInfo, key: StringName) -> void:
	unit._change_action_counter(key, 0)

## Delayed attacks retain their actor even after defeat; friendly actor matching therefore restricts owner, not the actor's later board state.
static func friendly_actors() -> QuerySelector:
	var query := QuerySelector.new()
	query.relative_owner = Enum.YOU
	return query

## Authors friendly deployed recipients within a radius or at exact adjacency through the shared HEX-to-UNIT projection.
static func friends_within(radius: int, adjacent: bool = false) -> Selector:
	var hexes := DistanceSelector.new(radius) if adjacent else DistanceSelector.within(radius)
	return Selectors.UnitsOn.new(hexes).where(WoodlandRules.friends())

## Creates a CHOOSE_ONE consequence, or ALL when a source/event identity should resolve without another picker.
static func phrase(verb: Effect.Verb, targets: Selector, automatic: bool = false) -> Effect.ConsequencePhrase:
	return Effect.ConsequencePhrase.new(Selectors.Self.new(), verb, targets,
		Effect.Phrase.TargetMode.ALL if automatic else Effect.Phrase.TargetMode.CHOOSE_ONE)

## Builds the approved [A]/[S]/[AS]/[2S] costs; extra costs join one atomic bundle and action-free propagates to verb legality.
static func command(consequence: Effect.ConsequencePhrase, stun: int = 1, action: bool = true,
		extra: Effect.CostPhrase = null) -> Effect:
	var payments: Array[Effect.CostPhrase] = []
	if stun > 0:
		payments.append(Effect.CostPhrase.new(Selectors.Self.new(), Verbs.pay_activity(not action, stun), Selectors.Self.new()))
	if extra != null: payments.append(extra)
	var payment: RefCounted = null
	if payments.size() == 1: payment = payments[0]
	elif payments.size() > 1: payment = Effect.CostBundle.new(payments)
	var effect := Collection.with_action_policy(consequence, stun == 0, not action, payment)
	effect.cost_label = StringName(("A" if action else "") + (str(stun) if stun > 1 else "") + ("S" if stun > 0 else ""))
	return effect

## A stored-counter spend chooses the exact existing PROPERTY before command() preflights it with activity.
static func spend(key: StringName, amount: int) -> Effect.CostPhrase:
	return Effect.CostPhrase.new(Selectors.Self.new(), Verbs.decrement(amount),
		Selectors.PropertyOf.new(Selectors.Self.new(), key))

## Captures one observed UNIT-to-UNIT event; callers choose SELF/friendly participants and an optional historical guard.
static func observe(action: StringName, actors: Selector, targets: Selector,
		consequence: RefCounted, guard: Condition = null) -> Effect:
	return Effect.on_event(Effect.EventPhrase.observe(action, actors, targets), consequence, guard)

## Deploy-resource triggers observe SELF entering a HEX and automatically award counters to that same identity.
static func on_deploy(key: StringName, amount: int) -> Effect:
	var event := Effect.EventPhrase.observe(&"deploy", Selectors.Self.new(), QuerySelector.new(TargetRef.Kind.HEX),
		TargetRef.Kind.UNIT, TargetRef.Kind.HEX)
	return Effect.on_event(event, phrase(counter(key, amount), Selectors.Self.new(), true))

## Upgrade first chooses an in-range friendly recipient with a numeric ability, then addresses that exact ability's stable PROPERTY.
static func upgrade(radius: int, soul_cost: int) -> Effect:
	var eligible := Selectors.UpgradeUnits.new()
	eligible.relative_owner = Enum.YOU
	var choice := phrase(Verbs.choose_upgrade_unit(), friends_within(radius).where(eligible))
	var effect := command(choice, 1, true, spend(&"Soul", soul_cost))
	effect.consequence = Effect.ConsequenceSequence.new([choice,
		phrase(Verbs.upgrade_ability(1, 0), Selectors.UpgradeOptions.new(
			Selectors.Completed.new(&"step_0", &"targets", TargetRef.Kind.UNIT)))])
	return effect

## Courier chooses a positive counter kind and amount, then a different destination; both deltas commit only in the final phrase.
static func transfer(recipients: Selector) -> Effect:
	var choose := Effect.Verb.new(&"choose_counter", SynergyActions.choose_counter, SynergyActions.can_choose_counter,
		TargetRef.Kind.UNIT, TargetRef.Kind.PROPERTY, [RuleNumber.choice()])
	choose.amount_limit = 2
	var selected := phrase(choose, Selectors.CountersOf.new(recipients))
	var transfer_verb := Effect.Verb.new(&"transfer_counter", SynergyActions.transfer_counter, SynergyActions.can_transfer_counter,
		TargetRef.Kind.UNIT, TargetRef.Kind.UNIT, [RuleBinding.new(&"step_0", RuleBinding.Field.HOST_ID),
		RuleBinding.new(&"step_0", RuleBinding.Field.PROPERTY_KEY), RuleBinding.new(&"step_0", RuleBinding.Field.AMOUNT)])
	var result := command(selected, 1, false)
	var destination := phrase(transfer_verb, recipients)
	destination.add_sticker(ActionSticker.new(ActionSticker.Kind.ACTION_FREE))
	result.consequence = Effect.ConsequenceSequence.new([selected, destination])
	return result

## Radius-independent event filters inspect captured attack kinds, excluding unrelated Hit/Wound families.
class AttackKind extends Condition:
	var family: StringName
	## Binds a reusable family name; capture supplies the immutable occurrence data.
	func _init(action: StringName) -> void:
		family = action
	## Bow support uses the original damage occurrence rather than the attacker's current available abilities.
	func test(ctx: RuleContext) -> bool:
		return ctx != null and ctx.triggering_event != null and ctx.triggering_event.data.get("kind", &"") == family

## Modifier-threshold auras query physical only, so their Bow/magical contributions cannot recurse into their own predicate.
class PhysicalAtLeast extends Condition:
	var minimum: int
	## Guardian factories bind their fixed threshold once; continuous reads supply each recipient.
	func _init(value: int = 3) -> void:
		minimum = value
	## Includes stored, temporary and live physical modifiers, including regional control.
	func test(ctx: RuleContext) -> bool:
		if ctx == null or ctx.recipient == null or ctx.recipient.kind != TargetRef.Kind.UNIT: return false
		var unit := Match.get_unit(ctx.recipient.id)
		return unit != null and unit.physical_modifier >= minimum

## Bomb-support auras depend on inert bomb presence at the recipient's current hex, never a copied tile snapshot.
class OnUnlitBomb extends Condition:
	## Beaver Warrior calls this during live magical-modifier reads; ignition or displacement removes the contribution immediately.
	func test(ctx: RuleContext) -> bool:
		return ctx != null and ctx.recipient != null and ctx.recipient.kind == TargetRef.Kind.UNIT \
			and ctx.recipient.has_hex() and Match.bomb_at(ctx.recipient.hex_id()) != null

## Jerboa Warrior reads the current opposing Bash participant's stored Stun count.
class BashingStunned extends Condition:
	## Continuous modifier reads inspect pending identity without writing counters or resolving the encounter.
	func test(ctx: RuleContext) -> bool:
		if not _matches_bash(ctx, true): return false
		for bash in Match.bashes:
			if bash.resolved: continue
			var other_id := bash.defender_id if bash.attacker_id == ctx.recipient.id else bash.attacker_id if bash.defender_id == ctx.recipient.id else -1
			var other := Match.get_unit(other_id)
			if other != null and other.player != Match.owner_of(ctx.recipient) and other._counter_value(UnitInfo.STUN_COUNTER) > 0: return true
		return false

## Banner Bearer reads whether the actual opposing Bash participant was forcibly moved in this player turn.
class BashingDisplaced extends Condition:
	## Aura evaluation uses captured per-unit displacement history; ordinary Walk and previous-turn displacement do not qualify.
	func test(ctx: RuleContext) -> bool:
		if not _matches_bash(ctx, true): return false
		for bash in Match.bashes:
			if bash.resolved: continue
			var other_id := bash.defender_id if bash.attacker_id == ctx.recipient.id else bash.attacker_id if bash.defender_id == ctx.recipient.id else -1
			var other := Match.get_unit(other_id)
			if other != null and other.player != Match.owner_of(ctx.recipient) and other.last_displaced_turn == Match.turn_number: return true
		return false
