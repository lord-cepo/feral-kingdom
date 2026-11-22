extends Control

const Harness = preload("res://scripts/runtime/headless_match.gd")
const TERRAIN := preload("res://assets/maps/pixellab-battlefield.png")
var games: Array[Dictionary] = []
var frames: Array[Dictionary] = []
var harness := Harness.new()
var steps: Array = []
var picker := OptionButton.new()
var previous := Button.new()
var next := Button.new()
var status := Label.new()
var detail := Label.new()
var field := Control.new()
var position_index := 0
var failure := ""

## Builds the viewer and opens the first locally recorded training game.
func _ready() -> void:
	var layout := VBoxContainer.new()
	add_child(layout)
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 20)
	var controls := HBoxContainer.new()
	layout.add_child(controls)
	var back := Button.new()
	back.text = "Menu"
	back.pressed.connect(func() -> void: get_tree().change_scene_to_file("res://scenes/army_menu.tscn"))
	controls.add_child(back)
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	picker.item_selected.connect(_select_game)
	controls.add_child(picker)
	var open := Button.new()
	open.text = "Open replay file"
	controls.add_child(open)
	var dialog := FileDialog.new()
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dialog.filters = PackedStringArray(["*.jsonl ; Training games"])
	add_child(dialog)
	open.pressed.connect(func() -> void: dialog.popup_centered_ratio(0.75))
	dialog.file_selected.connect(_open_file)
	previous.text = "←"
	next.text = "→"
	previous.pressed.connect(_step.bind(-1))
	next.pressed.connect(_step.bind(1))
	controls.add_child(previous)
	controls.add_child(next)
	layout.add_child(status)
	field.size_flags_vertical = Control.SIZE_EXPAND_FILL
	field.clip_contents = true
	field.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	field.draw.connect(_draw_position)
	field.resized.connect(field.queue_redraw)
	layout.add_child(field)
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(detail)
	for directory in ["res://.godot/mcts-replays", "user://training-replays"]:
		if DirAccess.open(directory) == null: continue
		for filename in DirAccess.get_files_at(directory):
			if filename.ends_with(".jsonl"): _load_file(directory.path_join(filename))
	if games.is_empty(): _update_display()
	else: _select_game(0)

## Adds recorded games from the selected shard and opens its first game.
func _open_file(path: String) -> void:
	var index := games.size()
	_load_file(path)
	if index < games.size():
		_select_game(index)
	else:
		detail.text = "This file contains no recorded move sequences."

## Reads full-catalogue records, including capped games with committed moves.
func _load_file(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return
	while not file.eof_reached():
		var line := file.get_line()
		if line.strip_edges().is_empty(): continue
		var parser := JSON.new()
		if parser.parse(line) != OK: continue
		var game: Variant = parser.data
		if not game is Dictionary or game.get("rejected", true) or game.get("pairing") != "full-catalogue": continue
		if not game.get("replay_steps") is Array or game.replay_steps.is_empty(): continue
		games.append(game)
		picker.add_item("Game %d · %s" % [int(game.seed), "vs random" if game.get("mode") in ["full-training-random", "full-benchmark"] else "vs heuristic"])

## Starts from the same catalogue and allowances as the recorded game.
func _select_game(index: int) -> void:
	picker.select(index)
	var game := games[index]
	steps = game.replay_steps
	frames.clear()
	position_index = 0
	failure = ""
	if harness.start(CardCatalogue.starter_army(), int(game.action_allowance), int(game.deployment_allowance)):
		frames.append(_capture(""))
	else:
		failure = "Could not initialize this game."
	_update_display()

## Advances through the authority once per new choice. Backward and cached
## forward steps only display saved frames, leaving the replay cursor intact.
func _step(direction: int) -> void:
	if frames.is_empty(): return
	var destination := position_index + direction
	if destination < 0 or destination > steps.size(): return
	if destination == frames.size():
		var entry: Variant = steps[position_index]
		if not entry is Dictionary or not entry.get("option") is Dictionary:
			failure = "Invalid decision at step %d." % destination
		else:
			var unit_id := int(entry.option.get("unit", -1))
			var unit := Match.get_unit(unit_id) if unit_id >= 0 else null
			var description := "P%d · %s" % [int(entry.player), str(entry.option.kind).capitalize()]
			if unit != null: description += " · " + unit.name
			if harness.submit(int(entry.player), entry.option):
				harness.decision()
				frames.append(_capture(description))
			else:
				failure = "Replay diverged at step %d. The game may use different rules." % destination
	if destination < frames.size(): position_index = destination
	_update_display()

## Copies the visible position so stepping backwards requires no rule replay.
func _capture(description: String) -> Dictionary:
	var units: Array[Dictionary] = []
	for unit: UnitInfo in Match.army:
		if unit.t_state != Enum.t_state.DEPLOYED: continue
		units.append({"hex": unit.ihx, "owner": unit.player, "name": unit.name, "life": unit.actual_life,
			"stun": unit._counter_value(UnitInfo.STUN_COUNTER), "sprite": BoardCharacter.replay_texture(unit)})
	return {"units": units, "turn": Match.turn_number, "player": Match.active_player,
		"winner": Match.winner, "description": description}

## Keeps the arrows, step counter and static board in sync with the chosen frame.
func _update_display() -> void:
	previous.disabled = position_index == 0
	next.disabled = frames.is_empty() or position_index >= steps.size() \
		or (not failure.is_empty() and position_index == frames.size() - 1)
	if frames.is_empty():
		status.text = "No recorded games" if failure.is_empty() else failure
		detail.text = "Open a training JSONL file that contains recorded moves."
	else:
		var frame := frames[position_index]
		status.text = "Step %d / %d   ·   Turn %d   ·   Player %d" % [
			position_index, steps.size(), int(frame.turn) + 1, int(frame.player)]
		var lines: PackedStringArray = []
		for unit in frame.units:
			lines.append("%d · P%d %s · %d life · %d Stun" % [
				int(unit.hex), int(unit.owner), unit.name, int(unit.life), int(unit.stun)])
		var outcome := ""
		if position_index == steps.size():
			outcome = "Player %d wins." % int(frame.winner) if frame.winner != 0 else "Decision cap reached."
		detail.text = "\n".join([failure if not failure.is_empty() else frame.description, outcome, "   ".join(lines)])
	field.queue_redraw()

## Draws the normal terrain and idle unit sprites using the live board's
## axial spacing and terrain calibration. Shared hexes retain two sprites.
func _draw_position() -> void:
	if frames.is_empty(): return
	var bounds := Rect2()
	var first := true
	for tile: HexInfo in Match.map:
		var point := GuerraBoard.world_position(tile.coordinate)
		var cell := Rect2(point - GuerraBoard.HEX_SIZE * 0.5, GuerraBoard.HEX_SIZE)
		bounds = cell if first else bounds.merge(cell)
		first = false
	if first: return
	var zoom := minf(field.size.x / bounds.size.x, field.size.y / bounds.size.y)
	var origin := field.size * 0.5 - bounds.get_center() * zoom
	field.draw_texture_rect(TERRAIN, Rect2(origin - GuerraBoard.TERRAIN_ANCHOR * GuerraBoard.TERRAIN_SCALE * zoom,
		TERRAIN.get_size() * GuerraBoard.TERRAIN_SCALE * zoom), false)
	var units: Array = frames[position_index].units.duplicate()
	units.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return GuerraBoard.world_position(Match.get_hex(a.hex).coordinate).y < GuerraBoard.world_position(Match.get_hex(b.hex).coordinate).y)
	for unit in units:
		var sprite: Texture2D = unit.sprite
		if sprite == null: continue
		var tile := Match.get_hex(unit.hex)
		var center := GuerraBoard.world_position(tile.coordinate) + Vector2(0, -18)
		if units.any(func(other: Dictionary) -> bool: return other.hex == unit.hex and other.owner != unit.owner):
			center.x += -32.0 if unit.owner == 1 else 32.0
		var sprite_size := sprite.get_size() * 2.0 * zoom
		field.draw_texture_rect(sprite, Rect2(origin + center * zoom - sprite_size * 0.5, sprite_size), false)
