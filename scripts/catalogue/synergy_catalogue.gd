## Approved PixelLab card definitions from docs/MY_28_UNIT_PROPOSALS.md; CardCatalogue appends them without changing older IDs.
class_name SynergyCatalogue
extends RefCounted

## CardCatalogue appends this fixed, owner-paired block after every older roster identity; all definitions remain reusable.
static func all_units(owner: int) -> Array[UnitInfo]:
	return [grey_squirrel_archer(owner), grey_squirrel_naturalist(owner), grey_squirrel_crossbowman(owner),
		grey_squirrel_pikeman(owner), grey_squirrel_warrior(owner), grey_squirrel_guardian(owner),
		grey_squirrel_musketeer(owner), grey_squirrel_wizard(owner), beaver_warrior(owner), beaver_guardian(owner),
		beaver_architect(owner), jerboa_banner_bearer(owner), jerboa_warrior(owner), jerboa_cannoneer(owner),
		jerboa_assassin(owner), jerboa_pyromancer(owner), jerboa_soldier(owner), jerboa_courier(owner),
		marmot_halberdier(owner), marmot_paladin(owner), chinchilla_soldier(owner), chinchilla_sentinel(owner),
		tamia_knight(owner), tamia_warrior(owner), tamia_archer(owner), tamia_crossbowman(owner),
		tamia_red_mage(owner), tamia_blue_mage(owner)]

## Constructs a troop's printed body and region list; Match supplies implicit Walk and captures its Reset baseline later.
static func card(owner: int, key: String, title: String, life: int, regions: Array[int]) -> UnitInfo:
	var unit := UnitInfo.new()
	unit.player = owner
	unit.uuid = "%s-p%d" % [key, owner]
	unit.name = title
	unit.max_life = life
	unit.actual_life = life
	unit.deploy_regions = regions.duplicate()
	return unit

## Counter-award triggers use the observed source/target identity, with optional ownership and attack-family filters.
static func award_on(action: StringName, key: StringName, amount: int, actors: Selector = null,
		targets: Selector = null, recipient: Selector = null, guard: Condition = null) -> Effect:
	return SynergyRules.observe(action, actors if actors != null else Selectors.Self.new(),
		targets if targets != null else QuerySelector.new(), SynergyRules.phrase(SynergyRules.counter(key, amount),
		recipient if recipient != null else Selectors.Self.new(), true), guard)

## Ranged Shield targets friends within the printed radius; the enclosing command owns the normal [AS] payment.
static func shield(amount: int, radius: int) -> Effect:
	return SynergyRules.command(SynergyRules.phrase(Verbs.shield(amount), SynergyRules.friends_within(radius)))

## Creates the archer's Bow and persistent control reward for each actual wound it deals.
static func grey_squirrel_archer(owner: int) -> UnitInfo:
	var unit := card(owner, "grey-squirrel-archer", "Grey Squirrel Archer", 2, [Enum.region.INTERMEDIATE])
	unit.effects.append(Collection.bow_DR(1, 4))
	unit.trigger_effects.append(award_on(&"wound", UnitInfo.CONTROL_COUNTER, 2))
	return unit

## Naturalist pays two self-Stun and no action for hostile Stun, or ordinary [AS] to Reset one adjacent friend.
static func grey_squirrel_naturalist(owner: int) -> UnitInfo:
	var unit := card(owner, "grey-squirrel-naturalist", "Grey Squirrel Naturalist", 2, [Enum.region.STARTING, Enum.region.INTERMEDIATE])
	var enemies := QuerySelector.new()
	enemies.relative_owner = Enum.OPP
	unit.effects.append(SynergyRules.command(SynergyRules.phrase(Verbs.stun(2, 1, true),
		Selectors.UnitsOn.new(DistanceSelector.within(1)).where(enemies)), 2, false))
	unit.effects.append(SynergyRules.command(SynergyRules.phrase(Verbs.reset_unit(), SynergyRules.friends_within(1, true))))
	return unit

## Crossbowman gains two projectiles on each own Deploy; firing spends one with activity atomically and Reset alone gives no ammunition.
static func grey_squirrel_crossbowman(owner: int) -> UnitInfo:
	var unit := card(owner, "grey-squirrel-crossbowman", "Grey Squirrel Crossbowman", 2, [Enum.region.INTERMEDIATE, Enum.region.FRONT])
	SynergyRules.resource(unit, UnitInfo.PROJECTILE_COUNTER)
	unit.trigger_effects.append(SynergyRules.on_deploy(UnitInfo.PROJECTILE_COUNTER, 2))
	unit.effects.append(SynergyRules.command(SynergyRules.phrase(Verbs.bow(4, 2), Selectors.BowTargets.new(2)),
		1, true, SynergyRules.spend(UnitInfo.PROJECTILE_COUNTER, 1)))
	return unit

## Pikeman contributes one live player action while bashing; Player retains spent actions independently to prevent Bash reentry refills.
static func grey_squirrel_pikeman(owner: int) -> UnitInfo:
	var unit := card(owner, "grey-squirrel-pikeman", "Grey Squirrel Pikeman", 3, [Enum.region.INTERMEDIATE])
	unit.effects.append(Collection.displacement(2, 2, true))
	unit.continuous_effects.append(ContinuousEffect.while_self(Condition.Bashing.new(),
		[Contribution.player_actions(1)], "+1 player action while bashing"))
	return unit

## Warrior earns Soul from every friendly Bow wound, then spends two on an in-range exact-ability +1/+0 upgrade.
static func grey_squirrel_warrior(owner: int) -> UnitInfo:
	var unit := card(owner, "grey-squirrel-warrior", "Grey Squirrel Warrior", 3, [Enum.region.STARTING, Enum.region.INTERMEDIATE])
	SynergyRules.resource(unit, &"Soul")
	unit.effects.append(Collection.movement(2))
	unit.effects.append(SynergyRules.upgrade(2, 2))
	unit.trigger_effects.append(award_on(&"wound", &"Soul", 1, SynergyRules.friendly_actors(), null, null, SynergyRules.AttackKind.new(&"bow")))
	return unit

## Guardian Shields within one and grants a global damage-only Bow aura to all friends whose live physical reaches three.
static func grey_squirrel_guardian(owner: int) -> UnitInfo:
	var unit := card(owner, "grey-squirrel-guardian", "Grey Squirrel Guardian", 3, [Enum.region.STARTING, Enum.region.INTERMEDIATE])
	unit.effects.append(shield(2, 1))
	unit.continuous_effects.append(ContinuousEffect.have(WoodlandRules.friends(),
		[Contribution.bow_values(1, 0)], null, SynergyRules.PhysicalAtLeast.new(3), "Friends with physical 3+: Bow +1/+0"))
	return unit

## Musketeer receives deployment ammunition and refunds one projectile for each friendly wound it actually causes.
static func grey_squirrel_musketeer(owner: int) -> UnitInfo:
	var unit := card(owner, "grey-squirrel-musketeer", "Grey Squirrel Musketeer", 2, [Enum.region.FRONT])
	SynergyRules.resource(unit, UnitInfo.PROJECTILE_COUNTER)
	unit.trigger_effects.append(SynergyRules.on_deploy(UnitInfo.PROJECTILE_COUNTER, 2))
	unit.effects.append(SynergyRules.command(SynergyRules.phrase(Verbs.cannon(3, 3), DistanceSelector.within(3)),
		1, true, SynergyRules.spend(UnitInfo.PROJECTILE_COUNTER, 1)))
	unit.trigger_effects.append(award_on(&"wound", UnitInfo.PROJECTILE_COUNTER, 1, null, WoodlandRules.friends()))
	return unit

## Wizard observes the Reset recipient's ownership and spends earned Soul to Return one adjacent unit of either owner.
static func grey_squirrel_wizard(owner: int) -> UnitInfo:
	var unit := card(owner, "grey-squirrel-wizard", "Grey Squirrel Wizard", 2, [Enum.region.STARTING])
	SynergyRules.resource(unit, &"Soul")
	unit.trigger_effects.append(award_on(&"reset", &"Soul", 1, QuerySelector.new(), WoodlandRules.friends()))
	unit.effects.append(SynergyRules.command(SynergyRules.phrase(Verbs.return_to_hand(), DistanceSelector.new(1)),
		1, true, SynergyRules.spend(&"Soul", 1)))
	return unit

## Warrior has its own magical protection and supplies an independent live +1 magical to friendly occupants of inert bomb hexes.
static func beaver_warrior(owner: int) -> UnitInfo:
	var unit := card(owner, "beaver-warrior", "Beaver Warrior", 3, [Enum.region.INTERMEDIATE])
	unit.effects.append(Collection.movement(2))
	unit.state_effects.append(StateModifier.permanent(0, 1, "Beaver Warrior"))
	unit.continuous_effects.append(ContinuousEffect.have(WoodlandRules.friends(), [Contribution.modifiers(0, 1)],
		null, SynergyRules.OnUnlitBomb.new(), "Friends on unlit bombs: +1 magical"))
	return unit

## Guardian's global friendly magical aura reads physical thresholds only; its Shield remains limited to range one.
static func beaver_guardian(owner: int) -> UnitInfo:
	var unit := card(owner, "beaver-guardian", "Beaver Guardian", 3, [Enum.region.STARTING, Enum.region.INTERMEDIATE])
	unit.effects.append(shield(3, 1))
	unit.continuous_effects.append(ContinuousEffect.have(WoodlandRules.friends(),
		[Contribution.modifiers(0, 1)], null, SynergyRules.PhysicalAtLeast.new(3), "Friends with physical 3+: +1 magical"))
	return unit

## Architect converts Soul into Bomb 3 and independently earns one Soul after its own successful Defuse.
static func beaver_architect(owner: int) -> UnitInfo:
	var unit := card(owner, "beaver-architect", "Beaver Architect", 2, [Enum.region.INTERMEDIATE])
	SynergyRules.resource(unit, &"Soul")
	unit.effects.append(SynergyRules.command(SynergyRules.phrase(Verbs.bomb_throw(3, 3), DistanceSelector.within(3)),
		1, true, SynergyRules.spend(&"Soul", 1)))
	unit.effects.append(Collection.defuse_bomb(2))
	var event := Effect.EventPhrase.observe(&"bomb_defuse", Selectors.Self.new(), QuerySelector.new(TargetRef.Kind.HEX),
		TargetRef.Kind.UNIT, TargetRef.Kind.HEX)
	unit.trigger_effects.append(Effect.on_event(event, SynergyRules.phrase(SynergyRules.counter(&"Soul", 1), Selectors.Self.new(), true)))
	return unit

## Banner Bearer supports every adjacent friendly participant of an unresolved Bash, without displacement history requirements.
static func jerboa_banner_bearer(owner: int) -> UnitInfo:
	var unit := card(owner, "jerboa-banner-bearer", "Jerboa Banner Bearer", 2, [Enum.region.INTERMEDIATE])
	unit.effects.append(Collection.movement(2))
	unit.continuous_effects.append(ContinuousEffect.have(SynergyRules.friends_within(1, true),
		[Contribution.modifiers(1, 0)], null, Condition.Bashing.new(), "Adjacent bashing friends: +1 physical"))
	return unit

## Warrior's +3 physical is derived only while its actual opposing Bash participant has stored Stun.
static func jerboa_warrior(owner: int) -> UnitInfo:
	var unit := card(owner, "jerboa-warrior", "Jerboa Warrior", 3, [Enum.region.INTERMEDIATE])
	unit.effects.append(Collection.movement(2))
	unit.state_effects.append(StateModifier.new(SynergyRules.BashingStunned.new(), 3, 0, "Bashing a stunned enemy"))
	return unit

## Cannoneer awards Ember to the exact friendly wound recipient, retaining that identity through lethal damage and followups.
static func jerboa_cannoneer(owner: int) -> UnitInfo:
	var unit := card(owner, "jerboa-cannoneer", "Jerboa Cannoneer", 2, [Enum.region.INTERMEDIATE])
	unit.effects.append(Collection.cannon_DR(1, 3))
	unit.trigger_effects.append(award_on(&"wound", UnitInfo.EMBER_COUNTER, 1, null, WoodlandRules.friends(),
		Selectors.Reference.new(Selectors.Anchor.EVENT_TARGET)))
	return unit

## Assassin combines existing Steady/First Strike passives with Walk 3; it adds no new Bash action family.
static func jerboa_assassin(owner: int) -> UnitInfo:
	var unit := card(owner, "jerboa-assassin", "Jerboa Assassin", 2, [Enum.region.INTERMEDIATE, Enum.region.FRONT])
	unit.effects.append(Collection.movement(3))
	for key in [&"steady", &"first-strike"]:
		var prop := Prop.new()
		prop.name = key
		prop.value = 1
		prop.increment = Enum.p_increment.FLAG
		prop.target = Enum.p_target.UNIT
		unit.props.append(prop)
	return unit

## Pyromancer turns actual zero-loss contact into one chosen adjacent friend's Ember, with no new resource or range limit invented.
static func jerboa_pyromancer(owner: int) -> UnitInfo:
	var unit := card(owner, "jerboa-pyromancer", "Jerboa Pyromancer", 2, [Enum.region.INTERMEDIATE])
	unit.effects.append(Collection.fire_DR(1, 3))
	unit.trigger_effects.append(SynergyRules.observe(&"hit", Selectors.Self.new(), QuerySelector.new(),
		SynergyRules.phrase(SynergyRules.counter(UnitInfo.EMBER_COUNTER, 1), SynergyRules.friends_within(1, true)),
		Condition.EventFact.new(&"wounded", false)))
	return unit

## Soldier gains one temporary magical protection from each actual friendly Fire contact, not from declaration, misses or immunity.
static func jerboa_soldier(owner: int) -> UnitInfo:
	var unit := card(owner, "jerboa-soldier", "Jerboa Soldier", 3, [Enum.region.STARTING, Enum.region.INTERMEDIATE])
	unit.effects.append(Collection.displacement(1, 3))
	unit.trigger_effects.append(award_on(&"hit", UnitInfo.TEMP_MAGICAL_COUNTER, 1, SynergyRules.friendly_actors(), null, null,
		SynergyRules.AttackKind.new(&"fire")))
	return unit

## Courier's [S] command chooses any owner's in-range positive counter and moves up to two of that kind to another in-range unit.
static func jerboa_courier(owner: int) -> UnitInfo:
	var unit := card(owner, "jerboa-courier", "Jerboa Courier", 2, [Enum.region.STARTING, Enum.region.INTERMEDIATE])
	unit.effects.append(Collection.movement(2))
	unit.effects.append(SynergyRules.transfer(Selectors.UnitsOn.new(DistanceSelector.within(2))))
	return unit

## Halberdier pays ordinary activity and one friendly sacrifice atomically before granting persistent +1/+1 to SELF.
static func marmot_halberdier(owner: int) -> UnitInfo:
	var unit := card(owner, "marmot-halberdier", "Marmot Halberdier", 3, [Enum.region.INTERMEDIATE])
	unit.effects.append(Collection.movement(2))
	var sacrifice := Effect.CostPhrase.new(Selectors.Self.new(), Verbs.sacrifice(), SynergyRules.friends_within(2))
	var physical := SynergyRules.phrase(Verbs.change_counter(1),
		Selectors.PropertyOf.new(Selectors.Self.new(), UnitInfo.PHYSICAL_COUNTER), true)
	var effect := SynergyRules.command(physical, 1, true, sacrifice)
	effect.consequence = Effect.ConsequenceSequence.new([physical, SynergyRules.phrase(Verbs.change_counter(1),
		Selectors.PropertyOf.new(Selectors.Self.new(), UnitInfo.MAGICAL_COUNTER), true)])
	unit.effects.append(effect)
	return unit

## Paladin captures the friendly sacrifice before departure, including its own; after defeat it uses existing Revive eligibility without a per-turn restriction.
static func marmot_paladin(owner: int) -> UnitInfo:
	var unit := card(owner, "marmot-paladin", "Marmot Paladin", 4, [Enum.region.STARTING])
	unit.effects.append(shield(2, 1))
	var victims := QuerySelector.new()
	victims.relative_owner = Enum.YOU
	var defeated := QuerySelector.new()
	defeated.relative_owner = Enum.YOU
	defeated.state = Enum.t_state.DEFEATED
	unit.trigger_effects.append(SynergyRules.observe(&"sacrifice", QuerySelector.new(), victims,
		SynergyRules.phrase(Verbs.revive(), defeated)))
	return unit

## Sentinel suppresses the whole Deploy occurrence for adjacent units of either owner; ordinary placement costs and entry Stun still apply.
static func chinchilla_sentinel(owner: int) -> UnitInfo:
	var unit := card(owner, "chinchilla-sentinel", "Chinchilla Sentinel", 2, [Enum.region.STARTING, Enum.region.INTERMEDIATE])
	unit.effects.append(Collection.displacement(1, 3))
	unit.continuous_effects.append(ContinuousEffect.have(Selectors.UnitsOn.new(DistanceSelector.new(1)),
		[Contribution.suppress_deploy()], null, null, "Adjacent deployments trigger no abilities"))
	return unit

## Soldier's mandatory own-Deploy consequence Returns another deployed friend at any distance; absence of a friend leaves deployment intact.
static func chinchilla_soldier(owner: int) -> UnitInfo:
	var unit := card(owner, "chinchilla-soldier", "Chinchilla Soldier", 5, [Enum.region.INTERMEDIATE])
	unit.effects.append(Collection.movement(2))
	var event := Effect.EventPhrase.observe(&"deploy", Selectors.Self.new(), QuerySelector.new(TargetRef.Kind.HEX),
		TargetRef.Kind.UNIT, TargetRef.Kind.HEX)
	unit.trigger_effects.append(Effect.on_event(event, SynergyRules.phrase(Verbs.return_to_hand(), OtherFriends.new()),
		null, null, Effect.Policy.MANDATORY))
	return unit

## Knight's deployment drawback adds three Stun beyond ordinary entry; its Bash contribution is a separate live rule.
static func tamia_knight(owner: int) -> UnitInfo:
	var unit := card(owner, "tamia-knight", "Tamia Knight", 2, [Enum.region.FRONT])
	unit.effects.append(Collection.movement(2))
	unit.trigger_effects.append(SynergyRules.on_deploy(UnitInfo.STUN_COUNTER, 3))
	unit.state_effects.append(StateModifier.new(Condition.Bashing.new(), 4, 0, "While bashing"))
	return unit

## Warrior's [AS] sacrifice precedes one Instant Bow 3/2; costs are not refunded if later geometry or source defeat makes Bow fail.
static func tamia_warrior(owner: int) -> UnitInfo:
	var unit := card(owner, "tamia-warrior", "Tamia Warrior", 3, [Enum.region.STARTING, Enum.region.INTERMEDIATE])
	unit.effects.append(Collection.movement(2))
	var sacrifice := Effect.CostPhrase.new(Selectors.Self.new(), Verbs.sacrifice(), SynergyRules.friends_within(1, true))
	unit.effects.append(SynergyRules.command(SynergyRules.phrase(Verbs.bow(3, 2, true), Selectors.BowTargets.new(2)), 1, true, sacrifice))
	return unit

## Red Mage stores two Ember after each of its actual zero-loss contacts; a failed Fire threshold is contact, while a miss is not.
static func tamia_red_mage(owner: int) -> UnitInfo:
	var unit := card(owner, "tamia-red-mage", "Tamia Red Mage", 2, [Enum.region.INTERMEDIATE])
	unit.effects.append(Collection.fire_DR(1, 3))
	unit.trigger_effects.append(award_on(&"hit", UnitInfo.EMBER_COUNTER, 2, null, null, null,
		Condition.EventFact.new(&"wounded", false)))
	return unit

## Blue Mage rewards another friend's Stun against an already-stunned victim; its own Stun and raw bonus do not trigger it.
static func tamia_blue_mage(owner: int) -> UnitInfo:
	var unit := card(owner, "tamia-blue-mage", "Tamia Blue Mage", 2, [Enum.region.STARTING, Enum.region.INTERMEDIATE])
	unit.effects.append(Collection.stun_DR(1, 2))
	unit.trigger_effects.append(SynergyRules.observe(&"stun", SynergyRules.friendly_actors(), QuerySelector.new(),
		SynergyRules.phrase(SynergyRules.counter(UnitInfo.STUN_COUNTER, 1),
			Selectors.Reference.new(Selectors.Anchor.EVENT_TARGET), true), SynergyRules.AlreadyStunned.new()))
	return unit

## Archer's [S] Bow pays activity without consuming a player action; normal delayed Bow/victim identity rules still apply.
static func tamia_archer(owner: int) -> UnitInfo:
	var unit := card(owner, "tamia-archer", "Tamia Archer", 1, [Enum.region.INTERMEDIATE])
	unit.effects.append(SynergyRules.command(SynergyRules.phrase(Verbs.bow(1, 3, false, false, true), Selectors.BowTargets.new(3)), 1, false))
	return unit

## Crossbowman permanently grows Bow range after each outgoing Hit, including zero-damage contact.
static func tamia_crossbowman(owner: int) -> UnitInfo:
	var unit := card(owner, "tamia-crossbowman", "Tamia Crossbowman", 2, [Enum.region.INTERMEDIATE, Enum.region.FRONT])
	unit.effects.append(Collection.bow_DR(3, 1))
	unit.trigger_effects.append(SynergyRules.observe(&"hit", Selectors.Self.new(), QuerySelector.new(),
		SynergyRules.phrase(Verbs.upgrade_bow(0, 1), Selectors.Self.new(), true)))
	return unit

## Exact SELF exclusion keeps Soldier's Return from substituting its own identity even on shared Bash hexes.
class OtherFriends extends QuerySelector:
	## Restricts the native UNIT query to deployed friends while preserving normal selector ownership rules.
	func _init() -> void:
		relative_owner = Enum.YOU
		state = Enum.t_state.DEPLOYED
	## TargetResolver calls this both for the picker and commit; only SELF is removed, not other same-hex units.
	func resolve(ctx: RuleContext) -> Array[TargetRef]:
		return super.resolve(ctx).filter(func(ref: TargetRef) -> bool: return not ref.same(ctx.source))
