## The second Frontier batch; CardCatalogue appends these after all established identities.
class_name FrontierRecruits
extends RefCounted

## Both owners receive the nine recruits in the same stable order.
static func all_units(owner: int) -> Array[UnitInfo]:
	return [beaver_bard(owner), chinchilla_druid(owner), dormouse_bard(owner), guinea_pig_jester(owner),
		hedgehog_cleric(owner), hedgehog_musketeer(owner), lemming_monk(owner), mara_witch(owner), otter_blacksmith(owner)]

## Push uses shared alignment checks. Each friendly Bash from an adjacent hex grants the attacker both counters.
static func beaver_bard(owner: int) -> UnitInfo:
	var unit := SynergyCatalogue.card(owner, "beaver-bard", "Beaver Bard", 2, [Enum.region.INTERMEDIATE, Enum.region.FRONT])
	unit.effects.append(Collection.movement(2))
	var push_targets := Selectors.UnitsOn.new(DistanceSelector.within(2, Selectors.Anchor.SUBJECT))
	unit.effects.append(SynergyRules.command(SynergyRules.phrase(Verbs.push(1, 2),
		push_targets.where(AdventurerRules.enemies()))))
	var attacker := Selectors.Reference.new(Selectors.Anchor.EVENT_SUBJECT)
	var bash := Effect.EventPhrase.observe(&"bash", FrontierCatalogue.other_friends(), QuerySelector.new(),
		TargetRef.Kind.UNIT, TargetRef.Kind.UNIT, &"target")
	var rally := Effect.on_event(bash, Effect.ConsequenceSequence.new([
		SynergyRules.phrase(Verbs.shield(1), attacker, true), SynergyRules.phrase(Verbs.mshield(1), attacker, true)]), Rally.new())
	rally.rule_text = "Friend Bashes from an adjacent hex: it gets +1 Shield and +1 Mshield."
	unit.trigger_effects.append(rally)
	return unit

## Mend restores one life within two; other wounded friends retain their global control contribution.
static func chinchilla_druid(owner: int) -> UnitInfo:
	var unit := SynergyCatalogue.card(owner, "chinchilla-druid", "Chinchilla Druid", 2, [Enum.region.INTERMEDIATE, Enum.region.FRONT])
	unit.effects.append(Collection.movement(2))
	unit.effects.append(Collection.mend_DR(1, 2))
	unit.continuous_effects.append(ContinuousEffect.have(FrontierCatalogue.other_friends(), [Contribution.regional_strength(1)],
		null, Condition.Wounded.new(), "Other wounded friends have +1 control"))
	return unit

## Return pays only self-Stun and takes an adjacent friend. The separate trigger still measures both distances within two.
static func dormouse_bard(owner: int) -> UnitInfo:
	var unit := SynergyCatalogue.card(owner, "dormouse-bard", "Dormouse Bard", 1, [Enum.region.INTERMEDIATE])
	unit.effects.append(Collection.movement(2))
	var recall := SynergyRules.command(SynergyRules.phrase(Verbs.return_to_hand(),
		Selectors.UnitsOn.new(DistanceSelector.new(1)).where(FrontierCatalogue.other_friends())), 1, false)
	recall.rule_text = "[lb]S[rb] Return an adjacent friend."
	unit.effects.append(recall)
	var movable := QuerySelector.new()
	movable.state = Enum.t_state.DEPLOYED
	movable.excluded_type = Enum.type.TEMPLE
	var relocate := Effect.ConsequencePhrase.new(Selectors.UnitsOn.new(DistanceSelector.within(2)).where(movable),
		Verbs.relocate(), Selectors.EventHex.new(&"last_hex"), Effect.Phrase.TargetMode.ALL)
	var relief := SynergyRules.observe(&"return_to_hand", QuerySelector.new(), OtherUnit.new(), relocate, NearbyReturn.new())
	relief.policy = Effect.Policy.OPTIONAL
	relief.rule_text = "Another unit Returns within 2: you may move a unit within 2 onto its former hex."
	unit.trigger_effects.append(relief)
	return unit

## Every eligible attack declaration forces the Jester's two-step Flee before impact, with no payment.
static func guinea_pig_jester(owner: int) -> UnitInfo:
	var unit := SynergyCatalogue.card(owner, "guinea-pig-jester", "Guinea Pig Jester", 2, [Enum.region.INTERMEDIATE])
	unit.effects.append(Collection.movement(2))
	unit.effects.append(Collection.bow_DR(1, 2))
	SynergyRules.resource(unit, &"Soul")
	unit.trigger_effects.append(SynergyRules.on_deploy(&"Soul", 1))
	var enemy := QuerySelector.new()
	enemy.relative_owner = Enum.OPP
	var attack := Effect.EventPhrase.observe_attack_declaration(enemy)
	var dodge := Effect.on_event(attack, SynergyRules.phrase(Verbs.flee(2), Selectors.FleeDestinations.new()), IncomingAttack.new())
	dodge.before_attack_resolution = true
	dodge.rule_text = "This unit is attacked: Flee."
	unit.trigger_effects.append(dodge)
	return unit

## Mshield targets a friend at any distance. Each magically shielded friend surviving physical contact gains life and Shield.
static func hedgehog_cleric(owner: int) -> UnitInfo:
	var unit := SynergyCatalogue.card(owner, "hedgehog-cleric", "Hedgehog Cleric", 3, [Enum.region.STARTING])
	var ward := SynergyRules.command(SynergyRules.phrase(Verbs.mshield(1), WoodlandRules.friends()))
	ward.rule_text = "1 Mshield on friend."
	unit.effects.append(ward)
	var survivor := Selectors.Reference.new(Selectors.Anchor.EVENT_TARGET).where(WoodlandRules.friends())
	var treatment := SynergyRules.observe(&"hit", QuerySelector.new(), WoodlandRules.friends(),
		Effect.ConsequenceSequence.new([SynergyRules.phrase(Verbs.up_life(3, 0), survivor, true),
			SynergyRules.phrase(Verbs.shield(1), survivor, true)]), SurvivingContact.new(true))
	treatment.rule_text = "Friend with 1+ Mshield survives a physical attack: +3 heart and +1 Shield on it."
	unit.trigger_effects.append(treatment)
	return unit

## Deploy loads two shots. Every surviving friendly Wound gets two Shield before its free Flee choice.
static func hedgehog_musketeer(owner: int) -> UnitInfo:
	var unit := SynergyCatalogue.card(owner, "hedgehog-musketeer", "Hedgehog Musketeer", 2, [Enum.region.FRONT])
	unit.effects.append(Collection.movement(1))
	SynergyRules.resource(unit, UnitInfo.PROJECTILE_COUNTER)
	unit.trigger_effects.append(SynergyRules.on_deploy(UnitInfo.PROJECTILE_COUNTER, 2))
	unit.effects.append(SynergyRules.command(SynergyRules.phrase(Verbs.cannon(2, 3),
		DistanceSelector.within(3, Selectors.Anchor.SUBJECT)), 1, true, SynergyRules.spend(UnitInfo.PROJECTILE_COUNTER, 1), true))
	var recipient := Selectors.Reference.new(Selectors.Anchor.EVENT_TARGET)
	var flee := Effect.ConsequencePhrase.new(recipient, Verbs.flee(), Selectors.FleeDestinations.new())
	var brace := SynergyRules.observe(&"wound", Selectors.Self.new(), WoodlandRules.friends(),
		Effect.ConsequenceSequence.new([SynergyRules.phrase(Verbs.shield(2), recipient, true), flee]), SurvivingContact.new())
	brace.rule_text = "This unit wounds a friend: target gets +2 Shield and Flees."
	unit.trigger_effects.append(brace)
	return unit

## The Monk moves a stored Stun without activity/token costs and derives one action from the enemy hero's live Stun.
static func lemming_monk(owner: int) -> UnitInfo:
	var unit := SynergyCatalogue.card(owner, "lemming-monk", "Lemming Monk", 1, [Enum.region.INTERMEDIATE])
	unit.effects.append(Collection.movement(2))
	var donor := Selectors.PropertyOf.new(Selectors.UnitsOn.new(DistanceSelector.new(1)).where(FrontierCatalogue.other_friends()),
		UnitInfo.STUN_COUNTER)
	var pay := Effect.CostPhrase.new(Selectors.Self.new(), Verbs.decrement(1), donor)
	var transfer := SynergyRules.command(SynergyRules.phrase(SynergyRules.counter(UnitInfo.STUN_COUNTER, 1),
		AdventurerRules.enemies()), 0, false, pay)
	transfer.condition = Condition.Matches.new(transfer.consequence.target)
	transfer.rule_text = "[lb][rb] -1 Stun from adjacent friend: +1 Stun on enemy."
	unit.effects.append(transfer)
	unit.continuous_effects.append(ContinuousEffect.while_self(EnemyHeroStunned.new(), [Contribution.player_actions(1)],
		"While the enemy hero has 5+ Stun: +1 action"))
	return unit

## Ash Offering pays self-Stun and a friendly hand Disable atomically, then awards two Ember within two.
static func mara_witch(owner: int) -> UnitInfo:
	var unit := SynergyCatalogue.card(owner, "mara-witch", "Mara Witch", 1, [Enum.region.INTERMEDIATE])
	unit.effects.append(Collection.movement(1))
	unit.effects.append(Collection.fire_DR(1, 3))
	var disable := Effect.CostPhrase.new(Selectors.Self.new(), Verbs.disable(), AdventurerRules.friendly_zone(Enum.t_state.UNDEPLOYED))
	var offering := SynergyRules.command(SynergyRules.phrase(SynergyRules.counter(UnitInfo.EMBER_COUNTER, 2),
		SynergyRules.friends_within(2)), 1, false, disable)
	offering.rule_text = "[lb]S[rb] Disable a friend: give 2 Ember to a friend within 2."
	unit.effects.append(offering)
	return unit

## Otter trades one stored Shield counter for two Projectiles on an adjacent friend.
static func otter_blacksmith(owner: int) -> UnitInfo:
	var unit := SynergyCatalogue.card(owner, "otter-blacksmith", "Otter Blacksmith", 3, [Enum.region.INTERMEDIATE])
	unit.effects.append(Collection.movement(1))
	unit.effects.append(Collection.shield_DR(2))
	var forge := SynergyRules.command(SynergyRules.phrase(SynergyRules.counter(UnitInfo.PROJECTILE_COUNTER, 2),
		SynergyRules.friends_within(1, true)), 1, true,
		SynergyRules.spend(UnitInfo.SHIELD_COUNTER, 1))
	forge.condition = Condition.Matches.new(forge.consequence.target)
	forge.rule_text = "-1 Shield: +2 Projectiles on adjacent friend."
	unit.effects.append(forge)
	return unit

## Compares a captured hex with the source's position at event capture.
static func distance_from(source: TargetRef, hex_id: int) -> int:
	var tile := Match.get_hex(hex_id)
	if source == null or not source.has_hex() or tile == null: return -1
	return DistanceSelector.hex_distance(Match.get_hex(source.hex_id()).coordinate, tile.coordinate)

class OtherUnit extends QuerySelector:
	## The Return target may belong to either player, but the Bard cannot trigger off its own departure.
	func matches(candidate: TargetRef, ctx: RuleContext) -> bool:
		return super.matches(candidate, ctx) and ctx != null and not candidate.same(ctx.source)

class Rally extends Condition:
	## Capture a friendly Bash whose attacker had a real board origin adjacent to the Bard.
	func test(ctx: RuleContext) -> bool:
		var history := ctx.triggering_event.data
		return FrontierRecruits.distance_from(ctx.source, int(history.get("origin_hex", -1))) == 1

class NearbyReturn extends Condition:
	## The returned identity has left the board, so the trigger uses its captured hex and only a vacant destination.
	func test(ctx: RuleContext) -> bool:
		var hex_id := int(ctx.triggering_event.data.get("last_hex", -1))
		var distance := FrontierRecruits.distance_from(ctx.source, hex_id)
		return distance in [0, 1, 2] and Match.occupants(hex_id).is_empty()

class IncomingAttack extends Condition:
	## Bash binds its defender, Bow/Fire bind their original victim, and Cannon threatens every hex on its captured line.
	func test(ctx: RuleContext) -> bool:
		var event := ctx.triggering_event
		if not ctx.source.has_hex(): return false
		var aimed_at_self := false
		match event.action:
			&"bash": aimed_at_self = ctx.source.same(event.target)
			&"cannon": aimed_at_self = ctx.source.hex_id() in event.data.get("line", [])
			&"bow", &"fire": aimed_at_self = int(event.data.get("target_unit_id", -1)) == ctx.source.id
		return aimed_at_self and Match.map.any(func(tile: HexInfo) -> bool:
			return tile != null and CombatResolver.can_flee_to(ctx.source, TargetRef.hex(tile.hex_id), 2))

class SurvivingContact extends Condition:
	var requires_mshield: bool
	## Cleric requires Mshield on physical contact; Musketeer's Wound pattern only requires survival.
	func _init(mshield_contact: bool = false) -> void:
		requires_mshield = mshield_contact
	## Hit/Wound capture sees post-damage life. Physical contact has left the victim's Mshield balance intact.
	func test(ctx: RuleContext) -> bool:
		var event := ctx.triggering_event
		var victim := Match.get_unit(event.target.id)
		if victim.actual_life <= 0: return false
		return not requires_mshield or (event.data.get("kind") in [&"bow", &"gore", &"bash"] \
			and victim._counter_value(UnitInfo.MSHIELD_COUNTER) >= 1)

class EnemyHeroStunned extends Condition:
	## The action allowance is a read-only threshold on an opposing deployed hero.
	func test(ctx: RuleContext) -> bool:
		for unit in Match.army:
			if unit != null and unit.player != Match.owner_of(ctx.source) and unit.type == Enum.type.HERO \
					and unit.t_state == Enum.t_state.DEPLOYED and unit._counter_value(UnitInfo.STUN_COUNTER) >= 5:
				return true
		return false

