## Retained player-info rows; resource changes bump only their own line without changing match state or phase timing.
extends VBoxContainer

var rows: Dictionary = {}
var initialized := false

## LocalMatchController._refresh_hud() supplies authoritative player state after resource changes and turn boundaries.
## Initial values establish a quiet baseline; later changes to deployments, actions or named counters grow and settle their own row.
## Pending next-turn actions have their own line while nonzero, separate from currently spendable actions.
func sync_player(player: Player) -> void:
	var entries: Array[Dictionary] = [
		{"key": "name", "title": player.name if not player.name.is_empty() else "Player %d" % player.id, "value": null},
		{"key": "deployments", "title": "Deployments", "value": player.deployments_remaining},
		{"key": "actions", "title": "Actions", "value": player.actions_remaining}]
	if player.next_turn_actions > 0:
		entries.append({"key": "next_actions", "title": "Next turn actions", "value": player.next_turn_actions})
	for prop: Prop in player.props:
		if prop != null and prop.increment == Enum.p_increment.COUNTER:
			entries.append({"key": "counter:" + prop.name, "title": prop.name, "value": prop.value})
	var live_keys: Array[String] = []
	for index in entries.size():
		var entry: Dictionary = entries[index]
		var key: String = entry.key
		live_keys.append(key)
		var added := not rows.has(key)
		if added:
			var label := Label.new()
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			label.add_theme_font_size_override("font_size", 16)
			label.resized.connect(func() -> void: label.pivot_offset = label.size * 0.5)
			add_child(label)
			rows[key] = {"label": label, "value": entry.value, "tween": null}
		var row: Dictionary = rows[key]
		var label: Label = row.label
		label.add_theme_color_override("font_color", Color("#ef7770") if player.id == 1 else Color("#6da9ee"))
		label.text = entry.title if entry.value == null else "%s: %d" % [entry.title, entry.value]
		move_child(label, index)
		if initialized and entry.value != null and (added or row.value != entry.value): _bump(row)
		row.value = entry.value
	for key in rows.keys():
		if key in live_keys: continue
		var row: Dictionary = rows[key]
		if row.tween != null: row.tween.kill()
		var label: Label = row.label
		var fade := create_tween()
		fade.tween_property(label, "modulate:a", 0.0, 0.18)
		fade.tween_callback(label.queue_free)
		rows.erase(key)
	initialized = true

## Controller blocked-deployment clicks call this to emphasize the existing deployments row without changing its value or any match resource.
func bump_deployments() -> void:
	if rows.has("deployments"): _bump(rows["deployments"])

## sync_player() and explicit resource feedback share this pulse; unchanged refreshes do not restart it, and repeated requests retarget from the visible scale.
func _bump(row: Dictionary) -> void:
	if row.tween != null: row.tween.kill()
	var label: Label = row.label
	label.pivot_offset = label.size * 0.5
	row.tween = create_tween()
	row.tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	row.tween.tween_property(label, "scale", Vector2.ONE * 1.12, 0.12)
	row.tween.tween_property(label, "scale", Vector2.ONE, 0.22)
