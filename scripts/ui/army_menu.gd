extends Control

var catalogue: Array[UnitInfo] = []
var selected: Array[String] = []
var checks: Dictionary = {}
var decks: Dictionary = {}
var army_size := 12
var army_rows: VBoxContainer
var landing_space: Control
var menu_tween: Tween
var body: VBoxContainer
var builder: VBoxContainer
var count_label: Label
var message: Label
var deck_name: LineEdit
var saved: OptionButton
var save_button: Button
var search_texts: Dictionary = {}
var search_count: Label
var info_panel: PanelContainer
var info_scroll: ScrollContainer
var inspected_key := ""
var welcome: HBoxContainer
var navigation: HBoxContainer
var player_name: LineEdit
var network_lobby: VBoxContainer
const UnitChoice = preload("res://scripts/ui/army_unit_choice.gd")

## Main-scene entry installs cursors and builds only the landing menu; catalogue/sprite loading waits for Build.
## Reads local deck records without changing Match; the fixed inspector starts hidden.
func _ready() -> void:
	preload("res://scripts/ui/game_cursors.gd").install()
	if FileAccess.file_exists("user://armies.json"):
		var data = JSON.parse_string(FileAccess.get_file_as_string("user://armies.json"))
		if data is Dictionary: decks = data
	var background := ColorRect.new()
	background.color = Color("202c29")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 28)
	add_child(margin)
	body = VBoxContainer.new()
	margin.add_child(body)
	landing_space = Control.new()
	landing_space.custom_minimum_size.y = size.y * 0.28
	body.add_child(landing_space)
	var title := Label.new()
	title.text = "Feral-Kingdom"
	title.add_theme_font_size_override("font_size", 40)
	body.add_child(title)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	navigation = HBoxContainer.new()
	body.add_child(navigation)
	navigation.alignment = BoxContainer.ALIGNMENT_CENTER
	navigation.add_theme_constant_override("separation", 20)
	for caption in ["Host", "Find", "Build"]:
		var button := Button.new()
		button.text = caption
		button.custom_minimum_size = Vector2(170, 56)
		button.pressed.connect(_navigate.bind(caption))
		navigation.add_child(button)
	message = Label.new()
	message.text = "Build and save an army from the complete catalogue."
	body.add_child(message)
	_build_info_panel()
	_build_welcome()

## Navigation buttons clear the inspector and reveal the animated builder or persistent relay lobby.
## First Build entry constructs the catalogue/editor once; subsequent visits retain choices without reloading portraits.
func _navigate(destination: String) -> void:
	if menu_tween != null: menu_tween.kill()
	menu_tween = create_tween()
	menu_tween.tween_property(landing_space, "custom_minimum_size:y", 0.0, 0.45).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	info_panel.hide()
	inspected_key = ""
	var show_builder := destination == "Build"
	if show_builder and builder == null:
		catalogue = CardCatalogue.all_units(1)
		_build_editor()
		info_panel.show()
	if builder != null: builder.visible = show_builder
	if network_lobby != null: network_lobby.visible = not show_builder
	if not show_builder:
		if network_lobby == null:
			network_lobby = preload("res://scripts/ui/network_lobby.gd").new()
			network_lobby.size_flags_vertical = Control.SIZE_EXPAND_FILL
			body.add_child(network_lobby)
			network_lobby.setup(decks)
		network_lobby.show_mode(destination == "Host", decks)
	message.text = "Choose distinct units, then name and save your army." if show_builder else "Choose your army and create or join a room."
	if show_builder:
		builder.modulate.a = 0.0
		create_tween().tween_property(builder, "modulate:a", 1.0, 0.2)

## Called once by the first Build navigation; wires size, search, sprites, inspection and local save/load controls.
func _build_editor() -> void:
	builder = VBoxContainer.new()
	builder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(builder)
	var toolbar := HBoxContainer.new()
	builder.add_child(toolbar)
	var sizes := OptionButton.new()
	for size in [8, 12, 16]: sizes.add_item("%d units" % size, size)
	sizes.select(1)
	sizes.item_selected.connect(_resize_army.bind(sizes))
	toolbar.add_child(sizes)
	count_label = Label.new()
	toolbar.add_child(count_label)
	deck_name = LineEdit.new()
	deck_name.placeholder_text = "Army name"
	deck_name.custom_minimum_size.x = 240
	toolbar.add_child(deck_name)
	save_button = Button.new()
	save_button.text = "Save deck"
	save_button.pressed.connect(_save_deck)
	toolbar.add_child(save_button)
	saved = OptionButton.new()
	saved.custom_minimum_size.x = 220
	toolbar.add_child(saved)
	var load_button := Button.new()
	load_button.text = "Load deck"
	load_button.pressed.connect(_load_deck.bind(sizes))
	toolbar.add_child(load_button)
	var search := LineEdit.new()
	search.placeholder_text = "Search names or keywords (fire, walk, bow, reset…)"
	search.clear_button_enabled = true
	search.text_changed.connect(_filter_units)
	builder.add_child(search)
	search_count = Label.new()
	builder.add_child(search_count)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var columns := HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 18)
	builder.add_child(columns)
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(scroll)
	var army_scroll := ScrollContainer.new()
	army_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(army_scroll)
	army_rows = VBoxContainer.new()
	army_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	army_scroll.add_child(army_rows)
	info_panel.get_parent().remove_child(info_panel)
	columns.add_child(info_panel)
	info_panel.custom_minimum_size.x = 340
	info_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(rows)
	for unit in catalogue:
		var key := unit.uuid.trim_suffix("-p1")
		unit.ensure_implicit_walk()
		var lines := EffectText.unit_lines(unit)
		var check := UnitChoice.new()
		check.unit = unit
		var regions := PackedStringArray()
		for region in unit.deploy_regions:
			var color := "#cbd5e1"
			if region == Enum.region.STARTING: color = "#60a5fa" if unit.deployment_enemy_side else "#ef7770"
			if region == Enum.region.INTERMEDIATE: color = "#93c5fd" if unit.deployment_enemy_side else "#fca5a5"
			regions.append("[color=%s]%s[/color]" % [color, String(Enum.region.keys()[region]).capitalize()])
		if unit.deployment_enemy_side: regions.append("[color=#60a5fa]Enemy side[/color]")
		check.info_text = "[b]%s[/b]\n%s · Life %d\nDeploy: %s\n\n%s" % [unit.name, String(Enum.type.keys()[unit.type]).capitalize(), unit.max_life, ", ".join(regions), "\n".join(lines)]
		check.mouse_entered.connect(_inspect_unit.bind(key))
		check.focus_entered.connect(_inspect_unit.bind(key))
		var portrait := BoardCharacter.portrait_path(unit)
		if not portrait.is_empty(): check.icon = load(portrait)
		check.expand_icon = true
		check.add_theme_constant_override("icon_max_width", 64)
		check.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		search_texts[key] = _searchable_rules(unit, lines)
		check.text = "%s   ·   %s   ·   Life %d" % [unit.name, String(Enum.type.keys()[unit.type]).capitalize(), unit.max_life]
		check.custom_minimum_size.y = 76
		check.toggled.connect(_toggle_unit.bind(key))
		rows.add_child(check)
		checks[key] = check
	_refresh_saved()
	_refresh_selection()
	_filter_units("")

## _ready creates one bottom-right inspector above the menu; bounded scrolling keeps long rules within the window.
## It retains the last hovered card so the user can move onto the panel and scroll its rules.
func _build_info_panel() -> void:
	info_panel = PanelContainer.new()
	info_panel.hide()
	add_child(info_panel)
	info_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	info_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	info_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	info_scroll = ScrollContainer.new()
	info_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	info_panel.add_child(info_scroll)
	resized.connect(_layout_info_panel)
	_layout_info_panel()

## Resize and hover callers leave geometry to the builder column container.
func _layout_info_panel() -> void:
	pass

## Row mouse_entered/focus_entered immediately replaces the pinned card, with no tooltip timer or appearance fade.
func _inspect_unit(key: String) -> void:
	if key == inspected_key and info_panel.visible: return
	inspected_key = key
	for child in info_scroll.get_children():
		info_scroll.remove_child(child)
		child.queue_free()
	var card: Control = checks[key].make_info_card()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_scroll.add_child(card)
	info_scroll.scroll_vertical = 0
	_layout_info_panel()
	info_panel.show()

## Editor construction indexes shared descriptions and icon action names, including implicit Walk, without resolving targets.
## BBCode is stripped after icons are named so formatting cannot hide searchable actions.
func _searchable_rules(unit: UnitInfo, lines: PackedStringArray) -> String:
	var text := unit.name + " " + String(Enum.type.keys()[unit.type]) + " " + " ".join(lines)
	for action in RuleGuide.ENTRIES:
		var path := GameIcons.action_path(StringName(action))
		if not path.is_empty(): text = text.replace(path, " " + str(action) + " ")
	for action in EffectText.ACTIONS:
		text = text.replace(EffectText.ACTIONS[action], " " + str(action) + " ")
	var tags := RegEx.new()
	tags.compile("\\[[^\\]]*\\]")
	text = tags.sub(text, " ", true).to_lower()
	return text.replace("move", "move walk")

## Search text_changed requires each space-separated term to match, ignoring case and preserving all selected identities.
## Clearing search restores every row; searching dismisses any stale inspected card and explains an empty list.
func _filter_units(query: String) -> void:
	if info_panel != null:
		info_panel.hide()
		inspected_key = ""
	var terms := query.to_lower().replace("\t", " ").split(" ", false)
	var visible_count := 0
	for key in checks:
		var matches := true
		for term in terms:
			if not String(search_texts[key]).contains(term):
				matches = false
				break
		checks[key].visible = matches
		if matches: visible_count += 1
	search_count.text = "%d / %d units shown" % [visible_count, checks.size()]
	if visible_count == 0: search_count.text += " · No matching units"

## Size selector preserves current choices; an oversized army must be reduced before saving.
func _resize_army(index: int, sizes: OptionButton) -> void:
	army_size = sizes.get_item_id(index)
	_refresh_selection()

## Catalogue toggles update editor-only stable IDs; selections never mutate live units.
func _toggle_unit(enabled: bool, key: String) -> void:
	if enabled:
		if selected.size() >= army_size:
			checks[key].set_pressed_no_signal(false)
			message.text = "Army is full. Remove a unit before adding another."
			return
		selected.append(key)
	else:
		selected.erase(key)
	_refresh_selection()

## Toggle/load/size callers rebuild comparison rows; clicking a selected row removes its catalogue identity.
func _refresh_selection() -> void:
	if army_rows != null:
		for child in army_rows.get_children():
			army_rows.remove_child(child)
			child.queue_free()
		for key in selected:
			var row := Button.new()
			row.text = checks[key].text
			row.icon = checks[key].icon
			row.expand_icon = true
			row.add_theme_constant_override("icon_max_width", 64)
			row.custom_minimum_size.y = 76
			row.mouse_entered.connect(_inspect_unit.bind(key))
			row.focus_entered.connect(_inspect_unit.bind(key))
			row.pressed.connect(checks[key].set_pressed.bind(false))
			army_rows.add_child(row)
	count_label.text = "%d / %d selected" % [selected.size(), army_size]
	save_button.disabled = selected.size() != army_size

## Save button persists a named, complete army; existing names intentionally update that deck.
func _save_deck() -> void:
	var title := deck_name.text.strip_edges()
	if title.is_empty():
		message.text = "Enter an army name first."
		return
	if selected.size() != army_size: return
	var previous := decks.duplicate(true)
	decks[title] = {"size": army_size, "units": selected.duplicate()}
	var file := FileAccess.open("user://armies.json", FileAccess.WRITE)
	if file == null:
		decks = previous
		message.text = "Could not save this army."
		return
	file.store_string(JSON.stringify(decks, "\t"))
	file.close()
	_refresh_saved()
	message.text = "Saved army: " + title

## Startup and successful saves rebuild the saved-name picker in alphabetical order.
func _refresh_saved() -> void:
	saved.clear()
	var names := decks.keys()
	names.sort()
	for title in names: saved.add_item(str(title))

## Load button restores known catalogue identities and reports obsolete or malformed local records.
func _load_deck(sizes: OptionButton) -> void:
	if saved.selected < 0: return
	var title := saved.get_item_text(saved.selected)
	var record = decks.get(title)
	if not record is Dictionary or not record.get("units") is Array or not record.get("size") in [8, 12, 16]:
		message.text = "This saved army is invalid."
		return
	army_size = int(record["size"])
	sizes.select([8, 12, 16].find(army_size))
	selected.clear()
	for key in record["units"]:
		if key is String and checks.has(key) and not selected.has(key): selected.append(key)
	for key in checks: checks[key].set_pressed_no_signal(selected.has(key))
	deck_name.text = title
	_refresh_selection()
	message.text = "Loaded army: " + title + ". Review the selection before saving."


## Startup asks for a locally remembered display name before exposing navigation; Play persists it independently of build/session caches.
func _build_welcome() -> void:
	navigation.hide()
	welcome = HBoxContainer.new()
	welcome.alignment = BoxContainer.ALIGNMENT_CENTER
	body.add_child(welcome)
	player_name = LineEdit.new()
	player_name.placeholder_text = "Your name"
	player_name.max_length = 32
	player_name.custom_minimum_size.x = 260
	if FileAccess.file_exists("user://player_name.txt"):
		player_name.text = FileAccess.get_file_as_string("user://player_name.txt").strip_edges()
	welcome.add_child(player_name)
	var play := Button.new()
	play.text = "Play"
	play.pressed.connect(_play)
	player_name.text_submitted.connect(func(_text: String) -> void: _play())
	welcome.add_child(play)
	message.text = "Welcome. Choose the name other players will see."

## Play and name-field Enter accept a nonempty name, save it locally, and reveal the main menu.
func _play() -> void:
	var chosen := player_name.text.strip_edges()
	if chosen.is_empty():
		message.text = "Enter your name to play."
		return
	NetworkSession.nickname = chosen
	var file := FileAccess.open("user://player_name.txt", FileAccess.WRITE)
	if file != null: file.store_string(chosen)
	welcome.hide()
	navigation.show()
	message.text = "Host a room, find a game, or build your army."
