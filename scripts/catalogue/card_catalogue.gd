## Small object-authored starter roster used by the first local match.
class_name CardCatalogue
extends RefCounted

## Makes all 86 sprite-backed units available to both players, preserving older roster prefixes and original eight IDs.
## LocalMatchController passes the roster to Match.start_local_match; new cards append without changing earlier identities.
## Seven rat synergy cards append for both owners, preserving every existing starter ID; defaults/captured printed baselines are supplied by Match.
## Keeps only PixelLab-supported entries; the current 86-per-owner order is unchanged, preserving saved IDs while excluding legacy portrait-only cards.
static func starter_army() -> Array[UnitInfo]:
	var army: Array[UnitInfo] = []
	army.append(squirrel_king(1))
	army.append(reed_archer(1))
	army.append(walnut_crab(1))
	army.append(mole_artificer(2))
	army.append(thunder_toad(2))
	army.append(pine_processionary(2))
	army.append(bramble_empress(1))
	army.append(bramble_empress(2))
	for player_id in [1, 2]:
		army.append(rat_dark_mage(player_id))
		army.append(wild_rat(player_id))
		army.append(rat_musketeer(player_id))
		army.append(rat_thief(player_id))
		army.append(rat_warrior(player_id))
		army.append(rat_pikeman(player_id))
		army.append(rat_swordsman(player_id))
	for player_id in [1, 2]: army.append(mouse_warrior(player_id))
	for player_id in [1, 2]:
		army.append(red_squirrel_explorer(player_id))
		army.append(red_squirrel_doctor(player_id))
		army.append(wild_red_squirrel(player_id))
		army.append(wild_beaver(player_id))
		army.append(mole_miner(player_id))
		army.append(wild_mole_rat(player_id))
		army.append(mouse_sorcerer(player_id))
		army.append(wild_mouse(player_id))
		army.append(wild_guinea_pig(player_id))
	for player_id in [1, 2]:
		army.append(wild_marmot(player_id))
		army.append(wild_jerboa(player_id))
		army.append(wild_dormouse(player_id))
		army.append(wild_chinchilla(player_id))
		army.append(wild_lemming(player_id))
		army.append(wild_porcupine(player_id))
		army.append(wild_hedgehog(player_id))
		army.append(wild_flying_squirrel(player_id))
	# Mirror the original asymmetric six cards; all other sprite-backed units already exist for both owners above.
	for player_id in [1, 2]:
		for unit in [squirrel_king(player_id), reed_archer(player_id), walnut_crab(player_id),
				mole_artificer(player_id), thunder_toad(player_id), pine_processionary(player_id)]:
			if not army.any(func(existing: UnitInfo) -> bool: return existing.uuid == unit.uuid): army.append(unit)
	for player_id in [1, 2]:
		army.append(wild_mara(player_id))
		army.append(wild_tamia(player_id))
		army.append(wild_grey_squirrel(player_id))
	for player_id in [1, 2]: army.append_array(SynergyCatalogue.all_units(player_id))
	for player_id in [1, 2]: army.append_array(AdventurerCatalogue.all_units(player_id))
	for player_id in [1, 2]: army.append_array(HeroCatalogue.all_units(player_id))
	return army.filter(BoardCharacter.supports)

## Returns only PixelLab-backed definitions for playable/exported inventories; legacy factories remain available for rule references and focused fixtures.
## Hero definitions are alternatives: the first deployed hero is retained as the player's sole hero choice for the match.
static func all_units(player_id: int) -> Array[UnitInfo]:
	var units: Array[UnitInfo] = [
		wild_mara(player_id),
		wild_tamia(player_id),
		wild_grey_squirrel(player_id),
		rat_dark_mage(player_id),
		wild_rat(player_id),
		rat_musketeer(player_id),
		rat_thief(player_id),
		rat_warrior(player_id),
		rat_pikeman(player_id),
		rat_swordsman(player_id),
		bramble_empress(player_id),
		queen_bee(player_id),
		squirrel_king(player_id),
		mole_artificer(player_id),
		reed_archer(player_id),
		walnut_crab(player_id),
		alps_lone_wolf(player_id),
		pyromaniac_beetle(player_id),
		war_temple(player_id),
		ranged_power_temple(player_id),
		magic_power_temple(player_id),
		magic_range_temple(player_id),
		ranged_range_temple(player_id),
		temple_of_marches(player_id),
		white_wolf(player_id),
		canyon_ibex(player_id),
		crown_breaker(player_id),
		marsh_badger(player_id),
		spring_temple(player_id),
		thunder_toad(player_id),
		pine_processionary(player_id),
		ironhide_boar_pup(player_id),
		prism_moth(player_id),
		canyon_hawk(player_id),
		mouse_warrior(player_id),
		red_squirrel_explorer(player_id),
		red_squirrel_doctor(player_id),
		wild_red_squirrel(player_id),
		wild_beaver(player_id),
		mole_miner(player_id),
		wild_mole_rat(player_id),
		mouse_sorcerer(player_id),
		wild_mouse(player_id),
		wild_guinea_pig(player_id),
		wild_marmot(player_id),
		wild_jerboa(player_id),
		wild_dormouse(player_id),
		wild_hedgehog(player_id),
		wild_chinchilla(player_id),
		wild_lemming(player_id),
		wild_porcupine(player_id),
		wild_flying_squirrel(player_id),
	]
	units.append_array(SynergyCatalogue.all_units(player_id))
	units.append_array(AdventurerCatalogue.all_units(player_id))
	units.append_array(HeroCatalogue.all_units(player_id))
	return units.filter(BoardCharacter.supports)

## Creates a 2-health Starting mage with Fire 2/2 and a death-triggered unrestricted single-unit Reset; implicit Walk 1 is supplied at setup.
static func rat_dark_mage(player_id: int) -> UnitInfo:
	var unit := _plain_card(player_id, "rat-dark-mage", "Rat Dark Mage", 2)
	unit.deploy_regions = [Enum.region.STARTING]
	unit.effects.append(Collection.fire_DR(2, 2))
	unit.trigger_effects.append(RatRules.reset_on_death())
	return unit

## Creates a 3-health Starting Walk-2 unit with a deployed friendly death-trigger amplifier; the amplifier is a static contribution, not a trigger itself.
static func wild_rat(player_id: int) -> UnitInfo:
	var unit := _plain_card(player_id, "wild-rat", "Wild Rat", 3)
	unit.deploy_regions = [Enum.region.STARTING]
	unit.effects.append(Collection.movement(2))
	var friendly := QuerySelector.new()
	friendly.relative_owner = Enum.YOU
	unit.continuous_effects.append(ContinuousEffect.have(friendly, [Contribution.extra_death_trigger()], null, null,
		"Friendly unit death triggers activate one additional time"))
	return unit

## Creates a 2-health Front musketeer with Cannon 1/4 and a friendly reserve recovery choice whenever any enemy dies.
static func rat_musketeer(player_id: int) -> UnitInfo:
	var unit := _plain_card(player_id, "rat-musketeer", "Rat Musketeer", 2)
	unit.deploy_regions = [Enum.region.FRONT]
	unit.effects.append(Collection.cannon_DR(1, 4))
	unit.trigger_effects.append(RatRules.recover_on_enemy_death())
	return unit

## Creates a 1-health Intermediate thief with Walk 2, Instant Bow 1/1 and one Copy choice whenever it wounds a unit.
static func rat_thief(player_id: int) -> UnitInfo:
	var unit := _plain_card(player_id, "rat-thief", "Rat Thief", 1)
	unit.deploy_regions = [Enum.region.INTERMEDIATE]
	unit.effects.append(Collection.movement(2))
	unit.effects.append(Collection.bow_DR(1, 1, true))
	unit.trigger_effects.append(RatRules.copy_on_wound())
	return unit

## Creates a 3-health Starting warrior with Walk 2, its own printed Soul counter, a recovery watcher and an atomic two-Soul deployment action.
static func rat_warrior(player_id: int) -> UnitInfo:
	var unit := _plain_card(player_id, "rat-warrior", "Rat Warrior", 3)
	unit.deploy_regions = [Enum.region.STARTING]
	unit.effects.append(Collection.movement(2))
	var soul := Prop.new()
	soul.name = "Soul"
	soul.increment = Enum.p_increment.COUNTER
	soul.target = Enum.p_target.UNIT
	unit.props.append(soul)
	unit.effects.append(RatRules.soul_deployment())
	unit.trigger_effects.append(RatRules.soul_on_return())
	return unit

## Creates a 2-health Intermediate Walk-3 pikeman with a live, possibly negative physical bonus equal to the remaining deployment difference.
static func rat_pikeman(player_id: int) -> UnitInfo:
	var unit := _plain_card(player_id, "rat-pikeman", "Rat Pikeman", 2)
	unit.deploy_regions = [Enum.region.INTERMEDIATE]
	unit.effects.append(Collection.movement(3))
	unit.state_effects.append(StateModifier.DeploymentDifference.new())
	return unit

## Creates a 3-health Starting Walk-2 swordsman with +1 physical while bashing and a next-turn action reward when its original defender flees.
static func rat_swordsman(player_id: int) -> UnitInfo:
	var unit := _plain_card(player_id, "rat-swordsman", "Rat Swordsman", 3)
	unit.deploy_regions = [Enum.region.STARTING]
	unit.effects.append(Collection.movement(2))
	unit.state_effects.append(StateModifier.new(Condition.BashingEnemy.new(), 1, 0, "While bashing: +1 physical"))
	unit.trigger_effects.append(RatRules.action_on_flee())
	return unit

## starter_army() adds Mouse Engineer to both players, retaining the bramble-empress card identity for art/snapshots.
## Printed Push(2,1)/Pull(1,3) share standard activity costs; Match supplies implicit Walk 1 because neither is movement.
## The 1-life troop deploys in starting/intermediate regions and uses the mapped PixelLab Mouse Engineer appearance.
static func bramble_empress(player_id: int) -> UnitInfo:
	var unit := _plain_card(player_id, "bramble-empress", "Mouse Engineer", 1)
	unit.effects.clear()
	unit.effects.append(Collection.displacement(2, 1))
	unit.effects.append(Collection.displacement(1, 3, true))
	unit.deploy_regions = [Enum.region.STARTING, Enum.region.INTERMEDIATE]
	return unit

## Creates Queen Bee with her reference Move 2 and Bow 3 at range 4 actions.
## Available for alternate test rosters; the tray loads her portrait from the card ID.
static func queen_bee(player_id: int) -> UnitInfo:
	var unit := _plain_card(player_id, "queen-bee", "Queen Bee", 1)
	unit.type = Enum.type.HERO
	unit.effects.clear()
	unit.effects.append(Collection.movement(2))
	unit.effects.append(Collection.bow_DR(3, 4))
	unit.deploy_regions = [Enum.region.INTERMEDIATE]
	return unit

## Creates Squirrel King with Fire 1 at range 3; Match supplies his implicit Walk 1.
## starter_army() uses this starting-region hero for Player 1 and loads his card art.
## Displays Red Squirrel King to match PixelLab; retains the squirrel-king identity, Fire/heal rules and snapshot compatibility.
static func squirrel_king(player_id: int) -> UnitInfo:
	var unit := _plain_card(player_id, "squirrel-king", "Red Squirrel King", 4)
	unit.type = Enum.type.HERO
	unit.effects.clear()
	unit.effects.append(Collection.fire_DR(1, 3))
	unit.trigger_effects.append(Collection.squirrel_king_kindle_trigger())
	unit.deploy_regions = [Enum.region.STARTING]
	return unit

## Creates Mole Artificer with only his reference Bomb 3/2 and Pierce Fire 1/2 actions.
## starter_army() uses this starting-region hero for Player 2 and supplies matching card art.
## Displays Mole King to match PixelLab; retains mole-artificer identity, Bomb/Fire rules and snapshot compatibility.
static func mole_artificer(player_id: int) -> UnitInfo:
	var unit := _plain_card(player_id, "mole-artificer", "Mole King", 4)
	unit.type = Enum.type.HERO
	unit.effects.clear()
	unit.effects.append(Collection.bomb_DR(3, 2))
	unit.effects.append(Collection.fire_DR(1, 2, false, true))
	unit.deploy_regions = [Enum.region.STARTING]
	return unit

## Creates Reed Archer with only her reference Bow 1/4 and Wound-triggered permanent sharpen.
## starter_army() uses this exact action list; her JS definition has no Move/Gore/Push/Pull.
## Displays Mouse Archer to match PixelLab; retains reed-archer identity and its Bow/Wound-upgrade rules.
static func reed_archer(player_id: int) -> UnitInfo:
	var unit := _plain_card(player_id, "reed-archer", "Mouse Archer", 1)
	unit.effects.clear()
	unit.effects.append(Collection.bow_DR(1, 4))
	unit.trigger_effects.append(Collection.reed_archer_sharpen_trigger())
	unit.deploy_regions = [Enum.region.INTERMEDIATE]
	return unit

## Creates Walnut Crab with Guerra's Cannon 2/3 and physical Shield 2 actions.
## starter_army() uses this card without the unrelated Bomb and displacement demo actions.
## Displays Mole Artificier to match PixelLab; retains walnut-crab identity and its Cannon/Shield rules.
static func walnut_crab(player_id: int) -> UnitInfo:
	var unit := _plain_card(player_id, "walnut-crab", "Mole Artificier", 2)
	unit.effects.clear()
	unit.effects.append(Collection.cannon_DR(2, 3))
	unit.effects.append(Collection.shield_DR(2))
	unit.deploy_regions = [Enum.region.INTERMEDIATE]
	return unit

## Creates Alps Lone Wolf with a read-only wounded +2 physical state rule.
## Deck construction can use this factory; the contribution vanishes when life returns to max.
static func alps_lone_wolf(player_id: int) -> UnitInfo:
	var unit := _plain_card(player_id, "alps-lone-wolf", "Alps Lone Wolf", 3)
	unit.effects.clear()
	unit.effects.append(Collection.movement(2))
	unit.state_effects.append(StateModifier.wounded_physical(2))
	return unit

## Creates Pyromaniac Beetle with its deployed +2 magical continuous contribution.
## UnitInfo derives the value on every modifier read and never writes its counters.
static func pyromaniac_beetle(player_id: int) -> UnitInfo:
	var unit := _plain_card(player_id, "pyromaniac-beetle", "Pyromaniac Beetle", 2)
	unit.state_effects.append(StateModifier.permanent(0, 2, "Pyromaniac Beetle"))
	return unit

## Creates War Temple with a live +1 physical aura for friendly units in unresolved opposing Bashes.
## UnitInfo modifier reads discover this deployed source; no counters are written or cached.
static func war_temple(player_id: int) -> UnitInfo:
	var unit := _plain_card(player_id, "war-temple", "War Temple", 3)
	unit.effects.clear()
	unit.type = Enum.type.TEMPLE
	unit.deploy_regions = [Enum.region.INTERMEDIATE]
	var friendly := QuerySelector.new(TargetRef.Kind.UNIT)
	friendly.relative_owner = Enum.YOU
	unit.continuous_effects.append(ContinuousEffect.have(friendly,
		[Contribution.modifiers(1, 0)], null, Condition.BashingEnemy.new(), "Friendly units bashing enemies"))
	return unit

## Creates Guerra JS's ranged-power Temple with a friendly +1 Bow damage grant.
## ContinuousEffect is read by Bow preview and attack capture without editing Bow definitions.
static func ranged_power_temple(player_id: int) -> UnitInfo:
	var unit := _plain_card(player_id, "ranged-power-temple", "Ranged Power Temple", 3)
	unit.type = Enum.type.TEMPLE
	unit.deploy_regions = [Enum.region.INTERMEDIATE]
	unit.effects.clear()
	var friendly := QuerySelector.new(TargetRef.Kind.UNIT)
	friendly.relative_owner = Enum.YOU
	unit.continuous_effects.append(ContinuousEffect.have(friendly, [Contribution.bow_values(1, 0)], null, null, "Friendly Bow +1 damage"))
	return unit

## Creates Guerra JS's magic-power Temple with a friendly +1 Fire damage grant.
## DistanceSelector and CombatResolver read the same live Fire parameters.
static func magic_power_temple(player_id: int) -> UnitInfo:
	var unit := _plain_card(player_id, "magic-power-temple", "Magic Power Temple", 3)
	unit.type = Enum.type.TEMPLE
	unit.deploy_regions = [Enum.region.INTERMEDIATE]
	unit.effects.clear()
	var friendly := QuerySelector.new(TargetRef.Kind.UNIT)
	friendly.relative_owner = Enum.YOU
	unit.continuous_effects.append(ContinuousEffect.have(friendly, [Contribution.action_values(&"fire", [1, 0])], null, null, "Friendly Fire +1 damage"))
	return unit

## Creates Guerra JS's magic-range Temple with a friendly +1 Fire range grant.
## The target preview and resolved action both derive this value from the source aura.
static func magic_range_temple(player_id: int) -> UnitInfo:
	var unit := _plain_card(player_id, "magic-range-temple", "Magic Range Temple", 3)
	unit.type = Enum.type.TEMPLE
	unit.deploy_regions = [Enum.region.INTERMEDIATE]
	unit.effects.clear()
	var friendly := QuerySelector.new(TargetRef.Kind.UNIT)
	friendly.relative_owner = Enum.YOU
	unit.continuous_effects.append(ContinuousEffect.have(friendly, [Contribution.action_values(&"fire", [0, 1])], null, null, "Friendly Fire +1 range"))
	return unit

## Creates Guerra JS's ranged-range Temple with a friendly +1 Bow range grant.
## BowTargets and CombatResolver use the grant without changing printed range.
static func ranged_range_temple(player_id: int) -> UnitInfo:
	var unit := _plain_card(player_id, "ranged-range-temple", "Ranged Range Temple", 3)
	unit.type = Enum.type.TEMPLE
	unit.deploy_regions = [Enum.region.INTERMEDIATE]
	unit.effects.clear()
	var friendly := QuerySelector.new(TargetRef.Kind.UNIT)
	friendly.relative_owner = Enum.YOU
	unit.continuous_effects.append(ContinuousEffect.have(friendly, [Contribution.bow_values(0, 1)], null, null, "Friendly Bow +1 range"))
	return unit

## Creates Temple of Marches with a friendly +1 Move range grant.
## DistanceSelector previews and CombatResolver legality read the derived range.
static func temple_of_marches(player_id: int) -> UnitInfo:
	var unit := _plain_card(player_id, "temple-marches", "Temple of Marches", 2)
	unit.type = Enum.type.TEMPLE
	unit.deploy_regions = [Enum.region.FRONT]
	unit.effects.clear()
	var friendly := QuerySelector.new(TargetRef.Kind.UNIT)
	friendly.relative_owner = Enum.YOU
	unit.continuous_effects.append(ContinuousEffect.have(friendly, [Contribution.action_values(&"move", [1])], null, null, "Friendly Move +1 range"))
	return unit

## Creates White Wolf with its inactive-source adjacent-friendly Bow aura and Bash modifier.
## Its source condition is rechecked on reads; its recipients receive the Bow values live.
static func white_wolf(player_id: int) -> UnitInfo:
	var unit := _plain_card(player_id, "white-wolf", "White Wolf", 2)
	var friendly := QuerySelector.new(TargetRef.Kind.UNIT)
	friendly.relative_owner = Enum.YOU
	var adjacent_friendly := Selectors.UnitsOn.new(DistanceSelector.within(1)).where(friendly)
	unit.continuous_effects.append(ContinuousEffect.have(adjacent_friendly,
		[Contribution.bow_values(1, 1)], Condition.Active.new(false), null, "Adjacent friendly Bow +1/+1 while inactive"))
	unit.state_effects.append(StateModifier.new(Condition.Bashing.new(), 1, -1, "Bashing +1/-1"))
	return unit

## Creates Canyon Ibex with its +2 physical modifier while participating in a Bash.
## StateModifier reads pending Bash identity and does not store the bonus.
static func canyon_ibex(player_id: int) -> UnitInfo:
	var unit := _plain_card(player_id, "canyon-ibex", "Canyon Ibex", 1)
	unit.effects.clear()
	unit.effects.append(Collection.movement(3))
	unit.state_effects.append(StateModifier.new(Condition.Bashing.new(), 2, 0, "Bashing +2 physical"))
	return unit

## Creates Crown Breaker with +2 physical only while bashing an opposing Hero.
## The recipient condition is evaluated at each live modifier read.
static func crown_breaker(player_id: int) -> UnitInfo:
	var unit := _plain_card(player_id, "crown-breaker", "Crown Breaker", 3)
	unit.effects.clear()
	unit.effects.append(Collection.movement(2))
	unit.state_effects.append(StateModifier.new(Condition.BashingEnemyHero.new(), 2, 0, "Bashing an enemy Hero"))
	return unit

## Creates Marsh Badger with its shielded -2 physical condition and Move 2 action.
## The modifier returns when temporary Shield counters are present and disappears after consumption.
static func marsh_badger(player_id: int) -> UnitInfo:
	var unit := _plain_card(player_id, "marsh-badger", "Marsh Badger", 4)
	unit.effects.clear()
	unit.effects.append(Collection.movement(2))
	unit.state_effects.append(StateModifier.new(Condition.Shielded.new(), -2, 0, "Shielded -2 physical"))
	return unit

## Creates Spring Temple with its immovable body and costed Mend 1 within radius 3.
## The normal action runner handles its activity payment, ally choice, and life mutation.
static func spring_temple(player_id: int) -> UnitInfo:
	var unit := _plain_card(player_id, "spring-temple", "Spring Temple", 3)
	unit.type = Enum.type.TEMPLE
	unit.deploy_regions = [Enum.region.STARTING, Enum.region.INTERMEDIATE]
	unit.effects.clear()
	unit.effects.append(Collection.mend_DR(1, 3))
	return unit

## Creates Thunder Toad with hostile Stun 1/1 and its captured +1 max/-1 current-life trigger.
## The trigger ignores SELF's ordinary activity-cost Stun and responds only to hostile Stun.
## Displays Red Squirrel Climber to match PixelLab; retains thunder-toad identity and hostile-Stun/charge rules.
static func thunder_toad(player_id: int) -> UnitInfo:
	var unit := _plain_card(player_id, "thunder-toad", "Red Squirrel Climber", 3)
	unit.effects.clear()
	unit.effects.append(Collection.stun_DR(1, 1))
	unit.trigger_effects.append(Collection.thunder_toad_charge_trigger())
	unit.deploy_regions = [Enum.region.STARTING]
	return unit

## Creates Pine Processionary with Move 2 and its captured self-death Revive trigger.
## The runner only offers previously defeated allied non-heroes and excludes this source.
## Displays Mouse Necromancer with its pine-processionary identity, movement and owner +2 deployment death trigger.
static func pine_processionary(player_id: int) -> UnitInfo:
	var unit := _plain_card(player_id, "pine-processionary", "Mouse Necromancer", 1)
	unit.effects.clear()
	unit.effects.append(Collection.movement(2))
	unit.trigger_effects.append(Collection.pine_processionary_trigger())
	unit.deploy_regions = [Enum.region.STARTING]
	return unit

## Creates Ironhide Boar Pup with a runner-owned, cost-free Hit trigger.
## Match's RulesRunner captures Hit events and grants both persistent counters once per occurrence.
static func ironhide_boar_pup(player_id: int) -> UnitInfo:
	var unit := _plain_card(player_id, "ironhide-boar-pup", "Ironhide Boar Pup", 2)
	unit.trigger_effects.append(Collection.ironhide_boar_pup_trigger())
	return unit

## Creates Prism Moth with an Instant Bow and a Bash-engagement modifier trigger.
## RulesRunner grants permanent +1 counters on each Bash target-stage event naming this unit.
static func prism_moth(player_id: int) -> UnitInfo:
	var unit := _plain_card(player_id, "prism-moth", "Prism Moth", 1)
	unit.effects.clear()
	unit.effects.append(Collection.movement(2, true))
	unit.effects.append(Collection.bow_DR(1, 2, true))
	unit.trigger_effects.append(Collection.prism_moth_trigger())
	return unit

## Creates Canyon Hawk with its printed Steady passive flag.
## CombatResolver reads this identity during Bash calculation; no effect is repeatedly run.
static func canyon_hawk(player_id: int) -> UnitInfo:
	var unit := _plain_card(player_id, "canyon-hawk", "Canyon Hawk", 3)
	unit.effects.clear()
	unit.effects.append(Collection.movement(2, true))
	var steady := Prop.new()
	steady.name = &"steady"
	steady.increment = Enum.p_increment.FLAG
	steady.target = Enum.p_target.UNIT
	steady.value = 1
	unit.props.append(steady)
	return unit

## Creates the 3-life Starting Mouse Warrior with Pull 2/2 and an exact incoming-Bash retaliation trigger; setup supplies implicit Walk 1.
static func mouse_warrior(player_id: int) -> UnitInfo:
	var unit := _plain_card(player_id, "mouse-warrior", "Mouse Warrior", 3)
	unit.deploy_regions = [Enum.region.STARTING]
	unit.effects.append(Collection.displacement(2, 2, true))
	unit.trigger_effects.append(WoodlandRules.retaliate_on_bash())
	return unit

## Explorer deploys Starting/Front, Walks 2 and gains its own physical/magic counters from captured friendly life increases.
static func red_squirrel_explorer(player_id: int) -> UnitInfo:
	var unit := _plain_card(player_id, "red-squirrel-explorer", "Red Squirrel Explorer", 2)
	unit.deploy_regions = [Enum.region.STARTING, Enum.region.FRONT]
	unit.effects.append(Collection.movement(2))
	unit.trigger_effects.append(WoodlandRules.grow_with_friends())
	return unit

## Doctor deploys Intermediate/Front, Walks 2 and pays current life plus activity to heal and enlarge a selected friend.
static func red_squirrel_doctor(player_id: int) -> UnitInfo:
	var unit := _plain_card(player_id, "red-squirrel-doctor", "Red Squirrel Doctor", 4)
	unit.deploy_regions = [Enum.region.INTERMEDIATE, Enum.region.FRONT]
	unit.effects.append(Collection.movement(2))
	unit.effects.append(WoodlandRules.doctor_heal())
	return unit

## Wild Red Squirrel is an Intermediate Walk-3 troop whose Instant Bow damage is the captured friendly maximum-life increase.
static func wild_red_squirrel(player_id: int) -> UnitInfo:
	var unit := _plain_card(player_id, "wild-red-squirrel", "Wild Red Squirrel", 1)
	unit.deploy_regions = [Enum.region.INTERMEDIATE]
	unit.effects.append(Collection.movement(3))
	unit.trigger_effects.append(WoodlandRules.bow_on_growth())
	return unit

## Wild Beaver carries the newly specified Fire/Bomb rules without changing the existing Mole Artificier card or identity.
static func wild_beaver(player_id: int) -> UnitInfo:
	var unit := _plain_card(player_id, "wild-beaver", "Wild Beaver", 2)
	unit.deploy_regions = [Enum.region.INTERMEDIATE]
	unit.effects.append(Collection.fire_DR(1, 2, false, true))
	unit.state_effects.append(StateModifier.permanent(0, 2, "Magical protection"))
	unit.trigger_effects.append(WoodlandRules.bomb_after_walk())
	return unit

## Miner deploys in opponent-side Intermediate regions under ordinary control/vacancy rules; First Strike and friendly Bomb-contact healing are independent effects.
static func mole_miner(player_id: int) -> UnitInfo:
	var unit := _plain_card(player_id, "mole-miner", "Mole Miner", 3)
	unit.deploy_regions = [Enum.region.INTERMEDIATE]
	unit.deployment_enemy_side = true
	unit.effects.append(Collection.movement(2))
	unit.props.append(_passive(&"first-strike"))
	unit.trigger_effects.append(WoodlandRules.heal_bomb_victim())
	return unit

## Wild Mole Rat deploys Starting/Intermediate with +2 magical and a defending-Bash Bomb-then-free-movement sequence; setup supplies Walk 1.
static func wild_mole_rat(player_id: int) -> UnitInfo:
	var unit := _plain_card(player_id, "wild-mole-rat", "Wild Mole Rat", 1)
	unit.deploy_regions = [Enum.region.STARTING, Enum.region.INTERMEDIATE]
	unit.state_effects.append(StateModifier.permanent(0, 2, "Magical protection"))
	unit.trigger_effects.append(WoodlandRules.bomb_and_flee())
	return unit

## Sorcerer uses Fire 2/2 and a current/max-life AC to grant Bow damage/range upgrades to a selected friendly deployed unit.
static func mouse_sorcerer(player_id: int) -> UnitInfo:
	var unit := _plain_card(player_id, "mouse-sorcerer", "Mouse Sorcerer", 2)
	unit.deploy_regions = [Enum.region.STARTING]
	unit.effects.append(Collection.fire_DR(2, 2))
	unit.effects.append(WoodlandRules.sorcerer_upgrade())
	return unit

## Wild Mouse owns zero initial Soul and three explicit activated effects: borrow Soul, upgrade a chosen ability, or Reset any unit.
static func wild_mouse(player_id: int) -> UnitInfo:
	var unit := _plain_card(player_id, "wild-mouse", "Wild Mouse", 2)
	unit.deploy_regions = [Enum.region.INTERMEDIATE]
	var soul := Prop.new()
	soul.name = "Soul"
	soul.increment = Enum.p_increment.COUNTER
	soul.target = Enum.p_target.UNIT
	unit.props.append(soul)
	unit.effects.append(WoodlandRules.borrow_souls())
	unit.effects.append(WoodlandRules.soul_upgrade())
	unit.effects.append(WoodlandRules.soul_reset())
	return unit

## Wild Guinea Pig pays current life to enlarge its maximum and heals itself on friendly Wild physical contacts; setup supplies Walk 1.
static func wild_guinea_pig(player_id: int) -> UnitInfo:
	var unit := _plain_card(player_id, "wild-guinea-pig", "Wild Guinea Pig", 2)
	unit.deploy_regions = [Enum.region.INTERMEDIATE]
	unit.effects.append(WoodlandRules.guinea_growth())
	unit.trigger_effects.append(WoodlandRules.heal_on_wild_hit())
	return unit

## Wild Marmot deploys Starting, Walks 2 and Returns another friendly adjacent unit through the standard activity/action policy.
static func wild_marmot(player_id: int) -> UnitInfo:
	var unit := _plain_card(player_id, "wild-marmot", "Wild Marmot", 2)
	unit.deploy_regions = [Enum.region.STARTING]
	unit.effects.append(Collection.movement(2))
	unit.effects.append(WildRules.return_friend())
	return unit

## Wild Jerboa deploys Intermediate with Pull 1/2 and returns the exact enemy declaring Bash against it; setup supplies Walk 1.
static func wild_jerboa(player_id: int) -> UnitInfo:
	var unit := _plain_card(player_id, "wild-jerboa", "Wild Jerboa", 1)
	unit.deploy_regions = [Enum.region.INTERMEDIATE]
	unit.effects.append(Collection.displacement(1, 2, true))
	unit.trigger_effects.append(WildRules.return_bash_attacker())
	return unit

## Wild Dormouse deploys Front with Bow 2/2 and an own-Deploy choice to Return one adjacent unit of either owner.
static func wild_dormouse(player_id: int) -> UnitInfo:
	var unit := _plain_card(player_id, "wild-dormouse", "Wild Dormouse", 2)
	unit.deploy_regions = [Enum.region.FRONT]
	unit.effects.append(Collection.bow_DR(2, 2))
	unit.trigger_effects.append(WildRules.return_on_deploy())
	return unit

## Wild Hedgehog deploys Intermediate, Walks 2 and gains persistent +1/+1 when it receives physical or magical attack Hit.
static func wild_hedgehog(player_id: int) -> UnitInfo:
	var unit := _plain_card(player_id, "wild-hedgehog", "Wild Hedgehog", 2)
	unit.deploy_regions = [Enum.region.INTERMEDIATE]
	unit.effects.append(Collection.movement(2))
	unit.trigger_effects.append(WildRules.grow_on_received_hit())
	return unit

## Wild Chinchilla deploys Starting/Intermediate with Fire 2/2, an own-Deploy resource grant and captured death replacement through a friendly Return.
static func wild_chinchilla(player_id: int) -> UnitInfo:
	var unit := _plain_card(player_id, "wild-chinchilla", "Wild Chinchilla", 1)
	unit.deploy_regions = [Enum.region.STARTING, Enum.region.INTERMEDIATE]
	unit.effects.append(Collection.fire_DR(2, 2))
	unit.trigger_effects.append(WildRules.deployment_on_deploy())
	unit.trigger_effects.append(WildRules.replace_on_death())
	return unit

## Wild Lemming deploys in opposing Intermediate with three extra ETB Stun, plus normal deployment Stun, and Instant Fire 1 against any deployed enemy.
## Omitted printed range is unlimited; the explicit enemy UNIT query projects into Fire's HEX contract without exposing empty/friendly-only hexes.
static func wild_lemming(player_id: int) -> UnitInfo:
	var unit := _plain_card(player_id, "wild-lemming", "Wild Lemming", 2)
	unit.deploy_regions = [Enum.region.INTERMEDIATE]
	unit.deployment_enemy_side = true
	var enemy := QuerySelector.new()
	enemy.relative_owner = Enum.OPP
	enemy.state = Enum.t_state.DEPLOYED
	unit.effects.append(Collection.with_action_policy(Effect.ConsequencePhrase.new(Selectors.Self.new(),
		Verbs.fire(1, true), Selectors.HexOf.new(enemy)), false, false, null, true))
	unit.trigger_effects.append(WildRules.stun_on_deploy())
	return unit

## Wild Porcupine deploys Starting/Intermediate with Bow 3/1, zero printed Soul, a unit→counter→X harvesting AC and unlimited Soul-to-Stun AC.
## Harvest addresses positive stored counters on deployed friends (including SELF), not flags or derived continuous values.
static func wild_porcupine(player_id: int) -> UnitInfo:
	var unit := _plain_card(player_id, "wild-porcupine", "Wild Porcupine", 3)
	unit.deploy_regions = [Enum.region.STARTING, Enum.region.INTERMEDIATE]
	var soul := Prop.new()
	soul.name = &"Soul"
	soul.increment = Enum.p_increment.COUNTER
	soul.target = Enum.p_target.UNIT
	unit.props.append(soul)
	unit.effects.append(Collection.bow_DR(3, 1))
	unit.effects.append(WildRules.harvest_counters(WoodlandRules.friends()))
	unit.effects.append(WildRules.stun_with_souls())
	return unit

## Wild Flying Squirrel deploys Starting with an explicit two-Stun Fly 3 payment and a derived +3 physical while bashing.
static func wild_flying_squirrel(player_id: int) -> UnitInfo:
	var unit := _plain_card(player_id, "wild-flying-squirrel", "Wild Flying Squirrel", 1)
	unit.deploy_regions = [Enum.region.STARTING]
	unit.effects.append(WildRules.tiring_fly())
	unit.state_effects.append(StateModifier.new(Condition.Bashing.new(), 3, 0, "While bashing: +3 physical"))
	return unit

## Mara deploys Intermediate with Cannon 2/2 and independent friendly/enemy Disable growth; setup supplies implicit Walk 1.
static func wild_mara(player_id: int) -> UnitInfo:
	var unit := _plain_card(player_id, "wild-mara", "Wild Mara", 2)
	unit.deploy_regions = [Enum.region.INTERMEDIATE]
	unit.effects.append(Collection.cannon_DR(2, 2))
	unit.trigger_effects.append(WildRules.grow_on_disable(true))
	unit.trigger_effects.append(WildRules.grow_on_disable(false))
	return unit

## Tamia deploys Starting with Walk 2 and a normal action converting a chosen non-hero reserve into one remaining deployment.
static func wild_tamia(player_id: int) -> UnitInfo:
	var unit := _plain_card(player_id, "wild-tamia", "Wild Tamia", 2)
	unit.deploy_regions = [Enum.region.STARTING]
	unit.effects.append(Collection.movement(2))
	unit.effects.append(WildRules.disable_for_deployment())
	return unit

## Grey Squirrel deploys Starting/Intermediate with Walk 2 and an Action-free, activity-costed adjacent friendly Bow grant through End.
static func wild_grey_squirrel(player_id: int) -> UnitInfo:
	var unit := _plain_card(player_id, "wild-grey-squirrel", "Wild Grey Squirrel", 1)
	unit.deploy_regions = [Enum.region.STARTING, Enum.region.INTERMEDIATE]
	unit.effects.append(Collection.movement(2))
	unit.effects.append(WildRules.prepare_bow())
	return unit

## Creates real passive flags (such as First Strike); name groups like Wild or squirrel are queried from the display name instead.
static func _passive(key: StringName) -> Prop:
	var result := Prop.new()
	result.name = key
	result.increment = Enum.p_increment.FLAG
	result.target = Enum.p_target.UNIT
	result.value = 1
	return result

## Creates a troop without movement or name-group flags; Match supplies implicit Walk 1 and selectors query its display name.
## Card factories author printed Move/Fly actions directly, and temples remain immovable.
static func _plain_card(player_id: int, card_id: String, display_name: String, life: int) -> UnitInfo:
	var unit := UnitInfo.new()
	unit.uuid = "%s-p%d" % [card_id, player_id]
	unit.name = display_name
	unit.player = player_id
	unit.type = Enum.type.TROOP
	unit.max_life = life
	unit.actual_life = life
	return unit

