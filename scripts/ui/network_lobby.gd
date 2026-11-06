## Army-menu lobby controls; NetworkSession owns the socket and survives the game scene handoff.
extends VBoxContainer

var host_mode := true
var decks: Dictionary = {}
var pending_army: Array = []
var submitted_room := ""
var start_requested := false
var create_button: Button
var leave_button: Button
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
	status = Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(status)
	controls = HBoxContainer.new()
	add_child(controls)
	title = LineEdit.new()
	title.custom_minimum_size.x = 320
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.text = "My game"
	controls.add_child(title)
	sizes = OptionButton.new()
	for value in [8, 12, 16]: sizes.add_item("%d units" % value, value)
	controls.add_child(sizes)
	deployments = OptionButton.new()
	for value in [8, 10, 12]: deployments.add_item("%d deployments" % value, value)
	controls.add_child(deployments)
	sizes.select(1)
	var selection := HBoxContainer.new()
	add_child(selection)
	army = OptionButton.new()
	army.custom_minimum_size.x = 220
	selection.add_child(army)
	create_button = Button.new()
	create_button.text = "Create room"
	create_button.pressed.connect(_create_room)
	selection.add_child(create_button)
	leave_button = Button.new()
	leave_button.text = "Leave lobby"
	leave_button.pressed.connect(_leave_lobby)
	selection.add_child(leave_button)
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
	NetworkSession.connect_relay(NetworkSession.nickname)
	if NetworkSession.authenticated: NetworkSession.lobby_command({"type": "list"})

## Host creation submits only supported format settings to the relay; army legality is checked before Ready/Start.
func _create_room() -> void:
	if not _capture_army(sizes.get_selected_id()): return
	NetworkSession.lobby_command({"type": "create", "title": title.text.strip_edges() if not title.text.strip_edges().is_empty() else "My game", "settings": {"army_size": sizes.get_selected_id(), "deployments": deployments.get_selected_id()}})

## Create/join capture and validate the selected deck before sending room commands; validation uses the requested immutable size.
func _capture_army(size: int) -> bool:
	if army.selected < 0:
		_notice("Build and save an army first.")
		return false
	var keys: Array = decks.get(army.get_item_text(army.selected), {}).get("units", [])
	var previous: Dictionary = NetworkSession.room
	NetworkSession.room = {"settings": {"army_size": size}}
	var valid := not NetworkSession.make_army([keys, keys]).is_empty()
	NetworkSession.room = previous
	if not valid:
		_notice("Choose a saved army with %d distinct units and exactly one hero." % size)
		return false
	pending_army = keys.duplicate()
	submitted_room = ""
	start_requested = false
	return true

## A Find room click validates its selected deck then joins; room acknowledgement submits it automatically.
func _join_room(id: String, size: int) -> void:
	if _capture_army(size): NetworkSession.lobby_command({"type": "join", "room_id": id})

## Host Leave lobby clears pending automatic submission/start state and asks the relay to release the room.
func _leave_lobby() -> void:
	pending_army.clear()
	submitted_room = ""
	start_requested = false
	NetworkSession.lobby_command({"type": "leave"})

## Transport notices remain visible until a new room update; no server text is interpreted as markup.
func _notice(text: String) -> void:
	status.text = text

## Room/ready updates rebuild compact listings and retain the selected saved army by name.
func _refresh() -> void:
	leave_button.visible = host_mode and not NetworkSession.room.is_empty()
	create_button.visible = host_mode and NetworkSession.room.is_empty()
	controls.visible = host_mode and NetworkSession.room.is_empty()
	var chosen := army.get_item_text(army.selected) if army.selected >= 0 else ""
	army.clear()
	for key in decks:
		army.add_item(str(key))
		if str(key) == chosen: army.select(army.item_count - 1)
	for child in room_rows.get_children(): child.queue_free()
	if not NetworkSession.room.is_empty():
		var room: Dictionary = NetworkSession.room
		var room_id := str(room.get("room_id", ""))
		if not pending_army.is_empty() and submitted_room != room_id and room.get("phase") == "waiting":
			submitted_room = room_id
			if NetworkSession.local_player == 1: NetworkSession.armies = [pending_army.duplicate(), []]
			NetworkSession.lobby_command({"type": "ready", "ready": true, "army": pending_army})
		var players: Array = room.get("players", [])
		if NetworkSession.local_player == 1 and not start_requested and room.get("phase") == "waiting" and players.size() == 2 and players.all(func(seat: Variant) -> bool: return seat is Dictionary and seat.get("ready", false) and seat.get("connected", false)):
			start_requested = true
			NetworkSession.lobby_command({"type": "start"})
		var lines := ["%s · %d units · %d deployments" % [room.get("title", "Game"), room.get("settings", {}).get("army_size", 0), room.get("settings", {}).get("deployments", 0)]]
		for seat in room.get("players", []):
			if seat is Dictionary: lines.append("%s: %s%s" % [seat.get("nickname", "Player"), "ready" if seat.get("ready", false) else "choosing army", " (disconnected)" if not seat.get("connected", false) else ""])
		status.text = "\n".join(lines)
	else:
		status.text = "Connected. Create a game or choose a compatible game below." if NetworkSession.authenticated else "Connecting to the relay…"
		if host_mode: return
		for room in NetworkSession.rooms:
			var id := str(room.get("room_id", ""))
			_button(room_rows, "%s · %s units · %s deployments · Join" % [room.get("title", "Game"), room.get("settings", {}).get("army_size", 0), room.get("settings", {}).get("deployments", 0)], _join_room.bind(id, int(room.get("settings", {}).get("army_size", 12))))


