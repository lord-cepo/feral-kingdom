## The three approved crowned hero alternatives; CardCatalogue appends them after older stable identities.
class_name HeroCatalogue
extends RefCounted

## Both inventory entry points append these owner-bound reusable definitions in this fixed order.
static func all_units(owner: int) -> Array[UnitInfo]:
	return [grey_squirrel_king(owner), jerboa_king(owner), marmot_queen(owner)]

## Builds Starting-region heroes; Match retains first-deployed hero choice and adds normal hero phase rules.
static func hero(owner: int, key: String, title: String, life: int, movement: int) -> UnitInfo:
	var unit := SynergyCatalogue.card(owner, key, title, life, [Enum.region.STARTING])
	unit.type = Enum.type.HERO
	unit.effects.append(Collection.movement(movement))
	return unit

## Shared spatial selectors exclude SELF explicitly, including when opposing Bash occupants share a hex.
class OtherFriends extends QuerySelector:
	## Hero definitions use this for friendly recipients whose exact identity differs from the source.
	func _init() -> void:
		relative_owner = Enum.YOU
		state = Enum.t_state.DEPLOYED
	## Selection and continuous reads apply ownership/state before excluding the source identity.
	func matches(candidate: TargetRef, ctx: RuleContext) -> bool:
		return super.matches(candidate, ctx) and ctx != null and ctx.source != null and candidate.id != ctx.source.id

## Supplies other deployed friends within a radius; exact adjacency is used only when requested.
static func other_friends(radius: int, adjacent: bool = false, troops: bool = false) -> Selector:
	var query := OtherFriends.new()
	if troops: query.type = Enum.type.TROOP
	var area := DistanceSelector.new(radius) if adjacent else DistanceSelector.within(radius)
	return Selectors.UnitsOn.new(area).where(query)

## King reloads an adjacent friend of any type; loaded adjacent friends receive live physical protection.
static func grey_squirrel_king(owner: int) -> UnitInfo:
	var unit := hero(owner, "grey-squirrel-king", "Grey Squirrel King", 5, 1)
	unit.effects.append(SynergyRules.command(SynergyRules.phrase(
		SynergyRules.counter(UnitInfo.PROJECTILE_COUNTER, 1), other_friends(1, true))))
	unit.effects.append(SynergyCatalogue.shield(2, 2))
	unit.continuous_effects.append(ContinuousEffect.have(other_friends(1, true),
		[Contribution.modifiers(1, 0)], null, Loaded.new(), "Adjacent friends with projectiles: +1 physical"))
	return unit

## Recipient-bound ammunition predicate; CounterAtLeast tests SELF, so this reads the aura recipient explicitly.
class Loaded extends Condition:
	## Live physical reads lose this bonus as soon as the recipient spends its last Projectile or leaves range.
	func test(ctx: RuleContext) -> bool:
		if ctx == null or ctx.recipient == null: return false
		var unit := Match.get_unit(ctx.recipient.id)
		return unit != null and unit._counter_value(UnitInfo.PROJECTILE_COUNTER) > 0

## King retains Push/Stun; each shifted friend has +2 physical until the source enemy End, refreshed per recipient.
static func jerboa_king(owner: int) -> UnitInfo:
	var unit := hero(owner, "jerboa-king", "Jerboa King", 6, 2)
	var enemies := QuerySelector.new()
	enemies.relative_owner = Enum.OPP
	unit.effects.append(SynergyRules.command(SynergyRules.phrase(Verbs.push(1, 2),
		Selectors.UnitsOn.new(DistanceSelector.within(2)).where(enemies))))
	unit.effects.append(Collection.stun_DR(1, 1))
	var shifted := Effect.EventPhrase.observe(&"shifted", SynergyRules.friendly_actors(), QuerySelector.new(TargetRef.Kind.HEX),
		TargetRef.Kind.UNIT, TargetRef.Kind.HEX)
	unit.trigger_effects.append(Effect.on_event(shifted, SynergyRules.phrase(Verbs.grant_modifiers(2, 0, true),
		Selectors.Reference.new(Selectors.Anchor.EVENT_SUBJECT), true)))
	return unit

## Sacrifice capture reads the victim's recorded departure hex, never its now-absent board position.
class NearbySacrifice extends Condition:
	## Queen captures another friendly victim within two; Die alone, enemies, distant victims and SELF do not qualify.
	func test(ctx: RuleContext) -> bool:
		if ctx == null or ctx.source == null or ctx.triggering_event == null: return false
		var event := ctx.triggering_event
		if event.target == null or event.target.id == ctx.source.id: return false
		var source := Match.get_unit(ctx.source.id)
		var victim := Match.get_unit(event.target.id)
		if source == null or victim == null or source.player != victim.player or source.ihx < 0: return false
		var last_hex := int(event.data.get("last_hex", -1))
		if Match.get_hex(last_hex) == null: return false
		return DistanceSelector.hex_distance(Match.get_hex(source.ihx).coordinate, Match.get_hex(last_hex).coordinate) <= 2

## Matriarch heals another friend and gains consumed protection from nearby sacrifices; wounded support is a live aura.
static func marmot_queen(owner: int) -> UnitInfo:
	var unit := hero(owner, "marmot-queen", "Marmot Queen", 6, 1)
	unit.effects.append(SynergyRules.command(SynergyRules.phrase(Verbs.mend(2, 2), other_friends(2))))
	var protection := Effect.ConsequenceSequence.new([
		SynergyRules.phrase(Verbs.shield(1), Selectors.Self.new(), true),
		SynergyRules.phrase(Verbs.mshield(1), Selectors.Self.new(), true)])
	unit.trigger_effects.append(SynergyRules.observe(&"sacrifice", QuerySelector.new(), QuerySelector.new(),
		protection, NearbySacrifice.new()))
	unit.continuous_effects.append(ContinuousEffect.have(other_friends(1, true),
		[Contribution.modifiers(0, 1)], Condition.Wounded.new(), null,
		"While wounded, adjacent friends: +1 magical"))
	return unit
