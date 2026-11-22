## Object-authored adventurer definitions; individual factories are reusable for either player.
class_name AdventurerCatalogue
extends RefCounted

## CardCatalogue appends all twenty adventurers as a fixed owner block after the older roster prefixes.
static func all_units(owner: int) -> Array[UnitInfo]:
	return [porcupine_barbarian(owner), marmot_berserker(owner), dormouse_rogue(owner), flying_squirrel_ranger(owner),
		tamia_hunter(owner), jerboa_scout(owner), dormouse_witch(owner), rat_warlock(owner), red_squirrel_druid(owner),
		porcupine_shaman(owner), mouse_summoner(owner), chinchilla_alchemist(owner), guinea_pig_cleric(owner), marmot_monk(owner), lemming_healer(owner), tamia_bard(owner),
		jerboa_jester(owner), rat_pirate(owner), beaver_blacksmith(owner), guinea_pig_merchant(owner)]

## Adds an ordinary printed FLAG without turning passive abilities into activations or counters.
static func passive(unit: UnitInfo, key: StringName) -> void:
	var prop := Prop.new()
	prop.name = key
	prop.value = 1
	prop.increment = Enum.p_increment.FLAG
	prop.target = Enum.p_target.UNIT
	unit.props.append(prop)

## Barbarian's modifiers follow distinct adjacent friends; Walk remains a normal [AS] command.
static func porcupine_barbarian(owner: int) -> UnitInfo:
	var unit := SynergyCatalogue.card(owner, "porcupine-barbarian", "Porcupine Barbarian", 3, [Enum.region.INTERMEDIATE, Enum.region.FRONT])
	unit.effects.append(Collection.movement(2))
	unit.state_effects.append(AdventurerRules.AdjacentFriends.new())
	return unit

## Summoner's exchange permits the returned friend itself; its independent Mshield command protects friends within one.
static func mouse_summoner(owner: int) -> UnitInfo:
	var unit := SynergyCatalogue.card(owner, "mouse-summoner", "Mouse Summoner", 1, [Enum.region.STARTING])
	unit.effects.append(SynergyRules.command(SynergyRules.phrase(Verbs.mshield(2), SynergyRules.friends_within(1))))
	unit.effects.append(AdventurerRules.summoner_exchange())
	return unit

## Cleric may add one only to an existing adjacent friendly counter type, even at zero; any Return grants one unrestricted Reset choice.
static func guinea_pig_cleric(owner: int) -> UnitInfo:
	var unit := SynergyCatalogue.card(owner, "guinea-pig-cleric", "Guinea Pig Cleric", 3, [Enum.region.INTERMEDIATE])
	unit.effects.append(SynergyRules.command(SynergyRules.phrase(Verbs.change_counter(1),
		AdventurerRules.ExistingCounters.new(SynergyRules.friends_within(1, true)))))
	unit.trigger_effects.append(SynergyRules.observe(&"return_to_hand", QuerySelector.new(), QuerySelector.new(),
		SynergyRules.phrase(Verbs.reset_unit(), QuerySelector.new())))
	return unit

## Berserker's [S] Walk pays self-Stun one without a player action and only lands on an enemy within two; Shield retains [AS].
static func marmot_berserker(owner: int) -> UnitInfo:
	var unit := SynergyCatalogue.card(owner, "marmot-berserker", "Marmot Berserker", 4, [Enum.region.STARTING])
	unit.effects.append(SynergyRules.command(SynergyRules.phrase(Verbs.movement(2, false, true), AdventurerRules.EnemyDestinations.new()), 1, false))
	unit.effects.append(SynergyCatalogue.shield(2, 0))
	return unit

## Rogue deploys on the opponent's Intermediate side and pays one exact counter kind for each independent command.
static func dormouse_rogue(owner: int) -> UnitInfo:
	var unit := SynergyCatalogue.card(owner, "dormouse-rogue", "Dormouse Rogue", 2, [Enum.region.INTERMEDIATE])
	unit.deployment_enemy_side = true
	unit.effects.append(AdventurerRules.rogue_steal())
	var defeat := Effect.Verb.new(&"defeat_enemy", AdventurerRules.defeat_enemy, AdventurerRules.can_defeat_enemy,
		TargetRef.Kind.UNIT, TargetRef.Kind.UNIT)
	unit.effects.append(SynergyRules.command(SynergyRules.phrase(defeat, AdventurerRules.enemies()), 1, true,
		AdventurerRules.counter_cost(Selectors.Self.new())))
	return unit

## Ranger's printed Pierce applies only to Bow; magical protection targets a friend within one.
static func flying_squirrel_ranger(owner: int) -> UnitInfo:
	var unit := SynergyCatalogue.card(owner, "flying-squirrel-ranger", "Flying Squirrel Ranger", 2, [Enum.region.INTERMEDIATE])
	unit.effects.append(Collection.bow_DR(1, 3, false, true))
	unit.effects.append(SynergyRules.command(SynergyRules.phrase(Verbs.mshield(1), SynergyRules.friends_within(1))))
	return unit

## Hunter's printed control strengthens its region; counter payment chooses an adjacent friend before unrestricted-owner Reset within two.
static func tamia_hunter(owner: int) -> UnitInfo:
	var unit := SynergyCatalogue.card(owner, "tamia-hunter", "Tamia Hunter", 2, [Enum.region.STARTING])
	unit.control_bonus = 2
	unit.effects.append(SynergyRules.command(SynergyRules.phrase(Verbs.reset_unit(), DistanceSelector.within(2)), 1, true,
		AdventurerRules.counter_cost(SynergyRules.friends_within(1, true))))
	return unit

## Scout's [A] Walk is Tireless and its live action allowance follows enemy Starting geography, without requiring control.
static func jerboa_scout(owner: int) -> UnitInfo:
	var unit := SynergyCatalogue.card(owner, "jerboa-scout", "Jerboa Scout", 1, [Enum.region.STARTING])
	unit.effects.append(Collection.movement(2, false, true))
	unit.continuous_effects.append(ContinuousEffect.while_self(AdventurerRules.EnemyStarting.new(),
		[Contribution.player_actions(1)], "+1 action while on enemy Starting"))
	return unit

## Witch trades one friendly Ember for permanent Fire damage; the paid Ember never also powers that Fire.
static func dormouse_witch(owner: int) -> UnitInfo:
	var unit := SynergyCatalogue.card(owner, "dormouse-witch", "Dormouse Witch", 2, [Enum.region.INTERMEDIATE])
	unit.effects.append(Collection.movement(2, true))
	unit.effects.append(Collection.fire_DR(1, 2))
	var payment := Effect.CostPhrase.new(Selectors.Self.new(), Verbs.decrement(1),
		Selectors.PropertyOf.new(WoodlandRules.friends(), UnitInfo.EMBER_COUNTER))
	var upgrade := Effect.Verb.new(&"upgrade_fire", AdventurerRules.upgrade_fire, AdventurerRules.can_upgrade_fire,
		TargetRef.Kind.UNIT, TargetRef.Kind.UNIT)
	unit.effects.append(SynergyRules.command(SynergyRules.phrase(upgrade, Selectors.Self.new(), true), 1, true, payment))
	return unit

## Warlock's action-free three-Stun command disables one friendly hand card atomically, then Revives a friendly defeated card.
static func rat_warlock(owner: int) -> UnitInfo:
	var unit := SynergyCatalogue.card(owner, "rat-warlock", "Rat Warlock", 1, [Enum.region.INTERMEDIATE, Enum.region.FRONT])
	unit.effects.append(Collection.stun_DR(1, 2))
	unit.effects.append(SynergyRules.command(SynergyRules.phrase(Verbs.revive(), AdventurerRules.friendly_zone(Enum.t_state.DEFEATED)),
		3, false, AdventurerRules.disable_cost()))
	return unit

## Druid spends Soul to increase maximum life only; its two live modifiers are maximum minus printed two.
static func red_squirrel_druid(owner: int) -> UnitInfo:
	var unit := SynergyCatalogue.card(owner, "red-squirrel-druid", "Red Squirrel Druid", 2, [Enum.region.INTERMEDIATE])
	SynergyRules.resource(unit, &"Soul")
	unit.effects.append(SynergyRules.command(SynergyRules.phrase(Verbs.up_life(0, 1), Selectors.Self.new(), true),
		1, true, SynergyRules.spend(&"Soul", 1)))
	unit.state_effects.append(AdventurerRules.MaximumLife.new())
	return unit

## Alchemist earns one Soul per positive friendly Ember addition, regardless of amount, and spends three on Instant Fire.
static func chinchilla_alchemist(owner: int) -> UnitInfo:
	var unit := SynergyCatalogue.card(owner, "chinchilla-alchemist", "Chinchilla Alchemist", 1, [Enum.region.STARTING])
	SynergyRules.resource(unit, &"Soul")
	unit.trigger_effects.append(SynergyCatalogue.award_on(&"ember_added", &"Soul", 1, QuerySelector.new(), WoodlandRules.friends(),
		null, Condition.EventPositive.new(&"amount")))
	unit.effects.append(SynergyRules.command(SynergyRules.phrase(Verbs.fire(1, true), DistanceSelector.within(3)),
		1, true, SynergyRules.spend(&"Soul", 3)))
	return unit

## Monk's two ordinary protection commands reach any deployed friend, including SELF, with no printed range cap.
static func marmot_monk(owner: int) -> UnitInfo:
	var unit := SynergyCatalogue.card(owner, "marmot-monk", "Marmot Monk", 3, [Enum.region.FRONT])
	unit.effects.append(SynergyRules.command(SynergyRules.phrase(Verbs.shield(1), WoodlandRules.friends())))
	unit.effects.append(SynergyRules.command(SynergyRules.phrase(Verbs.mshield(1), WoodlandRules.friends())))
	return unit

## Healer preserves ordinary Walk and Mend costs; Mend range and ownership share the standard resolver.
static func lemming_healer(owner: int) -> UnitInfo:
	var unit := SynergyCatalogue.card(owner, "lemming-healer", "Lemming Healer", 2, [Enum.region.STARTING, Enum.region.INTERMEDIATE])
	unit.effects.append(Collection.movement(2))
	unit.effects.append(Collection.mend_DR(1, 2))
	return unit

## Bard deploys on the opposing Intermediate side and grants Bow damage to every adjacent unit of either owner.
static func tamia_bard(owner: int) -> UnitInfo:
	var unit := SynergyCatalogue.card(owner, "tamia-bard", "Tamia Bard", 1, [Enum.region.INTERMEDIATE])
	unit.deployment_enemy_side = true
	unit.effects.append(Collection.displacement(1, 2))
	unit.continuous_effects.append(ContinuousEffect.have(Selectors.UnitsOn.new(DistanceSelector.new(1)),
		[Contribution.bow_values(1, 0)], null, null, "Adjacent units: +1 Bow damage"))
	return unit

## Jester captures only a new enemy control transition in its current region; its Instant Bow retains a normal target choice.
static func jerboa_jester(owner: int) -> UnitInfo:
	var unit := SynergyCatalogue.card(owner, "jerboa-jester", "Jerboa Jester", 2, [Enum.region.INTERMEDIATE])
	unit.effects.append(Collection.displacement(1, 3, true))
	var enemy := QuerySelector.new(TargetRef.Kind.PLAYER)
	enemy.relative_owner = Enum.OPP
	var event := Effect.EventPhrase.observe(&"gain_region", enemy, QuerySelector.new(TargetRef.Kind.HEX), TargetRef.Kind.PLAYER, TargetRef.Kind.HEX)
	unit.trigger_effects.append(Effect.on_event(event, SynergyRules.phrase(Verbs.bow(2, 2, true), Selectors.BowTargets.new(2)), AdventurerRules.OwnRegion.new()))
	return unit

## Pirate's printed Fast uses the existing Bash policy; [A] Walk pays a player action without activity.
static func rat_pirate(owner: int) -> UnitInfo:
	var unit := SynergyCatalogue.card(owner, "rat-pirate", "Rat Pirate", 2, [Enum.region.INTERMEDIATE])
	unit.deployment_enemy_side = true
	unit.effects.append(Collection.movement(2, false, true))
	passive(unit, &"fast")
	return unit

## Blacksmith combines the existing Fast and Steady Bash rules and receives the shared implicit Walk one.
static func beaver_blacksmith(owner: int) -> UnitInfo:
	var unit := SynergyCatalogue.card(owner, "beaver-blacksmith", "Beaver Blacksmith", 3, [Enum.region.INTERMEDIATE])
	passive(unit, &"fast")
	passive(unit, &"steady")
	return unit

## Merchant earns Soul from a friend's Die and spends one per adjacent recipient-owned next-Fire sticker.
static func guinea_pig_merchant(owner: int) -> UnitInfo:
	var unit := SynergyCatalogue.card(owner, "guinea-pig-merchant", "Guinea Pig Merchant", 2, [Enum.region.INTERMEDIATE, Enum.region.FRONT])
	SynergyRules.resource(unit, &"Soul")
	var death := Effect.EventPhrase.observe(&"die", SynergyRules.friendly_actors(), QuerySelector.new(TargetRef.Kind.HEX),
		TargetRef.Kind.UNIT, TargetRef.Kind.HEX)
	unit.trigger_effects.append(Effect.on_event(death, SynergyRules.phrase(SynergyRules.counter(&"Soul", 1), Selectors.Self.new(), true)))
	for sticker: StringName in [&"pierce", &"instant"]:
		var verb := Effect.Verb.new(&"grant_next_fire", AdventurerRules.grant_next_fire, AdventurerRules.can_grant_next_fire,
			TargetRef.Kind.UNIT, TargetRef.Kind.UNIT, [sticker])
		unit.effects.append(SynergyRules.command(SynergyRules.phrase(verb, SynergyRules.friends_within(1, true)),
			1, true, SynergyRules.spend(&"Soul", 1)))
	return unit

## Shaman has printed three-Stun hostile Stun and the confirmed unrestricted two-participant Return choice.
static func porcupine_shaman(owner: int) -> UnitInfo:
	var unit := SynergyCatalogue.card(owner, "porcupine-shaman", "Porcupine Shaman", 2, [Enum.region.FRONT])
	var enemies := QuerySelector.new()
	enemies.relative_owner = Enum.OPP
	unit.effects.append(SynergyRules.command(SynergyRules.phrase(Verbs.stun(2, 2, true),
		Selectors.UnitsOn.new(DistanceSelector.within(2)).where(enemies)), 3, false))
	unit.effects.append(AdventurerRules.shaman_return())
	return unit
