class_name Collection
extends RefCounted

## Default activity payment: SELF becomes inactive and receives one Stun.
## Action-free is passed through so this payment still applies without a player token.
static func action_cost(action_free: bool = false) -> Effect.CostPhrase:
	return Effect.CostPhrase.new(Selectors.Self.new(), Verbs.pay_activity(action_free), Selectors.Self.new())

## Builds Ironhide Boar Pup's automatic Hit trigger: gain persistent physical and magical counters.
## RulesRunner captures each Hit, matches the actor to SELF, and executes these ALL property steps.
static func ironhide_boar_pup_trigger() -> Effect:
	var hit := Effect.EventPhrase.observe(&"hit", Selectors.Self.new(),
		QuerySelector.new(TargetRef.Kind.UNIT), TargetRef.Kind.UNIT, TargetRef.Kind.UNIT)
	var physical := Effect.ConsequencePhrase.new(Selectors.Self.new(), Verbs.change_counter(1),
		Selectors.PropertyOf.new(Selectors.Self.new(), UnitInfo.PHYSICAL_COUNTER), Effect.Phrase.TargetMode.ALL)
	var magical := Effect.ConsequencePhrase.new(Selectors.Self.new(), Verbs.change_counter(1),
		Selectors.PropertyOf.new(Selectors.Self.new(), UnitInfo.MAGICAL_COUNTER), Effect.Phrase.TargetMode.ALL)
	return Effect.on_event(hit, Effect.ConsequenceSequence.new([physical, magical]))

## Builds Prism Moth's triggered +1/+1 gain when an opposing Bash engages it.
## The event pattern anchors SELF on the Bash target and requires the declaration stage.
static func prism_moth_trigger() -> Effect:
	var engagement := Effect.EventPhrase.observe(&"bash", QuerySelector.new(TargetRef.Kind.UNIT),
		Selectors.Self.new(), TargetRef.Kind.UNIT, TargetRef.Kind.UNIT, &"target")
	var physical := Effect.ConsequencePhrase.new(Selectors.Self.new(), Verbs.change_counter(1),
		Selectors.PropertyOf.new(Selectors.Self.new(), UnitInfo.PHYSICAL_COUNTER), Effect.Phrase.TargetMode.ALL)
	var magical := Effect.ConsequencePhrase.new(Selectors.Self.new(), Verbs.change_counter(1),
		Selectors.PropertyOf.new(Selectors.Self.new(), UnitInfo.MAGICAL_COUNTER), Effect.Phrase.TargetMode.ALL)
	return Effect.on_event(engagement, Effect.ConsequenceSequence.new([physical, magical]))

## Builds a Fire effect and applies the supported per-action stickers.
## CardCatalogue and selection tests use this factory; Action.free omits the local token,
## Tireless omits the generated self-Stun cost, and Instant/Pierce configure Fire.
static func fire_DR(damage: int, radius: int, instant: bool = false, pierce: bool = false,
		tireless: bool = false, action_free: bool = false) -> Effect:
	var consequence := Effect.ConsequencePhrase.new(Selectors.Self.new(),
		Verbs.fire(damage, instant, pierce, action_free),
		DistanceSelector.within(radius, Selectors.Anchor.SUBJECT))
	return with_action_policy(consequence, tireless, action_free, null, instant, pierce)

## Builds physical Bow with the shared default Stun cost and a target selector that reads permanent Bow range upgrades.
## CardCatalogue may compose it like fire_DR(); CombatResolver owns damage and delayed resolution.
static func bow_DR(damage: int, radius: int, instant: bool = false, pierce: bool = false,
		tireless: bool = false, action_free: bool = false) -> Effect:
	var consequence := Effect.ConsequencePhrase.new(Selectors.Self.new(),
		Verbs.bow(damage, radius, instant, pierce, action_free), Selectors.BowTargets.new(radius))
	return with_action_policy(consequence, tireless, action_free, null, instant, pierce)

## Builds Reed Archer's Wound-triggered permanent +1 Bow damage/range upgrade.
## CardCatalogue.reed_archer() installs this trigger; RulesRunner matches its source on Wound.
## ALL applies to SELF automatically, releasing combat continuation without a redundant target click.
static func reed_archer_sharpen_trigger() -> Effect:
	var any_unit := QuerySelector.new(TargetRef.Kind.UNIT)
	var wound := Effect.EventPhrase.observe(&"wound", Selectors.Self.new(), any_unit,
		TargetRef.Kind.UNIT, TargetRef.Kind.UNIT)
	var upgrade := Effect.ConsequencePhrase.new(Selectors.Self.new(), Verbs.upgrade_bow(1, 1),
		Selectors.Self.new(), Effect.Phrase.TargetMode.ALL)
	return Effect.on_event(wound, upgrade)

## Builds Squirrel King's +1 current-life restoration when Fire is declared, before attack resolution.
## CardCatalogue.squirrel_king() installs it; RulesRunner captures the target-stage event
## and automatically applies ALL on SELF as a command followup. Mend clamps at max life.
static func squirrel_king_kindle_trigger() -> Effect:
	var any_hex := QuerySelector.new(TargetRef.Kind.HEX)
	var fire := Effect.EventPhrase.observe(&"fire", Selectors.Self.new(), any_hex,
		TargetRef.Kind.UNIT, TargetRef.Kind.HEX, &"target")
	var heal := Effect.ConsequencePhrase.new(Selectors.Self.new(), Verbs.mend(1, 0),
		Selectors.Self.new(), Effect.Phrase.TargetMode.ALL)
	return Effect.on_event(fire, heal)

## Builds Thunder Toad's hostile-Stun trigger: lose one current life and gain one max life.
## CardCatalogue.thunder_toad() installs it; self-Stun activity costs do not qualify as hostile targets.
## ALL applies the fixed SELF adjustment without blocking the Stun command's followups on a target click.
static func thunder_toad_charge_trigger() -> Effect:
	var enemy := QuerySelector.new(TargetRef.Kind.UNIT)
	enemy.relative_owner = Enum.OPP
	var stun := Effect.EventPhrase.observe(&"stun", Selectors.Self.new(), enemy,
		TargetRef.Kind.UNIT, TargetRef.Kind.UNIT)
	var charge := Effect.ConsequencePhrase.new(Selectors.Self.new(), Verbs.up_life(-1, 1),
		Selectors.Self.new(), Effect.Phrase.TargetMode.ALL)
	return Effect.on_event(stun, charge)

## Builds straight-line magical Cannon with the shared activity and token sticker rules.
## Target selection uses a radius; the resolver offers only aligned endpoints.
static func cannon_DR(damage: int, radius: int, instant: bool = false, pierce: bool = false,
		tireless: bool = false, action_free: bool = false) -> Effect:
	var consequence := Effect.ConsequencePhrase.new(Selectors.Self.new(),
		Verbs.cannon(damage, radius, instant, pierce, action_free),
		DistanceSelector.within(radius, Selectors.Anchor.SUBJECT))
	return with_action_policy(consequence, tireless, action_free, null, instant, pierce)

## Builds an inert Bomb throw with ordinary activity payment and a selectable radius.
## BombResolver later handles merges, lighting, area damage, and chains.
static func bomb_DR(damage: int, radius: int, pierce: bool = false, tireless: bool = false,
		action_free: bool = false) -> Effect:
	var consequence := Effect.ConsequencePhrase.new(Selectors.Self.new(),
		Verbs.bomb_throw(damage, radius, pierce, action_free),
		DistanceSelector.within(radius, Selectors.Anchor.SUBJECT))
	return with_action_policy(consequence, tireless, action_free, null, false, pierce)

## Builds an inert Bomb defuse effect; no blast is created by removal.
## Object-authored card definitions supply its radius and optional activity/token stickers.
static func defuse_bomb(radius: int = 0, tireless: bool = false,
		action_free: bool = false) -> Effect:
	var consequence := Effect.ConsequencePhrase.new(Selectors.Self.new(),
		Verbs.defuse_bomb(radius, action_free),
		DistanceSelector.within(radius, Selectors.Anchor.SUBJECT))
	return with_action_policy(consequence, tireless, action_free)

## Builds the physical Gore leap with separate damage and travel range.
## The player chooses an aligned destination; pierced path is not blocked by units.
static func gore_DR(damage: int, radius: int, tireless: bool = false,
		action_free: bool = false) -> Effect:
	var consequence := Effect.ConsequencePhrase.new(Selectors.Self.new(),
		Verbs.gore(damage, radius, action_free),
		DistanceSelector.within(radius, Selectors.Anchor.SUBJECT))
	return with_action_policy(consequence, tireless, action_free)

## Builds a costed Move or Fly; Move needs a free adjacent path and Fly ignores intermediates.
## The chosen destination is resolved immediately and may create a delayed Bash on an enemy.
static func movement(range: int, flying: bool = false, tireless: bool = false,
		action_free: bool = false) -> Effect:
	var consequence := Effect.ConsequencePhrase.new(Selectors.Self.new(),
		Verbs.movement(range, flying, action_free), DistanceSelector.within(range, Selectors.Anchor.SUBJECT))
	return with_action_policy(consequence, tireless, action_free)

## CardCatalogue.bramble_empress() builds Push/Pull with fixed displacement distance and independent target radius.
## Unit-domain spatial targeting preserves CHOOSE_ONE; CombatResolver checks alignment, immovability and landing legality.
## Either owner's units may be chosen; ordinary activity/token policy applies unless explicitly stickered.
static func displacement(distance: int, radius: int, pull: bool = false,
		tireless: bool = false, action_free: bool = false) -> Effect:
	var recipients := Selectors.UnitsOn.new(DistanceSelector.within(radius, Selectors.Anchor.SUBJECT))
	var verb := Verbs.pull(distance, radius, action_free) if pull else Verbs.push(distance, radius, action_free)
	var consequence := Effect.ConsequencePhrase.new(Selectors.Self.new(), verb, recipients)
	return with_action_policy(consequence, tireless, action_free)

## Builds a costed Mend action targeting injured allies within range.
## Healing applies immediately, clamps to starting life, and refreshes regional control.
static func mend_DR(amount: int, radius: int, tireless: bool = false,
		action_free: bool = false) -> Effect:
	var allies := QuerySelector.new(TargetRef.Kind.UNIT)
	allies.relative_owner = Enum.YOU
	var recipients := Selectors.UnitsOn.new(
		DistanceSelector.within(radius, Selectors.Anchor.SUBJECT)).where(allies)
	var consequence := Effect.ConsequencePhrase.new(Selectors.Self.new(),
		Verbs.mend(amount, radius, action_free), recipients)
	return with_action_policy(consequence, tireless, action_free)

## Builds a self-targeted physical or magical Shield action with shared activity/token payment.
## CardCatalogue.walnut_crab() uses physical Shield 2 beside the Crab's Cannon action.
static func shield_DR(amount: int, magical: bool = false, tireless: bool = false,
		action_free: bool = false) -> Effect:
	var verb := Verbs.mshield(amount) if magical else Verbs.shield(amount)
	var consequence := Effect.ConsequencePhrase.new(Selectors.Self.new(), verb, Selectors.Self.new())
	return with_action_policy(consequence, tireless, action_free)

## Builds a costed hostile Stun action using the shared activity and token policy.
## Stun adds counters and deactivates an enemy; temporary protection remains untouched for now.
static func stun_DR(amount: int, radius: int, tireless: bool = false,
		action_free: bool = false) -> Effect:
	var enemies := QuerySelector.new(TargetRef.Kind.UNIT)
	enemies.relative_owner = Enum.OPP
	var recipients := Selectors.UnitsOn.new(
		DistanceSelector.within(radius, Selectors.Anchor.SUBJECT)).where(enemies)
	var consequence := Effect.ConsequencePhrase.new(Selectors.Self.new(),
		Verbs.stun(amount, radius, action_free), recipients)
	return with_action_policy(consequence, tireless, action_free)

## Mouse Necromancer's death trigger grants its owner two remaining deployments instead of reviving a unit.
## RulesRunner captures the death source; ALL resolves the single friendly player automatically after trigger acknowledgement.
static func pine_processionary_trigger() -> Effect:
	var event_target := QuerySelector.new(TargetRef.Kind.HEX)
	var death := Effect.EventPhrase.observe(&"die", Selectors.Self.new(), event_target,
		TargetRef.Kind.UNIT, TargetRef.Kind.HEX)
	var owner := QuerySelector.new(TargetRef.Kind.PLAYER)
	owner.relative_owner = Enum.YOU
	var grant := Effect.ConsequencePhrase.new(Selectors.Self.new(), Verbs.grant_deployments(2), owner,
		Effect.Phrase.TargetMode.ALL)
	return Effect.on_event(death, grant)

## Applies typed action stickers and the shared default activity policy; an explicit cost replaces the default.
## Combat factories call this so P/F/T/A metadata and payment semantics stay aligned.
static func with_action_policy(consequence: Effect.ConsequencePhrase, tireless: bool = false,
		action_free: bool = false, explicit_cost: RefCounted = null,
		instant: bool = false, pierce: bool = false) -> Effect:
	var sticker_options := ActionStickers.new()
	sticker_options.instant = instant
	sticker_options.pierce = pierce
	sticker_options.tireless = tireless
	sticker_options.action_free = action_free
	for sticker in ActionSticker.from_options(sticker_options): consequence.add_sticker(sticker)
	var payment: RefCounted = explicit_cost
	if payment == null and not tireless: payment = action_cost(action_free)
	return Effect.new(payment, null, consequence)

## Authors a ranged attack with named sticker fields, retaining the existing verb contracts.
## Catalogue authors may use this instead of positional booleans; explicit costs replace defaults.
static func ranged(action: StringName, damage: int, radius: int, stickers: ActionStickers = null,
		explicit_cost: RefCounted = null) -> Effect:
	var options := stickers if stickers != null else ActionStickers.new()
	var verb: Effect.Verb
	match action:
		&"fire": verb = Verbs.fire(damage, options.instant, options.pierce, options.action_free)
		&"bow": verb = Verbs.bow(damage, radius, options.instant, options.pierce, options.action_free)
		&"cannon": verb = Verbs.cannon(damage, radius, options.instant, options.pierce, options.action_free)
		_: return null
	var consequence := Effect.ConsequencePhrase.new(Selectors.Self.new(), verb, DistanceSelector.within(radius, Selectors.Anchor.SUBJECT))
	return with_action_policy(consequence, options.tireless, options.action_free, explicit_cost,
		options.instant, options.pierce)

## Builds a normal action that gives each chosen unit a temporary named action-value grant.
## The concrete recipients retain it through the active player's End triggers; Match cleanup expires it.
static func grant_action_values(family: StringName, values: Array[int], recipients: Selector,
		tireless: bool = false, action_free: bool = false,
		explicit_cost: RefCounted = null) -> Effect:
	if family.is_empty() or values.is_empty() or recipients == null: return null
	var consequence := Effect.ConsequencePhrase.new(Selectors.Self.new(),
		Verbs.grant_action_values(family, values), recipients, Effect.Phrase.TargetMode.CHOOSE_ONE)
	return with_action_policy(consequence, tireless, action_free, explicit_cost)

## Authors Tortoise Emperor's optional activity-costed End Shield for all adjacent allies.
## The runner asks once before payment and retains End while the cost target is selected.
static func tortoise_end_shield() -> Effect:
	var player := QuerySelector.new(TargetRef.Kind.PLAYER)
	player.relative_owner = Enum.YOU
	var event := Effect.EventPhrase.observe(&"end", player, player, TargetRef.Kind.PLAYER, TargetRef.Kind.PLAYER)
	var allies := QuerySelector.new()
	allies.relative_owner = Enum.YOU
	var adjacent := Selectors.UnitsOn.new(DistanceSelector.new(1)).where(allies)
	var consequence := Effect.ConsequencePhrase.new(Selectors.Self.new(), Verbs.shield(1), adjacent, Effect.Phrase.TargetMode.ALL)
	return Effect.on_event(event, consequence, null, action_cost(), Effect.Policy.OPTIONAL)
