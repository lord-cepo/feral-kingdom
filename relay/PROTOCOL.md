# Guerra relay protocol 1

Ordinary WebSocket text messages contain JSON objects with `type`. Server errors are `{ "type": "error", "code": "…", "message": "…" }`. Never log credentials or entire opaque game payloads. Literal text `ping` receives literal `pong` automatically without waking the object; these two heartbeat strings are the only non-JSON application frames.

## Connect / resume

Connect to `/v1/socket`, then send within 15 seconds:

```json
{"type":"hello","protocol_version":1,"game_version":"0.1.0","rules_hash":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","nickname":"Alice"}
```

The example hash is a placeholder, not the current game's fingerprint. The Godot integration must generate one from the agreed rule/catalogue/protocol inputs; both clients must send the exact same fingerprint and build.

Reply:

```json
{"type":"hello","protocol_version":1,"session_id":"opaque-id","resume_token":"private-64-hex-token","next_sequence":1,"room":null}
```

Keep the token privately. A resume `hello` includes `resume_token` and the same three compatibility fields. Nickname is retained on resume. The server replaces any older socket for that session, preserves its seat and sequence, and returns the current public room. It does not return the token again. A restored host is also given the retained `guest_army`. Invalid/expired tokens cannot claim seats.

## Discover, create and join

```json
{"type":"list"}
{"type":"create","title":"Alice's game","settings":{"army_size":8,"deployments":10}}
{"type":"join","room_id":"id-from-the-list"}
```

`list` replies `{ "type": "rooms", "rooms": [...] }`. HTTP alternative:

```text
GET /v1/rooms?protocol_version=1&game_version=0.1.0&rules_hash=<64-lowercase-hex-digits>
```

The room browser should request a fresh list periodically (for example every five seconds while open), not assume a subscription. No list request is required during a match. A public room has `room_id`, `title`, `settings`, `compatibility`, `phase`, `created_at` and `players` (two slots, possibly null). A player slot contains `player`, `nickname`, `ready` and `connected`, without session IDs, credentials or armies. Room members receive `{ "type": "room", "room": {...}, "player": 1, "next_sequence": 1 }` after membership/readiness/connectivity changes.

## Armies / ready / start

```json
{"type":"ready","ready":true,"army":["grey-squirrel-king","grey-squirrel-archer","grey-squirrel-crossbowman","grey-squirrel-warrior","grey-squirrel-guardian","marmot-paladin","tamia-blue-mage","beaver-warrior"]}
{"type":"ready","ready":false}
{"type":"start"}
```

The army array must contain exactly the room's army size, with distinct stable catalogue keys. These example cards demonstrate structure, not a relay-validated legal deck. Ready false removes that player's submitted army. The host receives `{ "type": "guest_army", "player": 2, "army": [...] }` when the guest changes Ready. Only the host may start; both players must be connected and Ready. The host must validate game legality first.

Both receive `{ "type": "started", "room": {...}, "player": 1 }` (guest player is 2). Host additionally receives `{ "type": "armies", "armies": [hostKeys, guestKeys] }` and `{ "type": "sync_required", "reason": "match_started", "player": 2 }`. Wait for these inputs before initializing the authoritative game and sending its initial snapshot. No deployment/action is executed by the relay.

## Relay messages

Guest → host:

```json
{"type":"relay","channel":"command","sequence":1,"payload":{"command_id":"guest-1","expected_revision":0,"kind":"choose","target":{"kind":"UNIT","id":12}}}
```

Host → guest:

```json
{"type":"relay","channel":"snapshot","sequence":1,"payload":{"revision":0,"state":{}}}
{"type":"relay","channel":"state","sequence":2,"payload":{"revision":1,"events":[]}}
```

The payload structures above are illustrative integration sketches, not already-implemented Godot command/snapshot APIs. Guest channels: `command`, `sync_request`. Host channels: `state`, `snapshot`. Trigger acknowledgements are guest commands; authenticate them as envelope player 2. Host-local actions/acknowledgements use the host's local rules runner, then publish confirmed results.

Forwarded envelopes:

```json
{"type":"relay","room_id":"room-id","player":2,"channel":"command","sequence":1,"relay_sequence":1,"payload":{}}
```

`player` is injected from the authenticated seat. `sequence` is sender-specific and increases by exactly one after acceptance. `relay_sequence` orders accepted forwarded messages across both seats. A `receipt` tells the sender the sequence was accepted. Repeating the most recently accepted sequence gets a duplicate receipt and is not forwarded twice; older/gapped sequences get `sequence_mismatch` plus `next_sequence`. Do not send several unacknowledged commands with guessed sequence numbers; send in order and handle errors/receipts.

These are transport counters, not game-state revisions. The host still rejects invalid ownership, illegal/stale commands and repeated game command IDs. The 256 KiB limit includes the forwarded envelope: leave room for metadata when sizing payloads. Larger snapshots require an integration-level chunking protocol; none is assumed here. A send/receipt cannot guarantee remote application, and uncertain delivery is recovered from the host's snapshot.

## Disconnect / leave / end

Network loss produces:

```json
{"type":"peer_disconnected","player":2,"reconnect_until":1790000000000}
```

The deadline is a real Unix timestamp in milliseconds. Stop submitting game actions, resume with the private token within two minutes, and use the returned `next_sequence`. Once both are connected again the host receives `sync_required` with `reason: "peer_reconnected"`. It must restore/send authoritative state; the relay does not keep it. A resumed host needs its own locally retained state. The guest waits for fresh synchronization.

```json
{"type":"leave"}
{"type":"end"}
```

Either seat can leave. Only host can end. Guest leave before start releases its seat and resets host Ready; host leave or either player's departure after start ends the room. Clients remain connected to the lobby and can create/join another room. `ended` contains `room_id` and `reason` (`host_ended`, `player_left`, `reconnect_expired`, `room_expired`), with no winner. Waiting rooms expire after 30 minutes, started rooms after 24 hours. The relay does not migrate authority to the guest.

## Common errors

`protocol_mismatch`, `version_mismatch`, `invalid_rules_hash`, `invalid_session`, `hello_required`, `room_unavailable`, `already_in_room`, `not_in_room`, `invalid_settings`, `invalid_army`, `host_only`, `not_ready`, `already_started`, `not_started`, `forbidden_channel`, `peer_disconnected`, `invalid_sequence`, `sequence_mismatch`, `message_too_large`, `rate_limited`, `capacity`.

Errors do not automatically consume a relay sequence. Binary/oversize frames, rate-limit violations and replaced-connection commands close the offending socket. No game costs are paid by the relay.
