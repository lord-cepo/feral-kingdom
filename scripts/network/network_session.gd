## Persistent relay transport and host-authorized command replication; no second implementation of gameplay rules.
extends Node

signal lobby_changed
signal notice(text: String)
const URL := "wss://guerra-relay.feral-kingdom.workers.dev/v1/socket"
const Build = preload("res://scripts/network/network_build.gd")
const Snapshot = preload("res://scripts/runtime/match_snapshot.gd")
const CACHE := "user://network_session.json"
var socket := WebSocketPeer.new()
var authenticated := false
var room: Dictionary = {}
var rooms: Array = []
var local_player := 0
var online := false
var applying := false
var fast_replay := false
var revision := 0
var context_id := 0
var next_sequence := 1
var pending_receipt := false
var pending_command := false
var token := ""
var nickname := "Player"
var armies: Array = []
var base: Dictionary = {}
var base_revision := 0
var history: Array = []
var outbox: Array[Dictionary] = []
var incoming: Array[Dictionary] = []
var chunks: Dictionary = {}
var bootstrap: Dictionary = {}
var board: WeakRef
var last_context := ""
var last_state := WebSocketPeer.STATE_CLOSED
var heartbeat := 0.0
var stalled := 0.0
var request_counter := 0
var game_loaded := false
var restored_room := ""
var gate_id := 0
var last_gate: WeakRef
var send_delay := 0.0
var handoff_pending := false

## Restore only private reconnect/session and host checkpoint data; local hot-seat matches remain offline.
func _ready() -> void:
	if FileAccess.file_exists(CACHE):
		var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(CACHE))
		if saved is Dictionary and saved.get("rules_hash", "") == Build.RULES_HASH:
			token = str(saved.get("token", ""))
			nickname = str(saved.get("nickname", "Player"))
			restored_room = str(saved.get("room_id", ""))
			armies = saved.get("armies", [])
			base = saved.get("base", {})
			base_revision = int(saved.get("base_revision", 0))
			history = saved.get("history", [])
			revision = int(saved.get("revision", base_revision))
			gate_id = int(saved.get("gate_id", 0))

## Host/Find connects outward over certificate-verified WSS; credentials are sent only after TLS completes.
func connect_relay(name: String) -> void:
	nickname = name.strip_edges().left(32)
	if nickname.is_empty(): nickname = "Player"
	if socket.get_ready_state() in [WebSocketPeer.STATE_OPEN, WebSocketPeer.STATE_CONNECTING]: return
	socket = WebSocketPeer.new()
	socket.inbound_buffer_size = 1048576
	socket.outbound_buffer_size = 1048576
	authenticated = false
	last_state = WebSocketPeer.STATE_CLOSED
	var error := socket.connect_to_url(URL)
	if error != OK: notice.emit("Could not connect to the relay (%s)." % error)

## Poll receipts and mirrored commands; settled Action checkpoints remain local until bootstrap or reconnect requests them.
func _process(delta: float) -> void:
	socket.poll()
	var state := socket.get_ready_state()
	if state != last_state:
		last_state = state
		if state == WebSocketPeer.STATE_OPEN:
			var hello := {"type": "hello", "protocol_version": Build.PROTOCOL_VERSION, "game_version": Build.GAME_VERSION, "rules_hash": Build.RULES_HASH, "nickname": nickname}
			if not token.is_empty(): hello.resume_token = token
			_send(hello)
		elif state == WebSocketPeer.STATE_CLOSED:
			authenticated = false
			pending_receipt = false
			pending_command = false
			outbox.clear()
			notice.emit("Disconnected. Use Reconnect to resume your seat within two minutes.")
			lobby_changed.emit()
	while socket.get_available_packet_count() > 0:
		var text := socket.get_packet().get_string_from_utf8()
		if text == "pong": continue
		var data: Variant = JSON.parse_string(text)
		if data is Dictionary: _receive(data)
	if authenticated:
		send_delay = maxf(0.0, send_delay - delta)
		heartbeat += delta
		if heartbeat >= 30.0:
			heartbeat = 0.0
			socket.send_text("ping")
		if not pending_receipt and not outbox.is_empty() and send_delay <= 0.0:
			var frame: Dictionary = outbox.pop_front()
			frame.sequence = next_sequence
			pending_receipt = true
			send_delay = 0.12
			_send(frame)
	if not online or not game_loaded: return
	if not incoming.is_empty():
		var entry: Dictionary = incoming[0]
		if int(entry.revision) <= revision:
			incoming.pop_front()
		elif _signature() == str(entry.before) and _execute(entry.intent):
			revision = int(entry.revision)
			incoming.pop_front()
			stalled = 0.0
		else:
			stalled += delta
			if stalled > 30.0:
				incoming.clear()
				stalled = 0.0
				request_sync()
		return
	if fast_replay:
		fast_replay = false
		if board != null and board.get_ref() != null:
			var waiting := Match.rules_runner.presentation_waiting
			if waiting != null and Match.rules_runner.presentation_acknowledged.size() < 2:
				Match.rules_runner.presentation_ready = false
				board.get_ref()._on_trigger_presentation_requested(waiting)
			board.get_ref().refresh_board()
			board.get_ref().restore_pending_projectiles()
	if local_player == 1 and both_connected():
		_refresh_gate()
		var signature := _signature()
		if signature != last_context:
			last_context = signature
			context_id += 1
			_send_data("state", {"op": "context", "context_id": context_id, "gate_id": gate_id, "revision": revision})
		if not Match.rules_runner.busy() and Match.phase == Match.Phase.ACTION and base_revision != revision:
			base = Snapshot._capture_state()
			base_revision = revision
			history.clear()
			_persist()


## Lobby controls use the same authenticated connection; no gameplay operation is performed here.
func lobby_command(message: Dictionary) -> void:
	if authenticated: _send(message)
	else: notice.emit("Wait for the relay connection.")

## Only relay-authenticated connected slots permit new gameplay; each disconnected side pauses command entry.
func both_connected() -> bool:
	return authenticated and room.get("players", []).size() == 2 and room.players.all(func(player: Variant) -> bool: return player is Dictionary and player.get("connected", false))

## Boundary hooks call this before local input; confirmed/replayed commands bypass routing while applying is true.
func routes_input() -> bool:
	return online and not applying

## Route one local intent with the last host context; the guest never mutates Match before host acceptance.
func request_intent(intent: Dictionary) -> bool:
	if not both_connected() or fast_replay or pending_command or not incoming.is_empty(): return false
	if _intent_owner(intent) != local_player: return false
	request_counter += 1
	intent = intent.duplicate(true)
	intent.request_id = "%d-%d" % [local_player, request_counter]
	intent.expected_revision = revision
	intent.context_id = context_id
	if intent.get("kind") == "ack": intent.gate_id = gate_id
	if local_player == 1: _authorize(intent, 1)
	else:
		pending_command = true
		_send_data("command", intent)
	return false

## The authenticated host validates identity, stage, revision and native engine legality before confirming an intent.
func _authorize(intent: Dictionary, player: int) -> void:
	if not _valid_intent(intent):
		if player == 2: _send_data("state", {"op": "rejected", "message": "Malformed command."})
		return
	_refresh_gate()
	var reason := ""
	if not both_connected(): reason = "The other player is disconnected."
	elif not game_loaded or fast_replay or not incoming.is_empty(): reason = "The host is restoring the match."
	elif intent.kind == "ack" and int(intent.get("gate_id", -1)) != gate_id: reason = "That trigger has already changed."
	elif str(intent.get("kind", "")) != "ack" and (int(intent.get("expected_revision", -1)) != revision or int(intent.get("context_id", -1)) != context_id): reason = "The choice changed; try again."
	elif player != _intent_owner(intent): reason = "This choice belongs to the other player."
	var before := _signature()
	if reason.is_empty() and not _execute(intent): reason = "That action is no longer legal."
	if not reason.is_empty():
		if player == 2: _send_data("state", {"op": "rejected", "request_id": intent.get("request_id", ""), "message": reason})
		else: notice.emit(reason)
		return
	revision += 1
	var entry := {"revision": revision, "before": before, "intent": intent}
	history.append(entry)
	_persist()
	_send_data("state", {"op": "accepted", "entry": entry})

## Check untrusted guest field types before numeric conversion or native engine calls; unknown command kinds never execute.
func _valid_intent(intent: Dictionary) -> bool:
	if not intent.get("kind") is String: return false
	var fields: Dictionary = {"deploy": ["unit", "hex"], "effect": ["unit", "slot"], "choose": [], "amount": ["amount"], "confirm_effect": [], "confirm_phrase": [], "cancel_effect": [], "cancel_phrase": [], "ack": ["player", "source", "gate_id"]}
	if not fields.has(intent.kind): return false
	for field in fields[intent.kind] + ["expected_revision", "context_id"]:
		var value: Variant = intent.get(field)
		if not _wire_integer(value): return false
	if intent.kind == "choose" and decode_ref(intent.get("ref")) == null: return false
	if intent.kind in ["confirm_effect", "confirm_phrase"] and not intent.get("accepted") is bool: return false
	return true

## JSON integers may arrive as floats; reject fractional, non-finite and oversized identities before any native integer cast.
func _wire_integer(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and float(value) == floor(float(value)) and absf(float(value)) <= 2147483647.0

## Host-local gate epochs reject delayed acknowledgements of a later trigger by the same unit; both seats may acknowledge one epoch concurrently.
func _refresh_gate() -> void:
	if local_player != 1: return
	var waiting := Match.rules_runner.presentation_waiting
	if waiting != null and (last_gate == null or last_gate.get_ref() != waiting):
		last_gate = weakref(waiting)
		gate_id += 1
		last_context = ""
		_persist()

## Choices belong to their captured effect source, actions to the active player, acknowledgements to their authenticated seat.
func _intent_owner(intent: Dictionary) -> int:
	var kind := str(intent.get("kind", ""))
	if kind == "ack": return int(intent.get("player", 0))
	if kind in ["deploy", "effect"]:
		var unit := Match.get_unit(int(intent.get("unit", -1)))
		return unit.player if unit != null and unit.player == Match.active_player else 0
	var run := Match.rules_runner.active
	return Match.owner_of(run.source) if run != null and run.source != null else 0

## Execute only an authorized or confirmed intent through the existing engine; fixed kinds never call arbitrary methods.
func _execute(intent: Dictionary) -> bool:
	applying = true
	var success := false
	var run := Match.rules_runner.active
	var phrase: PhraseExecution = run.current if run != null else null
	match str(intent.get("kind", "")):
		"deploy": success = Match.deploy(int(intent.get("unit", -1)), int(intent.get("hex", -1)))
		"effect":
			var unit := Match.get_unit(int(intent.get("unit", -1)))
			var slot := int(intent.get("slot", -1))
			if unit != null and slot >= 0 and slot < unit.effects.size(): success = Match.rules_runner.submit(unit.effects[slot], TargetRef.unit(unit.iun), true)
		"choose":
			var ref := decode_ref(intent.get("ref", {}))
			if phrase != null and ref != null and phrase.status in [PhraseExecution.Status.SUBJECT, PhraseExecution.Status.TARGET] and TargetResolver.contains(phrase.candidates, ref):
				# A consumed choice may finish FAILED after paid costs; replicate that engine transition too.
				phrase.choose(ref)
				success = true
		"amount":
			var amount := int(intent.get("amount", -1))
			if phrase != null and phrase.status == PhraseExecution.Status.AMOUNT and amount >= 1 and amount <= phrase.amount_max:
				phrase.choose_amount(amount)
				success = true
		"confirm_effect":
			if run != null and run.status == EffectExecution.Status.CONFIRMING:
				run.confirm(bool(intent.get("accepted", false)))
				success = true
		"confirm_phrase":
			if phrase != null and phrase.status == PhraseExecution.Status.CONFIRMING:
				phrase.confirm(bool(intent.get("accepted", false)))
				success = true
		"cancel_effect":
			if run != null and run.can_cancel():
				run.cancel()
				success = true
		"cancel_phrase":
			if phrase != null and (run.can_cancel() or phrase.phrase.optional):
				phrase.cancel()
				success = true
		"ack":
			var runner := Match.rules_runner
			var player := int(intent.get("player", 0))
			if runner.presentation_waiting != null and runner.presentation_ready and player in [1, 2] and player not in runner.presentation_acknowledged \
					and int(intent.get("source", -1)) == runner.presentation_waiting.source.id and board != null and board.get_ref() != null:
				board.get_ref().acknowledge_trigger_for_player(player)
				success = true
	applying = false
	return success

## Authorization and replay compare a stage digest including locally derived candidates; candidate identities never cross the wire.
func _signature() -> String:
	var runner := Match.rules_runner
	var run := runner.active
	var result := {"turn": Match.turn_number, "phase": int(Match.phase), "player": Match.active_player, "gate": -1, "acks": runner.presentation_acknowledged.duplicate()}
	if runner.presentation_waiting != null: result.gate = runner.presentation_waiting.source.id
	if run != null:
		result.source = run.source.id
		result.status = int(run.status)
		result.cost = run._cost_index
		result.consequence = run._consequence_index
		if run.current != null:
			result.phrase = int(run.current.status)
			result.verb = String(run.current.phrase.verb.name)
			result.candidates = run.current.candidates.map(encode_ref)
	return JSON.stringify(result).sha256_text()

## Encode stable reference identities, including counter/ability properties; never serialize definition objects or mutable owners/positions.
func encode_ref(ref: TargetRef) -> Dictionary:
	if ref == null: return {}
	if ref.kind == TargetRef.Kind.PROPERTY: return {"kind": int(ref.kind), "host": encode_ref(ref.host), "key": String(ref.property_key)}
	return {"kind": int(ref.kind), "id": ref.id}

## Validate wire reference shapes before passing identities to the shared TargetResolver/verb legality checks.
func decode_ref(data: Variant) -> TargetRef:
	if not data is Dictionary or not _wire_integer(data.get("kind")): return null
	if int(data.kind) != TargetRef.Kind.PROPERTY and not _wire_integer(data.get("id")): return null
	match int(data.get("kind", -1)):
		TargetRef.Kind.UNIT: return TargetRef.unit(int(data.get("id", -1)))
		TargetRef.Kind.HEX: return TargetRef.hex(int(data.get("id", -1)))
		TargetRef.Kind.PLAYER: return TargetRef.player(int(data.get("id", -1)))
		TargetRef.Kind.MATCH: return TargetRef.match_host() if int(data.id) == 0 else null
		TargetRef.Kind.PROPERTY:
			if not data.get("host") is Dictionary or not data.get("key") is String: return null
			var host: Dictionary = data.host
			if not _wire_integer(host.get("kind")) or int(host.kind) == TargetRef.Kind.PROPERTY: return null
			var ref := decode_ref(host)
			if ref != null: return TargetRef.property(ref, StringName(data.get("key", "")))
	return null

## Construct the exact selected armies in deterministic owner/deck order, requiring one hero and valid distinct card keys per owner.
func make_army(decks: Array) -> Array[UnitInfo]:
	var result: Array[UnitInfo] = []
	if decks.size() != 2: return result
	for owner in [1, 2]:
		if not decks[owner - 1] is Array: return []
		var keys: Array = decks[owner - 1]
		if keys.size() != int(room.get("settings", {}).get("army_size", 0)): return []
		var available := {}
		for unit in CardCatalogue.all_units(owner): available[unit.uuid.trim_suffix("-p%d" % owner)] = unit
		var used := {}
		var heroes := 0
		for key in keys:
			if not key is String or not available.has(key) or used.has(key): return []
			used[key] = true
			var unit: UnitInfo = available[key]
			if unit.type == Enum.type.HERO: heroes += 1
			result.append(unit)
		if heroes != 1: return []
	return result

## Game composition calls this after constructing the same armies; restore a settled base and replay only its accepted tail.
func attach_game(game_board: GuerraBoard) -> void:
	handoff_pending = false
	board = weakref(game_board)
	game_loaded = true
	Match.rules_runner.trigger_acknowledgements_enabled = true
	if not bootstrap.is_empty():
		base = bootstrap.get("base", {})
		base_revision = int(bootstrap.get("base_revision", 0))
		history = bootstrap.get("history", [])
		bootstrap.clear()
	if not base.is_empty():
		if not Snapshot._is_compatible_snapshot(base):
			game_loaded = false
			notice.emit("The host checkpoint is incompatible. Leave this room and start a new match.")
			return
		Snapshot._apply_state(base)
	game_board.restore_pending_projectiles()
	revision = base_revision
	var arrived := incoming.duplicate(true)
	incoming.assign(history)
	for entry in arrived:
		if int(entry.get("revision", -1)) > base_revision and not incoming.any(func(existing: Dictionary) -> bool: return int(existing.revision) == int(entry.revision)): incoming.append(entry)
	fast_replay = not incoming.is_empty()
	if local_player == 1 and base.is_empty():
		base = Snapshot._capture_state()
		base_revision = 0
	if local_player == 1: _send_bootstrap()
	_persist()

## Request fresh authoritative checkpoint/tail after uncertainty; relay receipts are not game confirmations.
func request_sync() -> void:
	pending_command = false
	if local_player == 2: _send_data("sync_request", {"op": "sync"})
	else: _send_bootstrap()

## Restore a guest from a host-authored settled snapshot plus pending accepted choices, without serializing live execution objects.
func _send_bootstrap() -> void:
	if not game_loaded or local_player != 1 or not both_connected(): return
	_refresh_gate()
	_send_data("snapshot", {"op": "bootstrap", "armies": armies, "base": base, "base_revision": base_revision, "history": history, "revision": revision, "context_id": context_id, "gate_id": gate_id})

## Chunk large snapshots below the relay limit; receipt pacing bounds native socket buffers and preserves frame order.
func _send_data(channel: String, payload: Dictionary) -> void:
	payload = payload.duplicate(true)
	var text := JSON.stringify(payload)
	if text.length() <= 32000:
		outbox.append({"type": "relay", "channel": channel, "payload": payload})
		return
	var identifier := str(Time.get_ticks_usec())
	var count := ceili(float(text.length()) / 32000.0)
	for index in count:
		outbox.append({"type": "relay", "channel": channel, "payload": {"op": "chunk", "id": identifier, "index": index, "count": count, "text": text.substr(index * 32000, 32000)}})

## Handle room/transport envelopes separately from opaque host-confirmed game data.
func _receive(data: Dictionary) -> void:
	match str(data.get("type", "")):
		"hello":
			authenticated = true
			token = str(data.get("resume_token", token))
			next_sequence = int(data.get("next_sequence", 1))
			if data.get("room") is Dictionary: _update_room(data.room)
			else:
				_close_room()
			_persist()
			notice.emit("Connected to the relay.")
			lobby_command({"type": "list"})
			lobby_changed.emit()
		"rooms":
			rooms = data.get("rooms", [])
			lobby_changed.emit()
		"room":
			local_player = int(data.get("player", local_player))
			next_sequence = int(data.get("next_sequence", next_sequence))
			_update_room(data.room)
			_persist()
		"guest_army":
			if data.get("army") is Array and not make_army([_host_army(), data.army]).is_empty(): notice.emit("Opponent's army is valid. Both players can ready up.")
		"started":
			_update_room(data.room)
			local_player = int(data.player)
			online = true
			if local_player == 2: notice.emit("Waiting for the host's match snapshot…")
		"armies":
			armies = data.get("armies", [])
			if make_army(armies).is_empty():
				notice.emit("The selected armies are not legal. Return to the lobby.")
				lobby_command({"type": "end"})
			else:
				base = {}
				history.clear()
				revision = 0
				base_revision = 0
				_launch_game()
		"sync_required":
			if local_player == 1:
				if game_loaded: _send_bootstrap()
				elif room.get("room_id", "") == restored_room and not armies.is_empty() and not base.is_empty():
					online = true
					_launch_game()
		"relay":
			if not data.get("payload") is Dictionary: return
			var player := int(data.get("player", 0))
			if local_player == 1 and player == 2 and data.channel == "command": _authorize(data.payload, player)
			elif local_player == 1 and player == 2 and data.channel == "sync_request": _send_bootstrap()
			elif local_player == 2 and player == 1 and data.channel in ["state", "snapshot"]: _host_data(data.payload)
		"receipt":
			next_sequence = int(data.sequence) + 1
			pending_receipt = false
		"peer_disconnected":
			notice.emit("Opponent disconnected. Waiting up to two minutes for reconnect.")
		"ended", "left":
			_close_room()
			_persist()
			lobby_changed.emit()
			notice.emit("Room closed. You can host or find another game.")
		"error":
			pending_command = false
			pending_receipt = false
			outbox.clear()
			notice.emit(str(data.get("message", data.get("code", "Relay error"))))
			if str(data.get("code", "")) == "invalid_session":
				token = ""
				_send({"type": "hello", "protocol_version": Build.PROTOCOL_VERSION, "game_version": Build.GAME_VERSION, "rules_hash": Build.RULES_HASH, "nickname": nickname})

## Store public room metadata; the separate authenticated room envelope supplies the local seat.
func _update_room(value: Dictionary) -> void:
	room = value
	if room.get("phase", "") == "playing": online = true
	lobby_changed.emit()

## Recover the host's own submitted deck for pre-start guest-deck validation.
func _host_army() -> Array:
	return armies[0] if armies.size() == 2 else []

## Only authenticated host envelopes reach this method; queued replay never accepts game state from the guest.
func _host_data(payload: Dictionary) -> void:
	match str(payload.get("op", "")):
		"chunk":
			var count := int(payload.get("count", 0))
			var index := int(payload.get("index", -1))
			if count < 1 or count > 128 or index < 0 or index >= count or str(payload.get("text", "")).length() > 32000: return
			var id := str(payload.get("id", ""))
			if not chunks.has(id):
				if chunks.size() >= 2: chunks.clear()
				chunks[id] = {}
			chunks[id][index] = payload.text
			if chunks[id].size() == count:
				var text := ""
				for part in count: text += str(chunks[id].get(part, ""))
				chunks.erase(id)
				var parsed: Variant = JSON.parse_string(text)
				if parsed is Dictionary and parsed.get("op", "") != "chunk": _host_data(parsed)
		"bootstrap":
			armies = payload.get("armies", [])
			if make_army(armies).is_empty():
				notice.emit("Host supplied an incompatible army.")
				return
			context_id = int(payload.get("context_id", 0))
			gate_id = int(payload.get("gate_id", 0))
			pending_command = false
			incoming.clear()
			bootstrap = payload
			online = true
			_launch_game()
		"accepted":
			pending_command = false
			incoming.append(payload.entry)
		"context":
			context_id = int(payload.get("context_id", context_id))
			gate_id = int(payload.get("gate_id", gate_id))
		"checkpoint":
			if int(payload.get("revision", -1)) == revision and incoming.is_empty() and not Match.rules_runner.busy() and Snapshot._is_compatible_snapshot(payload.state):
				applying = true
				Snapshot._apply_state(payload.state)
				applying = false
				if board != null and board.get_ref() != null:
					board.get_ref().refresh_board()
					board.get_ref().restore_pending_projectiles()
		"rejected":
			pending_command = false
			notice.emit(str(payload.get("message", "Choice rejected.")))

## Scene handoff is deferred so relay polling never frees an input handler on its own call stack.
func _launch_game() -> void:
	if handoff_pending: return
	handoff_pending = true
	game_loaded = false
	get_tree().change_scene_to_file.call_deferred("res://scenes/game.tscn")

## Expired sessions and explicit room closure release all match queues and return the graphical game to the lobby.
func _close_room() -> void:
	room = {}
	online = false
	game_loaded = false
	base = {}
	history.clear()
	armies.clear()
	outbox.clear()
	incoming.clear()
	chunks.clear()
	pending_command = false
	fast_replay = false
	handoff_pending = false
	local_player = 0
	if get_tree().current_scene != null and get_tree().current_scene.scene_file_path == "res://scenes/game.tscn": get_tree().change_scene_to_file.call_deferred("res://scenes/army_menu.tscn")

## Private reconnect state is kept in the user's data directory, never in the repository or public room list.
func _persist() -> void:
	var file := FileAccess.open(CACHE, FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify({"rules_hash": Build.RULES_HASH, "token": token, "nickname": nickname, "room_id": room.get("room_id", ""), "armies": armies, "base": base, "base_revision": base_revision, "history": history, "revision": revision, "gate_id": gate_id}))

## JSON sends use native WebSocketPeer text frames; relay-provided receipt sequences pace opaque gameplay traffic.
func _send(data: Dictionary) -> void:
	if socket.get_ready_state() == WebSocketPeer.STATE_OPEN: socket.send_text(JSON.stringify(data))
