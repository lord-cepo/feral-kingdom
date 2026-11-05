## Object-authored rules for the twenty adventurer cards; mutable selections belong to executions.
class_name AdventurerRules
extends RefCounted

## Cleric enumerates only existing numeric counters, including zero; it never creates a new counter family.
class ExistingCounters extends Selectors.ProjectionSelector:
	## The authored host selector provides adjacency/ownership while this projection provides PROPERTY identities.
	func _init(hosts: Selector) -> void:
		super(hosts, TargetRef.Kind.UNIT, TargetRef.Kind.PROPERTY)
	## TargetResolver uses stable keys and deduplicates these existing properties before CHOOSE_ONE.
	func resolve(ctx: RuleContext) -> Array[TargetRef]:
		var result: Array[TargetRef] = []
		for host in input.resolve(ctx):
			for prop in Match.get_unit(host.id).props:
				if prop.increment == Enum.p_increment.COUNTER: result.append(TargetRef.property(host, prop.name))
		return TargetResolver.unique(result)

## Summoner pays Return inside the same atomic bundle as activity; the phrase retains the cost target's historical hex.
static func summoner_exchange() -> Effect:
	var payment := Verbs.return_to_hand()
	payment.atomic_cost = true
	var deploy := Effect.Verb.new(&"deploy_returned_hex", deploy_returned_hex, can_deploy_returned_hex,
		TargetRef.Kind.UNIT, TargetRef.Kind.UNIT, [RuleBinding.new(&"cost_1", RuleBinding.Field.HEX_ID)])
	return SynergyRules.command(SynergyRules.phrase(deploy, friendly_zone(Enum.t_state.UNDEPLOYED)), 1, true,
		Effect.CostPhrase.new(Selectors.Self.new(), payment, WoodlandRules.friends()))

## The retained destination is independent of the returned identity; that same card is eligible alongside other friendly hand cards.
static func can_deploy_returned_hex(subject: TargetRef, target: TargetRef, hex_id: int) -> bool:
	if not Action.can_disable(subject, target) or Match.owner_of(subject) != Match.owner_of(target) or Match.get_hex(hex_id) == null: return false
	var unit := Match.get_unit(target.id)
	if unit.actual_life <= 0 or unit.max_life <= 0: return false
	if unit.type == Enum.type.HERO and Match.players[unit.player].selected_hero_id not in [-1, target.id]: return false
	return not Match.occupants(hex_id).any(func(ref: TargetRef) -> bool: return Match.owner_of(ref) == unit.player)

## Effect-deployment preserves health/counters, pays no additional action/deployment, and bypasses control/printed-region limits.
## The chosen hand card enters inactive with one Stun, emits Deploy, and starts Bash against an opposing occupant.
static func deploy_returned_hex(subject: TargetRef, target: TargetRef, hex_id: int) -> bool:
	if not can_deploy_returned_hex(subject, target, hex_id): return false
	Match.rules_runner.begin_boundary()
	var unit := Match.get_unit(target.id)
	var occupants := Match.occupants(hex_id)
	unit.t_state = Enum.t_state.DEPLOYED
	unit.ihx = hex_id
	unit.active = false
	unit._change_action_counter(UnitInfo.STUN_COUNTER, 1)
	Match.players[unit.player].has_deployed = true
	if unit.type == Enum.type.HERO: Match.players[unit.player].selected_hero_id = target.id
	Match.refresh_control()
	Match.action_event.emit(EffectEvent.new(&"deploy", target, TargetRef.hex(hex_id), {"effect_deployment": true}))
	if not occupants.is_empty(): CombatResolver._create_bash(target.id, occupants[0].id, hex_id)
	Match.state_changed.emit()
	Match.rules_runner.end_boundary()
	return true

## Barbarian's two modifier components use the same live friendly-adjacency count.
class AdjacentFriends extends StateModifier:
	## Catalogue supplies a hover description; the modifier never awards stored counters.
	func _init() -> void:
		super(null, 0, 0, "+X/+X, X adjacent friends")
	## UnitInfo evaluates on each read, excluding SELF and including each distinct adjacent friendly occupant once.
	func evaluate(ctx: RuleContext) -> Vector2i:
		var count := SynergyRules.friends_within(1, true).resolve(ctx).size()
		return Vector2i(count, count)

## Druid's signed modifier follows current maximum life, independently of wounds and regional strength.
class MaximumLife extends StateModifier:
	## Catalogue binds only the printed description; execution state is never stored here.
	func _init() -> void:
		super(null, 0, 0, "+X/+X, X maximum life minus 2")
	## UnitInfo supplies SELF; acquired maximum-life changes take effect immediately.
	func evaluate(ctx: RuleContext) -> Vector2i:
		var unit := Match.get_unit(ctx.source.id) if ctx != null and ctx.source != null else null
		var value := unit.max_life - 2 if unit != null else 0
		return Vector2i(value, value)

## Scout reads geography rather than regional control; the owning player's action ledger prevents refills on reentry.
class EnemyStarting extends Condition:
	## ContinuousEffect supplies SELF during live allowance queries, without writing action resources.
	func test(ctx: RuleContext) -> bool:
		if ctx == null or ctx.source == null or not ctx.source.has_hex(): return false
		var tile := Match.get_hex(ctx.source.hex_id())
		return tile.region == Enum.region.STARTING and int(tile.side) == 3 - Match.owner_of(ctx.source)

## Jester captures a newly enemy-owned region only when that region currently contains SELF.
class OwnRegion extends Condition:
	## Event matching already restricts the gaining PLAYER; this guard excludes unrelated regions and off-board sources.
	func test(ctx: RuleContext) -> bool:
		return ctx != null and ctx.source != null and ctx.source.has_hex() and ctx.triggering_event != null \
			and ctx.triggering_event.target != null and ctx.triggering_event.target.kind == TargetRef.Kind.HEX \
			and ControlResolver.same_region(Match.get_hex(ctx.source.hex_id()), Match.get_hex(ctx.triggering_event.target.id))

## Berserker retains ordinary movement legality but offers only destinations occupied by an enemy.
class EnemyDestinations extends Selector:
	## Movement verbs require HEX destinations; occupant projection is explicit inside this specialized selector.
	func output_kind(_ctx: RuleContext = null) -> int:
		return TargetRef.Kind.HEX
	## Every offered tile is within two and contains a current enemy, including a shared Bash tile.
	func resolve(ctx: RuleContext) -> Array[TargetRef]:
		var result: Array[TargetRef] = []
		for hex_ref in DistanceSelector.within(2).resolve(ctx):
			for unit in Match.occupants(hex_ref.id):
				if Match.owner_of(unit) != Match.owner_of(ctx.source):
					result.append(hex_ref)
					break
		return result

## Creates the owner/zone query used by off-board payments and unrestricted friendly effects.
static func friendly_zone(state: int) -> QuerySelector:
	var result := QuerySelector.new()
	result.relative_owner = Enum.YOU
	result.state = state
	return result

## Named enemy query keeps Rogue/Hunter targeting restrictions explicit at the definition boundary.
static func enemies() -> QuerySelector:
	var result := QuerySelector.new()
	result.relative_owner = Enum.OPP
	result.state = Enum.t_state.DEPLOYED
	return result

## Existing positive counters are selected as properties; ownership and range remain on their host selector.
static func counter_cost(hosts: Selector) -> Effect.CostPhrase:
	return Effect.CostPhrase.new(Selectors.Self.new(), Verbs.decrement(1), Selectors.CountersOf.new(hosts))

## Rogue reads the selected paid PROPERTY key and awards exactly that kind to SELF, creating it when absent.
static func rogue_steal() -> Effect:
	var award := Effect.Verb.new(&"add_counter", SynergyActions.add_counter, SynergyActions.can_add_counter,
		TargetRef.Kind.UNIT, TargetRef.Kind.UNIT, [RuleBinding.new(&"cost_1", RuleBinding.Field.PROPERTY_KEY), 1])
	return SynergyRules.command(SynergyRules.phrase(award, Selectors.Self.new(), true), 1, true,
		counter_cost(Selectors.UnitsOn.new(DistanceSelector.new(1)).where(enemies())))

## Rogue's direct defeat is restricted to a currently deployed enemy; it does not invent Bow/Fire contact.
static func can_defeat_enemy(subject: TargetRef, target: TargetRef) -> bool:
	return Action.can_return_to_hand(subject, target) and Match.owner_of(subject) != Match.owner_of(target)

## A paid Rogue command defeats one exact enemy through the authoritative death path and its normal triggers.
static func defeat_enemy(subject: TargetRef, target: TargetRef) -> bool:
	if not can_defeat_enemy(subject, target): return false
	Match.defeat(target, Match.owner_of(subject))
	return true

## Disable is a supported atomic friend-hand cost; reserve the chosen departure before any consequence Revive.
static func disable_cost() -> Effect.CostPhrase:
	var verb := Verbs.disable()
	verb.atomic_cost = true
	return Effect.CostPhrase.new(Selectors.Self.new(), verb, friendly_zone(Enum.t_state.UNDEPLOYED))

## Witch upgrades her own Fire family using a permanent numeric counter, independently of Embers consumed on Fire.
static func can_upgrade_fire(subject: TargetRef, target: TargetRef) -> bool:
	return subject != null and target != null and subject.kind == TargetRef.Kind.UNIT and target.kind == TargetRef.Kind.UNIT \
		and Match.get_unit(subject.id) != null and Match.get_unit(target.id) != null

## The consequence awards one permanent Fire-damage counter; Reset removes it and snapshots preserve its PROPERTY.
static func upgrade_fire(subject: TargetRef, target: TargetRef) -> bool:
	if not can_upgrade_fire(subject, target): return false
	return SynergyActions.add_counter(subject, target, &"fire_damage", 1)

## Merchant's sticker grant requires a real deployed friendly recipient, with adjacency supplied by the card selector.
static func can_grant_next_fire(subject: TargetRef, target: TargetRef, sticker: StringName) -> bool:
	return sticker in [&"pierce", &"instant"] and Action.can_return_to_hand(subject, target) \
		and Match.owner_of(subject) == Match.owner_of(target)

## Adds a recipient-owned pending sticker; multiple grants combine on that recipient's next successful Fire declaration.
static func grant_next_fire(subject: TargetRef, target: TargetRef, sticker: StringName) -> bool:
	if not can_grant_next_fire(subject, target, sticker): return false
	var unit := Match.get_unit(target.id)
	if sticker not in unit.next_fire_stickers: unit.next_fire_stickers.append(sticker)
	Match.action_event.emit(EffectEvent.new(&"grant_next_fire", subject, target, {"sticker": sticker}))
	Match.state_changed.emit()
	return true

## Shaman's activation guard rejects payment before selection when two participants do not exist.
class TwoBashing extends Condition:
	## EffectExecution and RulesRunner availability call this before collecting resource costs.
	func test(_ctx: RuleContext) -> bool:
		return BashingUnits.new().resolve(null).size() >= 2

## Shaman choices enumerate every live participant, independently of owner or encounter membership.
class BashingUnits extends Selector:
	## TargetResolver receives UNIT identities even when fewer than two participants remain.
	func output_kind(_ctx: RuleContext = null) -> int:
		return TargetRef.Kind.UNIT
	## Each picker rebuilds the distinct live set; resolved or departed participants cannot be selected.
	func resolve(_ctx: RuleContext) -> Array[TargetRef]:
		var result: Array[TargetRef] = []
		for encounter in Match.bashes:
			if encounter.resolved: continue
			var first := TargetRef.unit(encounter.attacker_id)
			var second := TargetRef.unit(encounter.defender_id)
			if not first.has_hex() or not second.has_hex() or first.hex_id() != encounter.target_hex or second.hex_id() != encounter.target_hex: continue
			for id in [encounter.attacker_id, encounter.defender_id]:
				var ref := TargetRef.unit(id)
				if ref.has_hex() and not result.any(func(other: TargetRef) -> bool: return other.id == id): result.append(ref)
		return result

## Shared read-only participant check is used by both selection stages and final preflight.
static func is_bashing(id: int) -> bool:
	for ref in BashingUnits.new().resolve(null):
		if ref.id == id: return true
	return false

## First choice requires two distinct live participants so a lone leftover cannot consume a deployment.
static func can_choose_bashing(subject: TargetRef, target: TargetRef) -> bool:
	return Action.can_return_to_hand(subject, target) and is_bashing(target.id) and BashingUnits.new().resolve(null).size() >= 2

## Records only the first identity; collecting the second choice must happen before either Return.
static func choose_bashing(subject: TargetRef, target: TargetRef) -> bool:
	return can_choose_bashing(subject, target)

## Final choice accepts another participant from any encounter and revalidates the retained first identity.
static func can_return_two(subject: TargetRef, target: TargetRef, first_id: int) -> bool:
	return first_id != target.id and is_bashing(first_id) and is_bashing(target.id) \
		and Action.can_return_to_hand(subject, TargetRef.unit(first_id)) and Action.can_return_to_hand(subject, target)

## Both identities are validated before mutation; nested Return events retain followups until the complete pair leaves.
static func return_two(subject: TargetRef, target: TargetRef, first_id: int) -> bool:
	if not can_return_two(subject, target, first_id): return false
	Match.rules_runner.begin_boundary()
	Action.return_to_hand(subject, TargetRef.unit(first_id))
	Action.return_to_hand(subject, target)
	Match.rules_runner.end_boundary()
	return true

## Shaman's atomic deployment payment addresses its owner explicitly and never deploys a unit.
static func can_spend_deployment(subject: TargetRef, target: TargetRef) -> bool:
	return subject != null and subject.kind == TargetRef.Kind.UNIT and target != null \
		and target.kind == TargetRef.Kind.PLAYER and Match.owner_of(subject) == target.id \
		and Match.players.has(target.id) and Match.players[target.id].deployments_remaining > 0

## CostPayment calls this only after its complete ledger succeeds; one resolved resource event is published.
static func spend_deployment(subject: TargetRef, target: TargetRef) -> bool:
	if not can_spend_deployment(subject, target): return false
	Match.players[target.id].deployments_remaining -= 1
	Match.action_event.emit(EffectEvent.new(&"spend_deployment", subject, target, {"amount": 1}))
	Match.state_changed.emit()
	return true

## Authors [A] -1 deploy followed by two distinct participant choices, without requiring a shared Bash.
static func shaman_return() -> Effect:
	var owner := QuerySelector.new(TargetRef.Kind.PLAYER)
	owner.relative_owner = Enum.YOU
	var payment := Effect.Verb.new(&"spend_deployment", spend_deployment, can_spend_deployment, TargetRef.Kind.UNIT, TargetRef.Kind.PLAYER)
	payment.atomic_cost = true
	var first := SynergyRules.phrase(Effect.Verb.new(&"choose_bashing", choose_bashing, can_choose_bashing,
		TargetRef.Kind.UNIT, TargetRef.Kind.UNIT), BashingUnits.new())
	var second := SynergyRules.phrase(Effect.Verb.new(&"return_two_bashing", return_two, can_return_two,
		TargetRef.Kind.UNIT, TargetRef.Kind.UNIT, [RuleBinding.new(&"step_0", RuleBinding.Field.UNIT_ID)]), BashingUnits.new())
	var result := SynergyRules.command(first, 0, true, Effect.CostPhrase.new(Selectors.Self.new(), payment, owner))
	result.consequence = Effect.ConsequenceSequence.new([first, second])
	result.condition = TwoBashing.new()
	return result
