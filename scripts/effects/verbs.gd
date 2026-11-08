class_name Verbs
extends RefCounted

## Grants recipient modifiers through End; the paid Berserker command requests separate stacking grants through enemy End.
static func grant_modifiers(physical: int, magical: int, enemy_end: bool = false, stack: bool = false) -> Effect.Verb:
	return Effect.Verb.new(&"grant_modifiers", Action.grant_modifiers, Action.can_grant_modifiers,
		TargetRef.Kind.UNIT, TargetRef.Kind.UNIT, [physical, magical, enemy_end, stack])

## Sacrifice is an atomic UNIT cost; the author supplies explicit eligibility and the shared cost ledger prevents duplicate payment.
static func sacrifice() -> Effect.Verb:
	var result := Effect.Verb.new(&"sacrifice", SynergyActions.sacrifice, SynergyActions.can_sacrifice,
		TargetRef.Kind.UNIT, TargetRef.Kind.UNIT)
	result.atomic_cost = true
	return result

## Mara's stored Cannon family upgrade addresses a UNIT, keeping permanent counters separate from timed grants and live auras.
static func upgrade_cannon(damage: int, range: int) -> Effect.Verb:
	return Effect.Verb.new(&"upgrade_cannon", Action.upgrade_cannon, Action.can_upgrade_cannon,
		TargetRef.Kind.UNIT, TargetRef.Kind.UNIT, [damage, range])

## Porcupine's first UNIT choice anchors its subsequent counter-kind/amount choices; atomic commit performs no mutation for this step.
static func choose_counter_unit() -> Effect.Verb:
	var result := Effect.Verb.new(&"choose_counter_unit", WildActions.choose_counter_unit, WildActions.can_choose_counter_unit,
		TargetRef.Kind.UNIT, TargetRef.Kind.UNIT)
	result.atomic_cost = true
	return result

## Chinchilla's death consequence selects one friend to Return, then effect-deploys SELF at that card's captured former hex.
static func return_and_deploy() -> Effect.Verb:
	return Effect.Verb.new(&"return_and_deploy", WildActions.return_and_deploy, WildActions.can_return_and_deploy,
		TargetRef.Kind.UNIT, TargetRef.Kind.UNIT)

## Porcupine's positive-X counter payment is selected after its PROPERTY; consequences read RuleNumber.paid_amount instead of live balances.
static func decrement_choice() -> Effect.Verb:
	var result := Effect.Verb.new(&"decrement", Action.decrement, Action.can_decrement,
		TargetRef.Kind.UNIT, TargetRef.Kind.PROPERTY, [RuleNumber.choice()])
	result.atomic_cost = true
	return result

## Woodland AC definitions combine this atomic health payment with ordinary activity in a CostBundle.
static func pay_life(actual: int, maximum: int = 0) -> Effect.Verb:
	var result := Effect.Verb.new(&"pay_life", WoodlandActions.pay_life, WoodlandActions.can_pay_life,
		TargetRef.Kind.UNIT, TargetRef.Kind.UNIT, [actual, maximum])
	result.atomic_cost = true
	return result

## Wild Mouse pays a captured opponent's next-Start action bonus instead of self-Stun for its explicit C action.
static func pay_next_turn_action(amount: int = 1) -> Effect.Verb:
	var result := next_turn_actions(amount)
	result.atomic_cost = true
	return result

## Upgrade's first UNIT choice stores its result for the subsequent ability PROPERTY projection.
static func choose_upgrade_unit() -> Effect.Verb:
	return Effect.Verb.new(&"choose_upgrade_unit", WoodlandActions.choose_upgrade_unit, WoodlandActions.can_choose_upgrade_unit,
		TargetRef.Kind.UNIT, TargetRef.Kind.UNIT)

## Permanent upgrade deltas address one chosen effect property, rather than all actions in the same family.
static func upgrade_ability(damage: int, range: int) -> Effect.Verb:
	return Effect.Verb.new(&"upgrade_ability", WoodlandActions.upgrade_ability, WoodlandActions.can_upgrade_ability,
		TargetRef.Kind.UNIT, TargetRef.Kind.PROPERTY, [damage, range])

## Wild Mole Rat's Flee grants a free use of its own movement; normal movement legality determines destinations.
static func flee() -> Effect.Verb:
	return Effect.Verb.new(&"flee", WoodlandActions.flee, WoodlandActions.can_flee, TargetRef.Kind.UNIT, TargetRef.Kind.HEX)

## Chooses a UNIT in hand and marks it defeated; target selectors specify friendly, enemy or explicit ownership as usual.
## PhraseExecution owns CHOOSE_ONE selection, including off-board hand choices; no deployment/death action is implied.
static func disable() -> Effect.Verb:
	return Effect.Verb.new(&"disable", Action.disable, Action.can_disable, TargetRef.Kind.UNIT, TargetRef.Kind.UNIT)

## Object-authored phrases return one deployed UNIT to its owner's hand; selectors specify ownership and range.
## PhraseExecution revalidates the chosen identity before Action publishes the existing return_to_hand synergy event.
static func return_to_hand() -> Effect.Verb:
	return Effect.Verb.new(&"return_to_hand", Action.return_to_hand, Action.can_return_to_hand, TargetRef.Kind.UNIT, TargetRef.Kind.UNIT)

## Rat Dark Mage resets one UNIT in place; the action restores its captured printed baseline without changing its zone or owner.
static func reset_unit() -> Effect.Verb:
	return Effect.Verb.new(&"reset", Action.reset_unit, Action.can_reset_unit, TargetRef.Kind.UNIT, TargetRef.Kind.UNIT)

## Rat Thief chooses one effect PROPERTY on its wounded event target; Copy preserves the target's own definition.
static func copy_effect() -> Effect.Verb:
	return Effect.Verb.new(&"copy_effect", Action.copy_effect, Action.can_copy_effect, TargetRef.Kind.UNIT, TargetRef.Kind.PROPERTY)

## Swordsman grants a one-shot player resource consumed at that owner's next Start rather than increasing the permanent allowance.
static func next_turn_actions(amount: int) -> Effect.Verb:
	return Effect.Verb.new(&"next_turn_actions", Action.next_turn_actions, Action.can_next_turn_actions,
		TargetRef.Kind.UNIT, TargetRef.Kind.PLAYER, [amount])

## Defines a unit-authored grant to a player's remaining deployment resource; Mouse Necromancer uses this on death.
static func grant_deployments(amount: int) -> Effect.Verb:
	return Effect.Verb.new(&"grant_deployments", Action.grant_deployments, Action.can_grant_deployments,
		TargetRef.Kind.UNIT, TargetRef.Kind.PLAYER, [amount])

static func deactivate() -> Effect.Verb:
	var result := Effect.Verb.new(&"deactivate", Action.deactivate, Action.can_deactivate, TargetRef.Kind.UNIT, TargetRef.Kind.UNIT)
	result.atomic_cost = true
	return result

## Defines atomic activity payment: SELF gains the positive authored Stun amount (one normally, two for Flying Squirrel).
## Collection.action_cost() places this verb in the default action cost phrase.
## Defines activity payment and whether Action-free exempts its separate token requirement.
## Collection.action_cost() includes this verb for ordinary non-Tireless actions.
static func pay_activity(action_free: bool = false, amount: int = 1) -> Effect.Verb:
	var result := Effect.Verb.new(&"self_stun", Action.pay_activity, Action.can_pay_activity,
		TargetRef.Kind.UNIT, TargetRef.Kind.UNIT, [action_free, amount])
	result.atomic_cost = true
	return result

static func damage(amount: int) -> Effect.Verb:
	return Effect.Verb.new(&"damage", Action.damage, Action.can_damage, TargetRef.Kind.UNIT, TargetRef.Kind.HEX, [amount])

## Defines permanent Bow damage/range counter changes for a deployed unit.
## Collection.reed_archer_sharpen_trigger() uses it after that unit wounds a target.
static func upgrade_bow(damage: int, range: int) -> Effect.Verb:
	return Effect.Verb.new(&"upgrade_bow", Action.upgrade_bow, Action.can_upgrade_bow,
		TargetRef.Kind.UNIT, TargetRef.Kind.UNIT, [damage, range])

## Defines a temporary named action-value grant with a lifetime captured at resolution.
## Collection.grant_action_values() builds the phrase; UnitInfo derives it until Match cleanup.
static func grant_action_values(family: StringName, values: Array[int]) -> Effect.Verb:
	return Effect.Verb.new(&"grant_action_values", Action.grant_action_values,
		Action.can_grant_action_values, TargetRef.Kind.UNIT, TargetRef.Kind.UNIT,
		[family, values.duplicate()])

## Defines a permanent current/max-life adjustment for SELF.
## Catalogue trigger factories use it for the JS up-life(actual,max) property.
static func up_life(actual_delta: int, max_delta: int) -> Effect.Verb:
	return Effect.Verb.new(&"up_life", Action.up_life, Action.can_up_life,
		TargetRef.Kind.UNIT, TargetRef.Kind.UNIT, [actual_delta, max_delta])

## Defines Fire's damage, timing, Pierce, and optional action-token sticker.
## Collection.fire_DR() supplies these values; PhraseExecution passes them to CombatResolver.
static func fire(amount: int, instant: bool = false, pierce: bool = false, action_free: bool = false) -> Effect.Verb:
	return Effect.Verb.new(&"fire", Action.fire, Action.can_fire, TargetRef.Kind.UNIT, TargetRef.Kind.HEX,
		[amount, instant, pierce, action_free])

## Defines physical Bow damage, range, and the supported Instant/Pierce stickers.
## Card effects use a HEX selector; Action.bow() captures the attack in CombatResolver.
static func bow(amount: int, range: int, instant: bool = false, pierce: bool = false,
		action_free: bool = false) -> Effect.Verb:
	return Effect.Verb.new(&"bow", Action.bow, Action.can_bow, TargetRef.Kind.UNIT, TargetRef.Kind.HEX,
		[amount, range, instant, pierce, action_free])

## Defines a straight-line magical Cannon action that can affect either player.
## A radius selector proposes endpoints; CombatResolver validates alignment and captures the line.
static func cannon(amount: int, range: int, instant: bool = false, pierce: bool = false,
		action_free: bool = false) -> Effect.Verb:
	return Effect.Verb.new(&"cannon", Action.cannon, Action.can_cannon, TargetRef.Kind.UNIT, TargetRef.Kind.HEX,
		[amount, range, instant, pierce, action_free])

## Defines an inert Bomb placement/merge at a chosen HEX.
## Collection.bomb_DR() uses it; the bomb remains until lit or defused.
static func bomb_throw(amount: int, range: int, pierce: bool = false,
		action_free: bool = false) -> Effect.Verb:
	return Effect.Verb.new(&"bomb_throw", Action.bomb_throw, Action.can_bomb_throw,
		TargetRef.Kind.UNIT, TargetRef.Kind.HEX, [amount, range, pierce, action_free])

## Defines removal of an inert Bomb within the supplied radius.
## Object-authored defuse effects call this verb; it does not affect lit blast records.
static func defuse_bomb(range: int = 0, action_free: bool = false) -> Effect.Verb:
	return Effect.Verb.new(&"bomb_defuse", Action.defuse_bomb, Action.can_defuse_bomb,
		TargetRef.Kind.UNIT, TargetRef.Kind.HEX, [range, action_free])

## Defines a straight-line physical leap; D is damage, R is maximum destination distance.
## Collection.gore_DR() supplies these values and the shared activity cost.
static func gore(amount: int, range: int, action_free: bool = false) -> Effect.Verb:
	return Effect.Verb.new(&"gore", Action.gore, Action.can_gore, TargetRef.Kind.UNIT,
		TargetRef.Kind.HEX, [amount, range, action_free])

## Defines immediate Walk/Move or Fly to a chosen HEX within the supplied range.
## The boolean selects path-blocking Move versus occupancy-ignoring Fly.
static func movement(range: int, flying: bool = false, action_free: bool = false) -> Effect.Verb:
	if flying:
		return Effect.Verb.new(&"fly", Action.fly, Action.can_fly, TargetRef.Kind.UNIT,
			TargetRef.Kind.HEX, [range, action_free])
	return Effect.Verb.new(&"move", Action.move, Action.can_move, TargetRef.Kind.UNIT,
		TargetRef.Kind.HEX, [range, action_free])

## Defines an immediate allied healing action with amount and range fixed in its definition.
## Collection.mend_DR() binds the shared activity cost and ally selector.
static func mend(amount: int, range: int, action_free: bool = false) -> Effect.Verb:
	return Effect.Verb.new(&"mend", Action.mend, Action.can_mend, TargetRef.Kind.UNIT,
		TargetRef.Kind.UNIT, [amount, range, action_free])

## Defines additive hostile Stun with its amount, range, and optional action-token exemption.
## Collection.stun_DR() composes the target choice with the shared activity cost.
static func stun(amount: int, range: int, action_free: bool = false) -> Effect.Verb:
	return Effect.Verb.new(&"stun", Action.stun, Action.can_stun, TargetRef.Kind.UNIT,
		TargetRef.Kind.UNIT, [amount, range, action_free])

## Defines the triggered return of a defeated allied non-hero to undeployed reserve.
## The death source cannot target itself; Action.can_revive enforces that reference rule.
static func revive() -> Effect.Verb:
	return Effect.Verb.new(&"revive", Action.revive, Action.can_revive,
		TargetRef.Kind.UNIT, TargetRef.Kind.UNIT)

## Displaces a selected unit along the line from SELF through that unit.
## Distance is the displacement length; range is SELF-to-target reach.
static func push(distance: int, range: int, action_free: bool = false) -> Effect.Verb:
	return Effect.Verb.new(&"push", Action.displace, Action.can_displace, TargetRef.Kind.UNIT,
		TargetRef.Kind.UNIT, [distance, range, false, action_free])

## Pulls a selected unit along the same axial line toward SELF.
## The landing may trigger Bash if occupied by an enemy.
static func pull(distance: int, range: int, action_free: bool = false) -> Effect.Verb:
	return Effect.Verb.new(&"pull", Action.displace, Action.can_displace, TargetRef.Kind.UNIT,
		TargetRef.Kind.UNIT, [distance, range, true, action_free])

## Explicitly targets an inert Bomb tile for displacement instead of selecting a unit.
## Bombs landing together merge damage and Pierce.
static func push_bomb(distance: int, range: int, action_free: bool = false) -> Effect.Verb:
	return Effect.Verb.new(&"push_bomb", Action.displace_bomb, Action.can_displace_bomb,
		TargetRef.Kind.UNIT, TargetRef.Kind.HEX, [distance, range, false, action_free])

## Pulls an inert Bomb toward SELF; an existing Bomb at the landing tile absorbs it.
## This distinct verb keeps unit and Bomb target domains explicit.
static func pull_bomb(distance: int, range: int, action_free: bool = false) -> Effect.Verb:
	return Effect.Verb.new(&"pull_bomb", Action.displace_bomb, Action.can_displace_bomb,
		TargetRef.Kind.UNIT, TargetRef.Kind.HEX, [distance, range, true, action_free])

## Standard Shield protects friends. The enemy-hero variant may also be an explicit atomic cost.
static func shield(amount: int, enemy_hero: bool = false) -> Effect.Verb:
	var result := Effect.Verb.new(&"shield", Action.shield, Action.can_shield, TargetRef.Kind.UNIT, TargetRef.Kind.UNIT, [amount, false, enemy_hero])
	result.atomic_cost = enemy_hero
	return result

static func mshield(amount: int) -> Effect.Verb:
	return Effect.Verb.new(&"mshield", Action.shield, Action.can_shield, TargetRef.Kind.UNIT, TargetRef.Kind.UNIT, [amount, true])

static func decrement(amount: int = 1) -> Effect.Verb:
	var result := Effect.Verb.new(&"decrement", Action.decrement, Action.can_decrement, TargetRef.Kind.UNIT, TargetRef.Kind.PROPERTY, [amount])
	result.atomic_cost = true
	return result

static func set_flag(value: bool) -> Effect.Verb:
	return Effect.Verb.new(&"set_flag", Action.set_flag, Action.can_set_flag, TargetRef.Kind.UNIT, TargetRef.Kind.PROPERTY, [value])

static func change_counter(delta: int) -> Effect.Verb:
	return Effect.Verb.new(&"change_counter", Action.change_counter, Action.can_change_counter, TargetRef.Kind.UNIT, TargetRef.Kind.PROPERTY, [delta])
