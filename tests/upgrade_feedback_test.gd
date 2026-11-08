## Focused cosmetic value-observer regression; run only when requested with TEST.
extends "res://tests/synergy_units_test.gd"

## Dedicated scene checks actual life/action mutations, silent baselines, duplicate notifications and ordered recipient feedback.
func _ready() -> void:
	Match.action_event.connect(record)
	fixture()
	var friend := add(SynergyCatalogue.tamia_archer(1), 0)
	var enemy := add(SynergyCatalogue.tamia_archer(2), 4)
	# Separate regions keep these life-only scenarios independent of control bonus gains.
	Match.map[4].region_count = 1
	friend.actual_life = 8
	friend.max_life = 8
	var observer := preload("res://scripts/board/serial_feedback.gd").new()
	observer.observe()
	check(observer.pending.is_empty(), "Initial deployed values do not animate")
	check(Action.up_life(TargetRef.unit(friend.iun), TargetRef.unit(friend.iun), 0, 2), "Maximum life gain commits")
	observer.observe()
	check(observer.pending.size() == 1 and observer.pending[0].unit == friend, "Positive life change queues one exact-recipient upgrade")
	observer.observe()
	check(observer.pending.size() == 1, "Repeated state notification never duplicates an upgrade")
	friend.actual_life -= 1
	observer.observe()
	check(observer.pending.size() == 1, "Damage does not play upgrade")
	check(Action.upgrade_bow(TargetRef.unit(friend.iun), TargetRef.unit(enemy.iun), 1, 1), "Enemy recipient attack values can increase")
	observer.observe()
	check(observer.pending.size() == 2 and observer.pending[1].unit == enemy, "Both owners receive upgrade feedback in occurrence order")
	check(Action.upgrade_bow(TargetRef.unit(friend.iun), TargetRef.unit(enemy.iun), 0, 0), "No-op attack grant is legal")
	observer.observe()
	check(observer.pending.size() == 2, "Zero deltas never queue upgrade")
	friend.t_state = Enum.t_state.UNDEPLOYED
	observer.observe()
	friend.max_life += 1
	observer.observe()
	check(observer.pending.size() == 2, "Off-board gains do not animate")
	friend.t_state = Enum.t_state.DEPLOYED
	observer.observe()
	check(observer.pending.size() == 2, "Re-deployment establishes a silent baseline")
	observer.pending.clear()
	observer.enqueue(friend, "shield", 1.5)
	observer.enqueue(enemy, "upgrade", 1.125)
	check(observer.busy() and observer.pending[0].clip == "shield" and observer.pending[1].clip == "upgrade", "Finite recipient feedback is retained in FIFO order and holds phase continuation")
	observer.free()
	print("Upgrade feedback: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
