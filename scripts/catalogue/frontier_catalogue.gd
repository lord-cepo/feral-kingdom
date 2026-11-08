## Object-authored roster additions from the approved PixelLab batch.
class_name FrontierCatalogue
extends RefCounted

## CardCatalogue appends these definitions after the established roster for both owners.
static func all_units(owner: int) -> Array[UnitInfo]:
	return [mole_shaman(owner), lemming_wizard(owner), mole_alchemist(owner), flying_squirrel_thief(owner),
		rat_hunter(owner), guinea_pig_berserker(owner), mara_merchant(owner), beaver_engineer(owner),
		marmot_crossbowman(owner), red_squirrel_paladin(owner), jerboa_pirate(owner)]

## Its Revive is restricted by geography; its separate Sacrifice pays normal activity and grants a future action.
static func mole_shaman(owner: int) -> UnitInfo:
	var unit := SynergyCatalogue.card(owner, "mole-shaman", "Mole Shaman", 2, [Enum.region.STARTING])
	unit.effects.append(Collection.movement(2))
	var revive := SynergyRules.command(SynergyRules.phrase(Verbs.revive(), AdventurerRules.friendly_zone(Enum.t_state.DEFEATED)))
	revive.condition = EnemySide.new()
	unit.effects.append(revive)
	unit.effects.append(SynergyRules.command(SynergyRules.phrase(Verbs.next_turn_actions(1), owner_player(), true),
		1, true, sacrifice_friend()))
	return unit

## Positive Ember gains by another deployed friend capture one award per turn on this Wizard.
static func lemming_wizard(owner: int) -> UnitInfo:
	var unit := SynergyCatalogue.card(owner, "lemming-wizard", "Lemming Wizard", 3, [Enum.region.INTERMEDIATE])
	unit.effects.append(Collection.fire_DR(1, 3))
	var gain := SynergyCatalogue.award_on(&"ember_added", UnitInfo.EMBER_COUNTER, 1, QuerySelector.new(),
		other_friends(), null, Condition.EventPositive.new(&"amount"))
	gain.once_per_turn_key = "friendly_ember"
	unit.trigger_effects.append(gain)
	return unit

## The paid Sacrifice records current life before defeat, and the followup reads that frozen amount.
static func mole_alchemist(owner: int) -> UnitInfo:
	var unit := SynergyCatalogue.card(owner, "mole-alchemist", "Mole Alchemist", 2, [Enum.region.INTERMEDIATE])
	unit.effects.append(Collection.fire_DR(1, 2))
	var award := Effect.Verb.new(&"add_counter", SynergyActions.add_counter, SynergyActions.can_add_counter,
		TargetRef.Kind.UNIT, TargetRef.Kind.UNIT, [UnitInfo.EMBER_COUNTER, RuleNumber.paid_amount(1)])
	unit.effects.append(SynergyRules.command(SynergyRules.phrase(award, Selectors.Self.new(), true),
		1, true, sacrifice_friend()))
	return unit

## Captures a deployed adjacent enemy hero's exact +1/+1 life event, then grants deployment and a Revive choice.
static func flying_squirrel_thief(owner: int) -> UnitInfo:
	var unit := SynergyCatalogue.card(owner, "flying-squirrel-thief", "Flying Squirrel Thief", 1,
		[Enum.region.INTERMEDIATE, Enum.region.FRONT])
	unit.effects.append(Collection.movement(2, true))
	var nearby_hero := Selectors.UnitsOn.new(DistanceSelector.new(1)).where(enemy_heroes())
	var sequence := Effect.ConsequenceSequence.new([
		SynergyRules.phrase(Verbs.grant_deployments(1), owner_player(), true),
		SynergyRules.phrase(Verbs.revive(), AdventurerRules.friendly_zone(Enum.t_state.DEFEATED))])
	var gain := Effect.EventPhrase.observe(&"life_increase", nearby_hero, QuerySelector.new(),
		TargetRef.Kind.UNIT, TargetRef.Kind.UNIT, &"resolved", {"actual": 1, "maximum": 1})
	unit.trigger_effects.append(Effect.on_event(gain, sequence))
	return unit

## Loaded adjacent units on either side gain live Bow values; declarations by loaded attackers offer a free retreat.
static func rat_hunter(owner: int) -> UnitInfo:
	var unit := SynergyCatalogue.card(owner, "rat-hunter", "Rat Hunter", 3, [Enum.region.FRONT])
	var loaded := ProjectileUnits.new()
	var adjacent := Selectors.UnitsOn.new(DistanceSelector.new(1)).where(loaded)
	unit.continuous_effects.append(ContinuousEffect.have(adjacent, [Contribution.bow_values(1, 1)],
		null, null, "Adjacent units with Projectiles have +1 Bow damage and +1 Bow range"))
	var retreat := SynergyRules.phrase(Verbs.movement(1, false, true), RetreatHexes.new())
	var declaration := Effect.EventPhrase.observe_any([&"bow", &"fire", &"cannon", &"gore"], loaded,
		QuerySelector.new(TargetRef.Kind.HEX), TargetRef.Kind.UNIT, TargetRef.Kind.HEX, &"target")
	unit.trigger_effects.append(Effect.on_event(declaration, retreat))
	var bash := Effect.EventPhrase.observe(&"bash", loaded, QuerySelector.new(),
		TargetRef.Kind.UNIT, TargetRef.Kind.UNIT, &"target")
	unit.trigger_effects.append(Effect.on_event(bash, retreat))
	return unit

## Own Bash declarations award Soul; positive X pays only Soul for Walk X followed by +X/+X through opposing End.
static func guinea_pig_berserker(owner: int) -> UnitInfo:
	var unit := SynergyCatalogue.card(owner, "guinea-pig-berserker", "Guinea Pig Berserker", 4,
		[Enum.region.STARTING, Enum.region.FRONT])
	SynergyRules.resource(unit, &"Soul")
	var bash := Effect.EventPhrase.observe(&"bash", Selectors.Self.new(), QuerySelector.new(),
		TargetRef.Kind.UNIT, TargetRef.Kind.UNIT, &"target")
	unit.trigger_effects.append(Effect.on_event(bash, SynergyRules.phrase(SynergyRules.counter(&"Soul", 1), Selectors.Self.new(), true)))
	var cost := Effect.CostPhrase.new(Selectors.Self.new(), Verbs.decrement_choice(),
		Selectors.PropertyOf.new(Selectors.Self.new(), &"Soul"))
	var x := RuleNumber.paid_amount(0)
	var move := Verbs.movement(1, false, true)
	move.user_params[0] = x
	var boost := Verbs.grant_modifiers(1, 1, true, true)
	boost.user_params[0] = x
	boost.user_params[1] = x
	var walk := SynergyRules.phrase(move, QuerySelector.new(TargetRef.Kind.HEX))
	var modifiers := SynergyRules.phrase(boost, Selectors.Self.new(), true)
	walk.action_free = true
	modifiers.action_free = true
	unit.effects.append(Effect.new(Effect.CostBundle.new([cost]), null, Effect.ConsequenceSequence.new([walk, modifiers])))
	return unit

## Merchant retains ordinary vacancy, player-token and first-hero checks but may also deploy under enemy control.
static func mara_merchant(owner: int) -> UnitInfo:
	var unit := SynergyCatalogue.card(owner, "mara-merchant", "Mara Merchant", 1,
		[Enum.region.STARTING, Enum.region.INTERMEDIATE, Enum.region.FRONT])
	unit.control_bonus = 3
	AdventurerCatalogue.passive(unit, &"enemy_control_deploy")
	unit.effects.append(Collection.shield_DR(2))
	return unit

## A selected adjacent friend's two Souls pay for consecutive friendly and enemy hand Disable choices.
static func beaver_engineer(owner: int) -> UnitInfo:
	var unit := SynergyCatalogue.card(owner, "beaver-engineer", "Beaver Engineer", 3, [Enum.region.STARTING, Enum.region.FRONT])
	unit.effects.append(Collection.cannon_DR(1, 3))
	var cost := Effect.CostPhrase.new(Selectors.Self.new(), Verbs.decrement(2),
		Selectors.PropertyOf.new(SynergyRules.friends_within(1, true), &"Soul"))
	var enemy := AdventurerRules.enemies()
	enemy.state = Enum.t_state.UNDEPLOYED
	var friendly := SynergyRules.phrase(Verbs.disable(), AdventurerRules.friendly_zone(Enum.t_state.UNDEPLOYED))
	var hostile := SynergyRules.phrase(Verbs.disable(), enemy)
	friendly.action_free = true
	hostile.action_free = true
	var disable := Effect.new(cost, null, Effect.ConsequenceSequence.new([friendly, hostile]))
	disable.condition = Condition.All.new([Condition.Matches.new(friendly.target), Condition.Matches.new(hostile.target)])
	unit.effects.append(disable)
	return unit

## Deploy grants two Projectiles; any actual own Hit permanently raises Bow damage without raising range.
static func marmot_crossbowman(owner: int) -> UnitInfo:
	var unit := SynergyCatalogue.card(owner, "marmot-crossbowman", "Marmot Crossbowman", 1,
		[Enum.region.STARTING, Enum.region.INTERMEDIATE])
	SynergyRules.resource(unit, UnitInfo.PROJECTILE_COUNTER)
	unit.effects.append(Collection.bow_DR(1, 3))
	unit.trigger_effects.append(SynergyRules.on_deploy(UnitInfo.PROJECTILE_COUNTER, 2))
	unit.trigger_effects.append(SynergyRules.observe(&"hit", Selectors.Self.new(), QuerySelector.new(),
		SynergyRules.phrase(Verbs.upgrade_bow(1, 0), Selectors.Self.new(), true)))
	return unit

## Opponent-side Intermediate Paladin pays self-Stun only for Bow or the paired Shield command.
static func red_squirrel_paladin(owner: int) -> UnitInfo:
	var unit := SynergyCatalogue.card(owner, "red-squirrel-paladin", "Red Squirrel Paladin", 3, [Enum.region.INTERMEDIATE])
	unit.deployment_enemy_side = true
	unit.effects.append(SynergyRules.command(SynergyRules.phrase(Verbs.bow(2, 2), Selectors.BowTargets.new(2)), 1, false))
	var friendly := SynergyRules.phrase(Verbs.shield(2), BashFriends.new())
	var hostile := SynergyRules.phrase(Verbs.shield(2, true), enemy_heroes(), true)
	friendly.action_free = true
	hostile.action_free = true
	var protection := Effect.new(Effect.CostPhrase.new(Selectors.Self.new(), Verbs.pay_activity(true, 1),
		Selectors.Self.new()), null, Effect.ConsequenceSequence.new([friendly, hostile]))
	protection.condition = Condition.All.new([Condition.Matches.new(friendly.target), Condition.Matches.new(hostile.target)])
	unit.effects.append(protection)
	return unit

## Its free Walk prefers a legal Bash; other deployed friends derive +1 Walk and no Fly bonus.
static func jerboa_pirate(owner: int) -> UnitInfo:
	var unit := SynergyCatalogue.card(owner, "jerboa-pirate", "Jerboa Pirate", 2, [Enum.region.FRONT])
	unit.effects.append(Collection.movement(2, false, true, true))
	AdventurerCatalogue.passive(unit, &"must_bash")
	unit.continuous_effects.append(ContinuousEffect.have(other_friends(),
		[Contribution.action_values(&"move", [1])], null, null, "Other friends have +1 Walk"))
	return unit

## Grants address the source's owning player, including when an enemy's occurrence triggered them.
static func owner_player() -> QuerySelector:
	var result := QuerySelector.new(TargetRef.Kind.PLAYER)
	result.relative_owner = Enum.YOU
	return result

## Both sacrifice commands pay one distinct deployed friend atomically with self-Stun.
static func sacrifice_friend() -> Effect.CostPhrase:
	return Effect.CostPhrase.new(Selectors.Self.new(), Verbs.sacrifice(), other_friends())

## Friendly auras and payment selectors exclude the source while retaining live ownership and deployment.
static func other_friends() -> OtherFriends:
	var result := OtherFriends.new()
	result.relative_owner = Enum.YOU
	result.state = Enum.t_state.DEPLOYED
	return result

## Filters the enemy hero by owner and live board state for the Thief and Paladin.
static func enemy_heroes() -> QuerySelector:
	var result := QuerySelector.new()
	result.relative_owner = Enum.OPP
	result.type = Enum.type.HERO
	result.state = Enum.t_state.DEPLOYED
	return result

class EnemySide extends Condition:
	## The Shaman's command preview and commit check geographical side rather than control.
	func test(ctx: RuleContext) -> bool:
		if ctx == null or ctx.source == null or not ctx.source.has_hex(): return false
		return int(Match.get_hex(ctx.source.hex_id()).side) == 3 - Match.owner_of(ctx.source)

class OtherFriends extends QuerySelector:
	## Inherits the owner and state filters, then excludes the exact SELF identity.
	func matches(candidate: TargetRef, ctx: RuleContext) -> bool:
		return super.matches(candidate, ctx) and not candidate.same(ctx.source)

class ProjectileUnits extends QuerySelector:
	## Hunter aura and attack capture test positive stored ammunition regardless of owner.
	func matches(candidate: TargetRef, ctx: RuleContext) -> bool:
		if not super.matches(candidate, ctx): return false
		if ctx != null and ctx.triggering_event != null and candidate.same(ctx.source): return false
		var unit := Match.get_unit(candidate.id)
		return unit.t_state == Enum.t_state.DEPLOYED and unit._counter_value(UnitInfo.PROJECTILE_COUNTER) > 0

class BashFriends extends QuerySelector:
	## The Shield choice resolves only live friendly participants of an unresolved encounter.
	func matches(candidate: TargetRef, ctx: RuleContext) -> bool:
		if not super.matches(candidate, ctx) or Match.owner_of(candidate) != Match.owner_of(ctx.source): return false
		for bash in Match.bashes:
			if bash != null and not bash.resolved and candidate.has_hex() and candidate.id in [bash.attacker_id, bash.defender_id]: return true
		return false

class RetreatHexes extends QuerySelector:
	## The retreat projects only adjacent HEX candidates; movement legality checks path and occupancy afterward.
	func _init() -> void:
		super(TargetRef.Kind.HEX)

	## Compare distances from the live attacking identity so a missing attacker or a non-away move cannot be selected.
	func matches(candidate: TargetRef, ctx: RuleContext) -> bool:
		if not super.matches(candidate, ctx) or ctx.triggering_event == null or not ctx.source.has_hex(): return false
		var attacker := ctx.triggering_event.subject
		if attacker == null or attacker.same(ctx.source) or not attacker.has_hex(): return false
		var origin := Match.get_hex(ctx.source.hex_id()).coordinate
		var threat := Match.get_hex(attacker.hex_id()).coordinate
		var landing := Match.get_hex(candidate.id).coordinate
		return DistanceSelector.hex_distance(origin, landing) == 1 and DistanceSelector.hex_distance(threat, landing) > DistanceSelector.hex_distance(threat, origin)
