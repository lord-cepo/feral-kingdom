## Army-menu lobby controls; NetworkSession owns the socket and survives the game scene handoff.
extends VBoxContainer

var host_mode := true
var decks: Dictionary = {}
var nickname: LineEdit
var title: LineEdit
var sizes: OptionButton
var deployments: OptionButton
var army: OptionButton
var status: Label
var room_rows: VBoxContainer
var controls: HBoxContainer
var refresh_time := 0.0

## ArmyMenu installs this once, supplying saved decks; navigation calls show_mode without replacing the connection.
func setup(saved_decks: Dictionary) -> void:
	decks = saved_decks
	var connection := HBoxContainer.new()
	add_child(connection)
	nickname = LineEdit.new()
	nickname.text = NetworkSession.nickname
	nickname.placeholder_text = "Your name"
	connection.add_child(nickname)
	_button(connection, "Connect / Reconnect", _connect_relay)
	_button(connection, "Leave room", func() -> void: NetworkSession.lobby_command({"type": "leave"}))
	status = Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(status)
	controls = HBoxContainer.new()
	add_child(controls)
	title = LineEdit.new()
	title.text = "My game"
	controls.add_child(title)
	sizes = OptionButton.new()
	for value in [8, 12, 16]: sizes.add_item("%d units" % value, value)
	controls.add_child(sizes)
	deployments = OptionButton.new()
	for value in [8, 10, 12]: deployments.add_item("%d deployments" % value, value)
	controls.add_child(deployments)
	_button(controls, "Create game", _create_room)
	var selection := HBoxContainer.new()
	add_child(selection)
	army = OptionButton.new()
	army.custom_minimum_size.x = 220
	selection.add_child(army)
	_button(selection, "Ready", _ready_army)
	_button(selection, "Unready", func() -> void: NetworkSession.lobby_command({"type": "ready", "ready": false}))
	_button(selection, "Start game (host)", _start_game)
	_button(selection, "Refresh games", func() -> void: NetworkSession.lobby_command({"type": "list"}))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(scroll)
	room_rows = VBoxContainer.new()
	room_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(room_rows)
	NetworkSession.lobby_changed.connect(_refresh)
	NetworkSession.notice.connect(_notice)
	_refresh()

## Host/Find navigation preserves room membership and fades the newly visible controls.
func show_mode(is_host: bool, saved_decks: Dictionary) -> void:
	host_mode = is_host
	decks = saved_decks
	show()
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.2)
	_refresh()
	_connect_relay()

## Visible Find refreshes compatible waiting rooms every five seconds; hidden menus do not poll.
func _process(delta: float) -> void:
	if not visible or host_mode or not NetworkSession.authenticated: return
	refresh_time += delta
	if refresh_time >= 5.0:
		refresh_time = 0.0
		NetworkSession.lobby_command({"type": "list"})

## Button factory keeps callbacks local to this lobby; freeing the menu releases all signal connections.
func _button(parent: Node, caption: String, callback: Callable) -> void:
	var button := Button.new()
	button.text = caption
	button.pressed.connect(callback)
	parent.add_child(button)

## Connect/reconnect reuses the private saved session token; authentication requests the first room list.
func _connect_relay() -> void:
	NetworkSession.connect_relay(nickname.text.strip_edges())
	if NetworkSession.authenticated: NetworkSession.lobby_command({"type": "list"})

## Host creation submits only supported format settings to the relay; army legality is checked before Ready/Start.
func _create_room() -> void:
	NetworkSession.lobby_command({"type": "create", "title": title.text, "settings": {"army_size": sizes.get_selected_id(), "deployments": deployments.get_selected_id()}})

## Ready requires a saved army matching the room size with distinct catalogue units and exactly one hero.
func _ready_army() -> void:
	if NetworkSession.room.is_empty() or army.selected < 0: return
	var key := army.get_item_text(army.selected)
	var keys: Array = decks.get(key, {}).get("units", [])
	if NetworkSession.make_army([keys, keys]).is_empty():
		_notice("Choose a saved army of the room's size with exactly one hero.")
		return
	if NetworkSession.local_player == 1: NetworkSession.armies = [keys.duplicate(), []]
	NetworkSession.lobby_command({"type": "ready", "ready": true, "army": keys})

## Only the host can start; the relay enforces both ready/connected and the host validates both decks again on handoff.
func _start_game() -> void:
	if NetworkSession.local_player == 1: NetworkSession.lobby_command({"type": "start"})

## Transport notices remain visible until a new room update; no server text is interpreted as markup.
func _notice(text: String) -> void:
	status.text = text

## Room/ready updates rebuild compact listings and retain the selected saved army by name.
func _refresh() -> void:
	controls.visible = host_mode and NetworkSession.room.is_empty()
	var chosen := army.get_item_text(army.selected) if army.selected >= 0 else ""
	army.clear()
	for key in decks:
		army.add_item(str(key))
		if str(key) == chosen: army.select(army.item_count - 1)
	for child in room_rows.get_children(): child.queue_free()
	if not NetworkSession.room.is_empty():
		var room: Dictionary = NetworkSession.room
		var lines := ["%s · %d units · %d deployments" % [room.get("title", "Game"), room.get("settings", {}).get("army_size", 0), room.get("settings", {}).get("deployments", 0)]]
		for seat in room.get("players", []):
			if seat is Dictionary: lines.append("%s: %s%s" % [seat.get("nickname", "Player"), "ready" if seat.get("ready", false) else "choosing army", " (disconnected)" if not seat.get("connected", false) else ""])
		status.text = "\n".join(lines)
	else:
		status.text = "Connected. Create a game or choose a compatible game below." if NetworkSession.authenticated else "Connecting to the relay…"
		for room in NetworkSession.rooms:
			var id := str(room.get("room_id", ""))
			_button(room_rows, "%s · %s units · %s deployments · Join" % [room.get("title", "Game"), room.get("settings", {}).get("army_size", 0), room.get("settings", {}).get("deployments", 0)], func() -> void: NetworkSession.lobby_command({"type": "join", "room_id": id}))
