class_name Action
extends RefCounted

## Disable accepts any existing unit in hand, regardless of owner; the authored target selector supplies ownership restrictions.
## Verbs.disable uses this for previews and commit, so moved/deployed/defeated choices cannot be substituted or disabled twice.
static func can_disable(subject: TargetRef, target: TargetRef) -> bool:
	if subject == null or target == null or subject.kind != TargetRef.Kind.UNIT or target.kind != TargetRef.Kind.UNIT: return false
	var unit := Match.get_unit(target.id)
	return Match.get_unit(subject.id) != null and unit != null and unit.t_state == Enum.t_state.UNDEPLOYED

## Moves a chosen hand unit directly to defeated while preserving health, counters and abilities; emits one Disable occurrence, not Die.
## Managed effects call this through Verbs.disable; boundary followups complete before command resources/turns continue.
## Defeating a hero still applies the general hero-loss rule, even though Disable does not cause death triggers.
static func disable(subject: TargetRef, target: TargetRef) -> bool:
	if not can_disable(subject, target): return false
	Match.rules_runner.begin_boundary()
	var unit := Match.get_unit(target.id)
	unit.t_state = Enum.t_state.DEFEATED
	unit.active = false
	unit.ihx = -1
	if unit.type == Enum.type.HERO: Match.winner = 3 - unit.player
	Match.action_event.emit(EffectEvent.new(&"disable", subject, target, {"owner": unit.player}))
	Match.state_changed.emit()
	Match.rules_runner.end_boundary()
	return true

## Verbs.return_to_hand() checks existing UNIT actors and deployed recipients; selectors supply ownership/range restrictions.
## Self, heroes and either owner are eligible; hand/defeated units cannot be returned from the board.
static func can_return_to_hand(subject: TargetRef, target: TargetRef) -> bool:
	if subject == null or target == null or subject.kind != TargetRef.Kind.UNIT or target.kind != TargetRef.Kind.UNIT: return false
	var unit := Match.get_unit(target.id)
	return Match.get_unit(subject.id) != null and unit != null and unit.t_state == Enum.t_state.DEPLOYED and target.has_hex()

## Managed phrases move the chosen board card to its owner's hand, inactive, preserving health, counters and definitions.
## One resolved Return occurrence captures its old hex/owner; Bash cleanup and derived control finish before followups resume.
## This is neither Reset, Revive, Deploy nor Die and does not spend resources outside the enclosing effect's cost policy.
static func return_to_hand(subject: TargetRef, target: TargetRef) -> bool:
	if not can_return_to_hand(subject, target): return false
	Match.rules_runner.begin_boundary()
	var unit := Match.get_unit(target.id)
	var last_hex := unit.ihx
	unit.t_state = Enum.t_state.UNDEPLOYED
	unit.ihx = -1
	unit.active = false
	Match.action_event.emit(EffectEvent.new(&"return_to_hand", subject, target, {"last_hex": last_hex, "owner": unit.player}))
	CombatResolver.cancel_dodged_bashes(target.id)
	Match.refresh_control()
	Match.state_changed.emit()
	Match.rules_runner.end_boundary()
	return true

## Reset selection accepts any existing unit with a printed baseline, including enemy units and the captured defeated source itself.
static func can_reset_unit(subject: TargetRef, target: TargetRef) -> bool:
	return subject != null and target != null and target.kind == TargetRef.Kind.UNIT \
		and Match.get_unit(target.id) != null and not Match.get_unit(target.id).printed_state.is_empty()

## Restores printed state in place; accumulated counters, wounds, copied effects and timed grants disappear without causing a return-to-hand occurrence.
static func reset_unit(subject: TargetRef, target: TargetRef) -> bool:
	if not can_reset_unit(subject, target): return false
	Match.rules_runner.begin_boundary()
	var unit := Match.get_unit(target.id)
	var previous := Vector2i(unit.actual_life, unit.max_life)
	unit.reset_printed_state()
	LifeChanges.publish(unit, previous, subject)
	Match.refresh_control()
	Match.action_event.emit(EffectEvent.new(&"reset", subject, target))
	Match.state_changed.emit()
	Match.rules_runner.end_boundary()
	return true

## Copy accepts an existing effect property and a deployed recipient, including a lethally wounded target whose definition still exists off-board.
static func can_copy_effect(subject: TargetRef, target: TargetRef) -> bool:
	if subject == null or subject.kind != TargetRef.Kind.UNIT or target == null: return false
	var unit := Match.get_unit(subject.id)
	return unit != null and unit.t_state == Enum.t_state.DEPLOYED and Match.get_property(target) is EffectOption

## Appends one chosen effect with independent future execution bindings; the original owner keeps it, and the recipient's Reset removes the copy.
static func copy_effect(subject: TargetRef, target: TargetRef) -> bool:
	if not can_copy_effect(subject, target): return false
	Match.rules_runner.begin_boundary()
	Match.get_unit(subject.id).add_effect_copy(Match.get_property(target))
	Match.refresh_control()
	Match.action_event.emit(EffectEvent.new(&"copy_effect", subject, target))
	Match.state_changed.emit()
	Match.rules_runner.end_boundary()
	return true

## Next-turn action grants require an existing player and a positive amount; the source can be a captured unit trigger.
static func can_next_turn_actions(subject: TargetRef, target: TargetRef, amount: int) -> bool:
	return subject != null and target != null and target.kind == TargetRef.Kind.PLAYER and Match.players.has(target.id) and amount > 0

## Adds a one-shot scheduled allowance bonus; Match.start_turn consumes it once, even if the original Swordsman has since left play.
static func next_turn_actions(subject: TargetRef, target: TargetRef, amount: int) -> bool:
	if not can_next_turn_actions(subject, target, amount): return false
	Match.players[target.id].next_turn_actions += amount
	Match.action_event.emit(EffectEvent.new(&"next_turn_actions", subject, target, {"amount": amount}))
	Match.state_changed.emit()
	return true

## Verbs.grant_deployments validates a positive grant to an existing player; a captured defeated source remains a valid actor.
static func can_grant_deployments(subject: TargetRef, target: TargetRef, amount: int) -> bool:
	return subject != null and subject.kind == TargetRef.Kind.UNIT and Match.get_unit(subject.id) != null \
		and target != null and target.kind == TargetRef.Kind.PLAYER and Match.players.has(target.id) and amount > 0

## Adds remaining deployments without deploying cards or granting actions; the trigger runner owns activation and acknowledgement timing.
## Emits one resolved resource event and state refresh inside a runner boundary so player info updates after the mutation.
static func grant_deployments(subject: TargetRef, target: TargetRef, amount: int) -> bool:
	if not can_grant_deployments(subject, target, amount): return false
	Match.rules_runner.begin_boundary()
	Match.players[target.id].deployments_remaining += amount
	Match.action_event.emit(EffectEvent.new(&"grant_deployments", subject, target, {"amount": amount}, &"resolved"))
	Match.state_changed.emit()
	Match.rules_runner.end_boundary()
	return true

static func can_deactivate(_subject: TargetRef, target: TargetRef) -> bool:
	var info := Match.get_unit(target.id)
	return info != null and info.active and info.t_state != Enum.t_state.DEFEATED

static func deactivate(subject: TargetRef, target: TargetRef) -> bool:
	if not can_deactivate(subject, target): return false
	Match.get_unit(target.id).active = false
	Match.deactivate.emit(subject, target)
	Match.action_event.emit(EffectEvent.new(&"deactivate", subject, target))
	return true

## Checks active deployed SELF, a positive authored Stun payment and required tokens before payment; ordinary costs use one.
## Verbs.pay_activity binds this atomic cost; Action-free exempts only its token check.
static func can_pay_activity(subject: TargetRef, target: TargetRef, action_free: bool = false, amount: int = 1) -> bool:
	if amount < 1: return false
	if subject == null or target == null or not subject.same(target) or target.kind != TargetRef.Kind.UNIT: return false
	var unit := Match.get_unit(target.id)
	if unit == null or unit.t_state != Enum.t_state.DEPLOYED or not unit.active: return false
	if not Match.rules_runner.is_triggered() and (Match.phase != Match.Phase.ACTION or unit.player != Match.active_player): return false
	if not Match.rules_runner.is_triggered() and Match.players[unit.player].actions_remaining <= 0 and not action_free: return false
	var stun := Match.get_property(TargetRef.property(target, UnitInfo.STUN_COUNTER))
	return stun != null and stun.increment == Enum.p_increment.COUNTER

## Pays the authored positive self-Stun amount after PhraseExecution validates activity; ordinary actions use one, Flying Squirrel uses two.
## Action-free permits payment without a token; own Start removes one Stun and own End activates only if none remain.
static func pay_activity(subject: TargetRef, target: TargetRef, action_free: bool = false, amount: int = 1) -> bool:
	if not can_pay_activity(subject, target, action_free, amount): return false
	var unit := Match.get_unit(target.id)
	var stun := Match.get_property(TargetRef.property(target, UnitInfo.STUN_COUNTER))
	unit.active = false
	stun.value += amount
	Match.action_event.emit(EffectEvent.new(&"stun", subject, target, {"amount": amount, "self_cost": true}))
	return true

static func can_damage(_subject: TargetRef, _target: TargetRef, amount: int) -> bool:
	return amount >= 0

static func damage(subject: TargetRef, target: TargetRef, amount: int) -> bool:
	# Preserve the prototype's combat-resolver signal contract.
	Match.fire.emit(subject, target, amount)
	Match.action_event.emit(EffectEvent.new(&"damage", subject, target, {"amount": amount}))
	return true

## Checks a deployed Bow-upgrade recipient; authored selectors determine ownership, and the source may have paid a lethal cost.
static func can_upgrade_bow(subject: TargetRef, target: TargetRef, damage: int, range: int) -> bool:
	if subject == null or target == null or subject.kind != TargetRef.Kind.UNIT or Match.get_unit(subject.id) == null or target.kind != TargetRef.Kind.UNIT: return false
	var unit := Match.get_unit(target.id)
	return unit != null and unit.t_state == Enum.t_state.DEPLOYED and damage >= 0 and range >= 0

## Adds permanent Bow damage/range counters to the live unit; Reed Archer's Wound trigger invokes this.
static func upgrade_bow(subject: TargetRef, target: TargetRef, damage: int, range: int) -> bool:
	if not can_upgrade_bow(subject, target, damage, range): return false
	var unit := Match.get_unit(target.id)
	unit.add_bow_counters(damage, range)
	Match.action_event.emit(EffectEvent.new(&"upgrade_bow", subject, target,
		{"damage": damage, "range": range}))
	return true

## Permanent Cannon upgrades share Bow's recipient/amount legality; authored selectors determine ownership and source binding.
static func can_upgrade_cannon(subject: TargetRef, target: TargetRef, damage: int, range: int) -> bool:
	return can_upgrade_bow(subject, target, damage, range)

## Mara's friendly-Disable trigger awards stored Cannon counters without editing reusable abilities; preview and combat read the same derived values.
static func upgrade_cannon(subject: TargetRef, target: TargetRef, damage: int, range: int) -> bool:
	if not can_upgrade_cannon(subject, target, damage, range): return false
	Match.rules_runner.begin_boundary()
	Match.get_unit(target.id).add_cannon_counters(damage, range)
	Match.action_event.emit(EffectEvent.new(&"upgrade_cannon", subject, target, {"damage": damage, "range": range}))
	Match.state_changed.emit()
	Match.rules_runner.end_boundary()
	return true

## Validates a temporary action-value grant for an identified deployed recipient.
## Verbs.grant_action_values() calls this before showing or committing a unit choice.
static func can_grant_action_values(subject: TargetRef, target: TargetRef,
		family: StringName, values: Array[int]) -> bool:
	if subject == null or subject.kind != TargetRef.Kind.UNIT or not subject.valid(): return false
	if target == null or target.kind != TargetRef.Kind.UNIT or not target.valid(): return false
	var source_unit := Match.get_unit(subject.id)
	var recipient := Match.get_unit(target.id)
	return source_unit != null and recipient != null and recipient.t_state == Enum.t_state.DEPLOYED \
		and not family.is_empty() and not values.is_empty()

## Grants a concrete action-value bonus through the active player's End cleanup.
## PhraseExecution commits this after target selection; Match._next_turn expires it after End triggers.
static func grant_action_values(subject: TargetRef, target: TargetRef,
		family: StringName, values: Array[int]) -> bool:
	if not can_grant_action_values(subject, target, family, values): return false
	var recipient := Match.get_unit(target.id)
	var grant := TimedGrant.action_values(Match.allocate_timed_grant_id(), subject,
		family, values, Match.active_player, Match.turn_number)
	recipient.timed_grants.append(grant)
	Match.action_event.emit(EffectEvent.new(&"grant_action_values", subject, target, {
		"family": family, "values": values.duplicate(), "grant_id": grant.id,
		"expires_player": grant.expires_player, "expires_turn": grant.expires_turn}))
	return true

## Timed modifier selection requires a concrete deployed recipient; card selectors own ownership and triggering eligibility.
static func can_grant_modifiers(subject: TargetRef, target: TargetRef, physical: int, magical: int,
		enemy_end: bool = false, _stack: bool = false) -> bool:
	return can_grant_action_values(subject, target, &"modifiers", [physical, magical])

## Captures modifiers through current End or enemy End. Identical awards refresh unless the card explicitly stacks each payment.
## Match cleanup and snapshot persistence use the shared typed TimedGrant records for either policy.
static func grant_modifiers(subject: TargetRef, target: TargetRef, physical: int, magical: int,
		enemy_end: bool = false, stack: bool = false) -> bool:
	if not can_grant_modifiers(subject, target, physical, magical): return false
	var expiry_player := 3 - Match.owner_of(subject) if enemy_end else Match.active_player
	var expiry_turn := Match.turn_number + (1 if expiry_player != Match.active_player else 0)
	var recipient := Match.get_unit(target.id)
	if not stack:
		for grant in recipient.timed_grants:
			if grant.kind == TimedGrant.Kind.MODIFIERS and grant.source.same(subject) and grant.parameters == [physical, magical] \
					and grant.expires_player == expiry_player:
				grant.expires_turn = expiry_turn
				return true
	var grant := TimedGrant.modifiers(Match.allocate_timed_grant_id(), subject, [physical, magical], expiry_player, expiry_turn)
	recipient.timed_grants.append(grant)
	Match.action_event.emit(EffectEvent.new(&"grant_modifiers", subject, target, {"values": [physical, magical], "grant_id": grant.id}))
	Match.refresh_control()
	Match.state_changed.emit()
	return true

## Checks a life adjustment on any existing selected unit; selectors own recipient restrictions, and paid defeated sources remain valid.
## Verbs.up_life() calls this for previews and commit; positive health on a defeated unit does not implicitly Revive it.
static func can_up_life(subject: TargetRef, target: TargetRef, actual_delta: int, max_delta: int) -> bool:
	if subject == null or target == null or subject.kind != TargetRef.Kind.UNIT or target.kind != TargetRef.Kind.UNIT: return false
	var unit := Match.get_unit(target.id)
	return Match.get_unit(subject.id) != null and unit != null and unit.max_life + max_delta >= 0 and (actual_delta != 0 or max_delta != 0)

## Permanently adjusts actual/max life, clamps to the new maximum, and defeats at zero life.
## Captured card triggers such as Squirrel King and Thunder Toad invoke this action.
## Records the actual maximum-life delta and responsible source before emitting events for hover provenance.
static func up_life(subject: TargetRef, target: TargetRef, actual_delta: int, max_delta: int) -> bool:
	if not can_up_life(subject, target, actual_delta, max_delta): return false
	Match.rules_runner.begin_boundary()
	var unit := Match.get_unit(target.id)
	var old_life := unit.actual_life
	var old_max := unit.max_life
	unit.max_life = maxi(0, unit.max_life + max_delta)
	unit.record_max_life_change(subject, unit.max_life - old_max)
	unit.actual_life = clampi(unit.actual_life + actual_delta, 0, unit.max_life)
	LifeChanges.publish(unit, Vector2i(old_life, old_max), subject)
	Match.action_event.emit(EffectEvent.new(&"up_life", subject, target,
		{"actual": unit.actual_life - old_life, "max": max_delta}))
	if unit.actual_life == 0:
		Match.defeat(target, Match.owner_of(subject))
	else:
		Match.refresh_control()
		Match.state_changed.emit()
	Match.rules_runner.end_boundary()
	return true

## Includes Action-free in Fire legality while leaving activity cost to EffectExecution.
## Verbs.fire() binds this check; PhraseExecution calls it before offering and committing hexes.
static func can_fire(subject: TargetRef, target: TargetRef, amount: int, _instant: bool,
		_pierce: bool, action_free: bool) -> bool:
	return CombatResolver.can_fire(subject, target, amount, action_free)

## Declares Fire with its action-token exemption passed to the resolver.
## The Verb created by Verbs.fire() calls this after its matching legality check.
static func fire(subject: TargetRef, target: TargetRef, amount: int, instant: bool = false,
		pierce: bool = false, action_free: bool = false) -> bool:
	return CombatResolver.declare_fire(subject, target, amount, instant, pierce, action_free)

## Checks the captured Bow action's amount, range, phase, token, and enemy/empty destination.
## Verbs.bow() invokes it while deriving the phrase's legal target hexes.
static func can_bow(subject: TargetRef, target: TargetRef, amount: int, range: int,
		_instant: bool, _pierce: bool, action_free: bool) -> bool:
	return CombatResolver.can_bow(subject, target, amount, range, action_free)

## Captures or immediately resolves Bow after phrase selection.
## Verbs.bow() calls this after can_bow() succeeds.
static func bow(subject: TargetRef, target: TargetRef, amount: int, range: int,
		instant: bool = false, pierce: bool = false, action_free: bool = false) -> bool:
	return CombatResolver.declare_bow(subject, target, amount, range, instant, pierce, action_free)

## Checks Cannon's straight-line endpoint and normal player-token requirement.
## Verbs.cannon() calls this before a target is offered and again at commit.
static func can_cannon(subject: TargetRef, target: TargetRef, amount: int, range: int,
		_instant: bool, _pierce: bool, action_free: bool) -> bool:
	return CombatResolver.can_cannon(subject, target, amount, range, action_free)

## Captures every playable hex along a legal Cannon line.
## Verbs.cannon() calls this after the player chooses an endpoint.
static func cannon(subject: TargetRef, target: TargetRef, amount: int, range: int,
		instant: bool = false, pierce: bool = false, action_free: bool = false) -> bool:
	return CombatResolver.declare_cannon(subject, target, amount, range, instant, pierce, action_free)

## Checks Bomb-throw amount, range, turn ownership, and token availability.
## Verbs.bomb_throw() invokes it for target previews and again at commit.
static func can_bomb_throw(subject: TargetRef, target: TargetRef, amount: int, range: int,
		_pierce: bool, action_free: bool) -> bool:
	return CombatResolver.can_bomb_throw(subject, target, amount, range, action_free)

## Places an inert bomb or merges its damage into the existing bomb on that hex.
## Verbs.bomb_throw() calls this after the selected target passes legality.
static func bomb_throw(subject: TargetRef, target: TargetRef, amount: int, range: int,
		pierce: bool = false, action_free: bool = false) -> bool:
	return CombatResolver.throw_bomb(subject, target, amount, range, pierce, action_free)

## Checks that an inert bomb lies within the defuse action's declared radius.
## Verbs.defuse_bomb() invokes it before exposing candidate hexes.
static func can_defuse_bomb(subject: TargetRef, target: TargetRef, range: int,
		action_free: bool) -> bool:
	return CombatResolver.can_defuse_bomb(subject, target, range, action_free)

## Removes the selected inert bomb and reports the defuse event.
## Verbs.defuse_bomb() calls it through the ordinary PhraseExecution path.
static func defuse_bomb(subject: TargetRef, target: TargetRef, range: int,
		action_free: bool) -> bool:
	return CombatResolver.defuse_bomb(subject, target, range, action_free)

## Validates a straight-line Gore leap before PhraseExecution offers its destination hex.
## Verbs.gore() binds this check; landing legality and path capture use CombatResolver.
static func can_gore(subject: TargetRef, target: TargetRef, amount: int, range: int,
		action_free: bool) -> bool:
	return CombatResolver.can_gore(subject, target, amount, range, action_free)

## Leaps immediately and queues captured physical hits for the next combat window.
## The selected HEX is the landing tile; CombatResolver captures enemies crossed en route.
static func gore(subject: TargetRef, target: TargetRef, amount: int, range: int,
		action_free: bool = false) -> bool:
	return CombatResolver.declare_gore(subject, target, amount, range, action_free)

## Checks Move range and path blocking before a destination is shown or committed.
## Verbs.movement(..., false) supplies the range and token sticker.
static func can_move(subject: TargetRef, target: TargetRef, range: int, action_free: bool) -> bool:
	return CombatResolver.can_move(subject, target, range, false, action_free)

## Moves SELF immediately; an enemy landing creates the normal delayed Bash.
## PhraseExecution calls this after the current destination remains legal.
static func move(subject: TargetRef, target: TargetRef, range: int, action_free: bool) -> bool:
	return CombatResolver.move_unit(subject, target, range, false, action_free)

## Checks Fly range and landing rules while ignoring all intermediate occupancy.
## Verbs.movement(..., true) supplies the range and token sticker.
static func can_fly(subject: TargetRef, target: TargetRef, range: int, action_free: bool) -> bool:
	return CombatResolver.can_move(subject, target, range, true, action_free)

## Flies SELF immediately; an enemy landing creates the normal delayed Bash.
## PhraseExecution calls this after the chosen destination remains legal.
static func fly(subject: TargetRef, target: TargetRef, range: int, action_free: bool) -> bool:
	return CombatResolver.move_unit(subject, target, range, true, action_free)

## Checks allied target identity, healing need, range, phase, and action-token availability.
## Verbs.mend() calls this during preview and PhraseExecution repeats it before commit.
static func can_mend(subject: TargetRef, target: TargetRef, amount: int, range: int,
		action_free: bool) -> bool:
	return CombatResolver.can_mend(subject, target, amount, range, action_free)

## Restores up to the printed amount without exceeding the recipient's starting life.
## Verbs.mend() calls this after the selected ally remains legal.
static func mend(subject: TargetRef, target: TargetRef, amount: int, range: int,
		action_free: bool) -> bool:
	return CombatResolver.mend(subject, target, amount, range, action_free)

## Checks hostile Stun target, range, phase, and token before a choice is offered.
## Verbs.stun() calls this during preview and PhraseExecution repeats it before commit.
static func can_stun(subject: TargetRef, target: TargetRef, amount: int, range: int,
		action_free: bool) -> bool:
	return CombatResolver.can_stun(subject, target, amount, range, action_free)

## Deactivates the selected enemy and adds the authored Stun duration.
## CombatResolver preserves every other counter, including temporary protection; Reset is the separate clearing action.
static func stun(subject: TargetRef, target: TargetRef, amount: int, range: int,
		action_free: bool) -> bool:
	return CombatResolver.stun(subject, target, amount, range, action_free)

## Revive accepts a defeated allied non-hero other than SELF for death triggers or a paid Warlock command.
## PhraseExecution/RulesRunner own activation eligibility; the verb checks recipient identity/zone without requiring a trigger-only caller.
static func can_revive(subject: TargetRef, target: TargetRef) -> bool:
	if Match.winner != 0: return false
	if subject == null or target == null or subject.kind != TargetRef.Kind.UNIT \
			or target.kind != TargetRef.Kind.UNIT or subject.id == target.id: return false
	var source_unit := Match.get_unit(subject.id)
	var target_unit := Match.get_unit(target.id)
	return source_unit != null and target_unit != null and target_unit.t_state == Enum.t_state.DEFEATED \
		and target_unit.type != Enum.type.HERO and target_unit.max_life > 0 and source_unit.player == target_unit.player

## Returns a defeated allied non-hero to reserve at full life without deploying it.
## Triggered death effects and paid Warlock commands call this; stable IDs and stored properties remain attached.
## Also emits a return_to_hand occurrence for recovery watchers; Reset remains a distinct in-place action.
static func revive(subject: TargetRef, target: TargetRef) -> bool:
	if not can_revive(subject, target): return false
	Match.rules_runner.begin_boundary()
	var unit := Match.get_unit(target.id)
	unit.actual_life = unit.max_life
	unit.active = false
	unit.t_state = Enum.t_state.UNDEPLOYED
	unit.ihx = -1
	Match.action_event.emit(EffectEvent.new(&"revive", subject, target,
		{"life": unit.actual_life, "max_life": unit.max_life}, &"resolved"))
	Match.action_event.emit(EffectEvent.new(&"return_to_hand", subject, target))
	Match.refresh_control()
	Match.state_changed.emit()
	Match.rules_runner.end_boundary()
	return true

## Checks aligned unit displacement and destination occupancy for Push or Pull.
## The corresponding named verb calls this during preview and commit.
static func can_displace(subject: TargetRef, target: TargetRef, distance: int, range: int,
		pull: bool, action_free: bool) -> bool:
	return CombatResolver.can_displace(subject, target, distance, range, pull, action_free)

## Moves the selected unit along an axial line; an enemy landing creates a delayed Bash.
## Verbs.push()/pull() call this after the chosen unit remains legal.
static func displace(subject: TargetRef, target: TargetRef, distance: int, range: int,
		pull: bool, action_free: bool) -> bool:
	return CombatResolver.displace(subject, target, distance, range, pull, action_free)

## Checks an inert Bomb's axial displacement and merge destination.
## Verbs.push_bomb()/pull_bomb() use this explicit HEX-target contract.
static func can_displace_bomb(subject: TargetRef, target: TargetRef, distance: int, range: int,
		pull: bool, action_free: bool) -> bool:
	return CombatResolver.can_displace_bomb(subject, target, distance, range, pull, action_free)

## Moves an inert bomb or merges it into a bomb at the landing tile.
## The named Bomb displacement verbs call this through PhraseExecution.
static func displace_bomb(subject: TargetRef, target: TargetRef, distance: int, range: int,
		pull: bool, action_free: bool) -> bool:
	return CombatResolver.displace_bomb(subject, target, distance, range, pull, action_free)

## Shield normally protects friends; the Paladin's explicit enemy-hero mode accepts only that opposing deployed hero.
static func can_shield(subject: TargetRef, target: TargetRef, amount: int, magical: bool, enemy_hero: bool = false) -> bool:
	if amount < 0 or target == null or target.kind != TargetRef.Kind.UNIT or not target.has_hex(): return false
	var friendly := Match.owner_of(subject) == Match.owner_of(target)
	if enemy_hero:
		if friendly or Match.get_unit(target.id).type != Enum.type.HERO: return false
	elif not friendly: return false
	var key := UnitInfo.TEMP_MAGICAL_COUNTER if magical else UnitInfo.TEMP_PHYSICAL_COUNTER
	var counter := Match.get_property(TargetRef.property(target, key))
	return counter != null and counter.increment == Enum.p_increment.COUNTER

## Shield verbs commit one checked temporary counter gain and retain the granting source in the emitted occurrence.
static func shield(subject: TargetRef, target: TargetRef, amount: int, magical: bool, enemy_hero: bool = false) -> bool:
	if not can_shield(subject, target, amount, magical, enemy_hero): return false
	var key := UnitInfo.TEMP_MAGICAL_COUNTER if magical else UnitInfo.TEMP_PHYSICAL_COUNTER
	var counter := Match.get_property(TargetRef.property(target, key))
	if counter == null or counter.increment != Enum.p_increment.COUNTER: return false
	counter.value += amount
	Match.action_event.emit(EffectEvent.new(&"mshield" if magical else &"shield", subject, target, {"amount": amount}))
	return true

static func can_decrement(_subject: TargetRef, target: TargetRef, amount: int) -> bool:
	var prop := Match.get_property(target)
	return prop != null and prop.increment == Enum.p_increment.COUNTER and amount > 0 and prop.value >= amount

static func decrement(subject: TargetRef, target: TargetRef, amount: int) -> bool:
	if not can_decrement(subject, target, amount): return false
	Match.get_property(target).value -= amount
	Match.action_event.emit(EffectEvent.new(&"decrement", subject, target, {"amount": amount}))
	return true

static func can_change_counter(_subject: TargetRef, target: TargetRef, _delta: int) -> bool:
	var counter := Match.get_property(target)
	return counter != null and counter.increment == Enum.p_increment.COUNTER

## PROPERTY-targeted grants publish the same positive Ember occurrence as UNIT resource awards; removals never trigger Alchemist.
static func change_counter(subject: TargetRef, target: TargetRef, delta: int) -> bool:
	if not can_change_counter(subject, target, delta): return false
	Match.get_property(target).value += delta
	if target.host.kind == TargetRef.Kind.UNIT: Match.get_unit(target.host.id).publish_ember_gain(target.property_key, delta)
	Match.action_event.emit(EffectEvent.new(&"change_counter", subject, target, {"delta": delta}))
	return true

static func can_set_flag(_subject: TargetRef, target: TargetRef, _value: bool) -> bool:
	var prop := Match.get_property(target)
	return prop != null and prop.increment == Enum.p_increment.FLAG

static func set_flag(subject: TargetRef, target: TargetRef, value: bool) -> bool:
	if not can_set_flag(subject, target, value): return false
	Match.get_property(target).value = int(value)
	Match.action_event.emit(EffectEvent.new(&"set_flag", subject, target, {"value": value}))
	return true
