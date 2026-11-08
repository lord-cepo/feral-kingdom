## Preflights supported resource costs using a shadow ledger, then commits their fixed choices.
## No disposable live-Match mutation, rollback, signals, or trigger capture occurs in preflight.
class_name CostPayment
extends RefCounted

## Checks cumulative counter/activity spending before mutating any selected resource.
## EffectExecution calls after collecting identities/amounts without payment; live bindings and cumulative ledgers reject stale or overspent X.
## Selection-only anchors do not mutate; Disable/Return/Sacrifice reserve departures and deployment payments share a cumulative player ledger.
## A committed Sacrifice records actual life before defeat so the Alchemist can read its paid amount.
static func commit(choices: Array[PhraseExecution]) -> String:
	var counters: Dictionary = {}
	var activity: Dictionary = {}
	var life: Dictionary = {}
	var departures: Dictionary = {}
	var deployments: Dictionary = {}
	for choice in choices:
		var verb := choice.phrase.verb.bound_to(choice)
		if choice.targets.size() != 1: return "Every payment needs one chosen identity."
		var target := choice.targets[0]
		var host_id := target.host.id if target.kind == TargetRef.Kind.PROPERTY and target.host.kind == TargetRef.Kind.UNIT else target.id if target.kind == TargetRef.Kind.UNIT else -1
		if host_id >= 0 and departures.has(host_id): return "A departed unit cannot fund another payment."
		if not choice._still_legal(target): return "A selected payment is no longer legal."
		if verb.name == &"spend_deployment":
			var remaining: int = deployments.get(target.id, Match.players[target.id].deployments_remaining)
			if remaining < 1: return "The complete deployment payment cannot be paid."
			deployments[target.id] = remaining - 1
		elif verb.name in [&"disable", &"return_to_hand"]:
			departures[target.id] = true
		elif verb.name == &"sacrifice":
			if life.has(target.id) and life[target.id].x <= 0: return "A defeated life payer cannot also be sacrificed."
			departures[target.id] = true
		elif verb.name == &"decrement":
			var key := target.identity()
			var value: int = counters.get(key, Match.get_property(target).value)
			var amount: int = verb.user_params[0]
			if value < amount: return "The complete cost bundle cannot be paid."
			counters[key] = value - amount
		elif verb.name == &"pay_life":
			var unit := Match.get_unit(target.id)
			var value: Vector2i = life.get(target.id, Vector2i(unit.actual_life, unit.max_life))
			var actual: int = verb.user_params[0]
			var maximum: int = verb.user_params[1]
			if value.x <= 0 or value.x < actual or value.y < maximum: return "The complete life payment cannot be paid."
			life[target.id] = Vector2i(mini(value.x - actual, value.y - maximum), value.y - maximum)
		elif verb.name == &"next_turn_actions":
			pass # Positive grants have no spendable balance; identity/amount legality was checked above.
		elif verb.name == &"choose_counter_unit":
			pass # Identity-only anchor; its dependent property and amount are preflighted separately.
		elif verb.name in [&"self_stun", &"deactivate"]:
			if activity.has(target.id): return "The same activity cannot be paid twice."
			activity[target.id] = false
			if verb.name == &"self_stun":
				var stun := TargetRef.property(target, UnitInfo.STUN_COUNTER)
				counters[stun.identity()] = int(counters.get(stun.identity(), Match.get_property(stun).value)) + int(verb.user_params[1])
		else: return "Unsupported atomic bundle payment."
	# Fixed built-in operations below cannot fail after the above preflight. Apply
	# resource deltas directly so no intervening callback can change later legality.
	Match.rules_runner.begin_boundary()
	var events: Array[EffectEvent] = []
	for choice in choices:
		var verb := choice.phrase.verb.bound_to(choice)
		var target := choice.targets[0]
		if verb.name == &"spend_deployment":
			AdventurerRules.spend_deployment(choice.subject, target)
			continue
		elif verb.name == &"disable":
			Action.disable(choice.subject, target)
			continue
		elif verb.name == &"return_to_hand":
			Action.return_to_hand(choice.subject, target)
			continue
		elif verb.name == &"sacrifice":
			choice.chosen_amount = Match.get_unit(target.id).actual_life
			SynergyActions.sacrifice(choice.subject, target)
			continue # Sacrifice and Die were published by the shared mutation.
		elif verb.name == &"decrement":
			var amount: int = verb.user_params[0]
			Match.get_property(target).value -= amount
			events.append(EffectEvent.new(&"decrement", choice.subject, target, {"amount": amount}))
		elif verb.name == &"pay_life":
			WoodlandActions.pay_life(choice.subject, target, int(verb.user_params[0]), int(verb.user_params[1]))
			continue # The health action publishes its own cost/Die events once.
		elif verb.name == &"next_turn_actions":
			Action.next_turn_actions(choice.subject, target, int(verb.user_params[0]))
			continue
		elif verb.name == &"choose_counter_unit":
			continue # Choosing a resource host is not a fictional gameplay occurrence.
		else:
			Match.get_unit(target.id).active = false
			if verb.name == &"self_stun":
				var amount: int = verb.user_params[1]
				Match.get_property(TargetRef.property(target, UnitInfo.STUN_COUNTER)).value += amount
				events.append(EffectEvent.new(&"stun", choice.subject, target, {"amount": amount, "self_cost": true}))
			else: events.append(EffectEvent.new(&"deactivate", choice.subject, target))
		# Capture membership at each payment, before the next payment changes state.
		Match.rules_runner.capture_event(events.back())
	for event in events:
		Match.action_event.emit(event)
		if event.action == &"deactivate": Match.deactivate.emit(event.subject, event.target)
	Match.rules_runner.end_boundary()
	return ""
