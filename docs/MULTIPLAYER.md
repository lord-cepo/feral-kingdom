# Multiplayer client

The deployed relay is `wss://guerra-relay.feral-kingdom.workers.dev/v1/socket`.
Godot uses ordinary JSON `WebSocketPeer` text frames with verified TLS. The
server stores lobby/session metadata and forwards messages; the existing host
client runs the authoritative rules. The guest shares that engine to reproduce
confirmed actions and present choices/animations. There is no second server
implementation of gameplay rules.

## Playing

1. Both players use the same exported build. Build and save an army containing
   distinct cards and exactly one hero in **Build**.
2. The host chooses **Host**, enters a name, chooses **8 / 12 / 16 units** and
   **8 / 10 / 12 deployments**, then chooses **Create game**.
3. The other player chooses **Find** and joins the listed game. Find refreshes
   compatible waiting games every five seconds; Refresh games updates manually.
4. Each player selects a saved army matching the room size and chooses **Ready**.
   The host chooses **Start game** after both are ready and connected.
5. Each controls their own units and their own triggered choices. Each player
   acknowledges a trigger using Space/the blink once; one client cannot supply
   both identities. Save is disabled online; Leave closes room membership.

Initial deployments are the chosen pool, not an automatically placed army. The
hero still deploys first under the normal rules. The current game uses its
existing one action per turn. Host and guest seats remain Player 1 and Player 2.

Use **Reconnect** after a connection loss. The relay reserves the seat for two
minutes. On application restart, choose Host or Find to reconnect with the saved
private token. The host must return with its saved checkpoint; there is no host
migration. Two local instances need separate Godot user-data directories so they
do not share a reconnect token. The relay cannot prevent a modified host cheating.

## Caller map

| Entry | Calls / responsibility |
| --- | --- |
| `ArmyMenu._navigate` | Creates `network_lobby.gd` once; switches Host/Find/Build with fades. |
| `NetworkLobby.setup/show_mode` | Nickname, room format, saved decks, room list, Ready, Start, Leave and reconnect. |
| `NetworkSession.connect_relay/_process/_receive` | TLS, compatibility hello, private token, room updates, heartbeat, receipt-paced frames and reconnect. |
| `LocalMatchController.start_match` | Builds the selected deterministic decks, starts existing Match with room deployment allowance, then calls `attach_game`. Never loads the offline save online. |
| `Match.deploy`, `RulesRunner.submit` | Route online UI actions as stable unit/hex/effect-slot intents; confirmed calls use their existing legality/payment paths. |
| `EffectExecution.confirm/cancel`, `PhraseExecution.choose/choose_amount/confirm/cancel` | Route player choices before any mutation. Definitions and selector logic remain unchanged. |
| `Board.acknowledge_trigger_for_player` | Submits only local seat identity; host validates authenticated relay seat and current gate epoch. |
| `NetworkSession._authorize/_execute` | Checks wire shape, sender ownership, revision/context/gate, then calls the existing engine with routing bypassed only during accepted application. |
| `NetworkSession._signature` | Stable turn/phase/execution/choice signature; guest waits for its finite animations to reach the host's pre-command stage. |
| `NetworkSession.attach_game/_send_bootstrap` | Restores a settled Action snapshot plus ordered accepted choices after it, including pending costs/targets/acknowledgements. |
| Board presentation hooks | Fast replay skips historical effects; the remaining unacknowledged gate gets a fresh cue when replay finishes. Ordinary play retains its animation waits. |

Example UI intent: `{"kind":"deploy","unit":7,"hex":3}`.
The adapter adds the current revision/context and a request ID; the guest sends
it over the `command` channel. The host obtains sender `2` from the relay
envelope, validates ownership and executes `Match.deploy(7, 3)` through the same
rules as local play. Only an accepted entry advances the game revision. The
guest queues that host entry, waits for its matching stage, then reproduces it.
Costs are paid only by the existing engine, once per accepted command.

The relay sequence acknowledges transport acceptance; it is separate from the
game revision. A receipt never means that a choice executed. Host confirmations
use the `state` channel, reconnect bootstrap uses `snapshot`, and the guest may
request `sync_request`. Large snapshots are chunked below the relay frame limit;
sends are paced below its sustained rate limit. Queued payloads are copied so
checkpoint cleanup cannot rewrite an earlier queued bootstrap.

`user://network_session.json` contains the reconnect token, build hash and host
checkpoint/tail. Keep it private. It is separate from `armies.json` and the
offline snapshot. The relay stores neither the checkpoint nor accepted history.
If a session expired, the client returns to the lobby and starts a fresh session.

## Building and verification

Run `python tools/generate_network_fingerprint.py` before exporting clients after
changing rules, map, roster or the replication adapter. Ship the generated
`scripts/network/network_build.gd` with both clients. Discovery and reconnect
require identical protocol version, game version and source fingerprint. Changes
to presentation input hooks also affect that fingerprint.

Compile-only check (does not connect sockets or execute test assertions):

```powershell
godot --headless --path . res://tools/check_network_build.tscn
```

Focused offline assertions are in `tests/network_session_test.tscn`: reference
encoding, malformed payloads, deck ownership/size/hero/uniqueness, sender/revision
rejection, actual deployment payment and disconnected guest non-mutation. Run
them only when the user's request ends with `TEST`:

```powershell
godot --headless --path . res://tests/network_session_test.tscn
```

Behavioral tests and a real two-device match have **not been run** for this
implementation request. Full M8 acceptance still requires a complete match and
reconnect during a paid target choice and a two-player trigger gate, checking
identical state, stale-choice rejection and exactly-once costs. Web exports also
need their hosting origin allowed by the relay; native clients send no browser
Origin header.

### Simplified entry and room flow
Startup `_build_welcome` asks for a display name; `_play` saves it in `user://player_name.txt`, independently of versioned reconnect state. Future launches prefill the field and expose Play. Builder defaults to 12 units.
`NetworkLobby.setup` creates host settings, one deck picker and Create room. `show_mode` connects automatically; Find polls listings without a refresh button. `_create_room` and `_join_room` call `_capture_army` to validate size, distinct catalogue identities and exactly one hero before sending. `_refresh` submits the captured deck once after the room acknowledgement; the host requests start once both authenticated seats are connected and ready. Existing relay validation and host army validation still apply. Example: Play → Host → room title/settings/deck → Create room; opponent uses Play → Find → deck → room row. No manual Ready/Start steps remain.
Names and saved deck collections remain local. The relay retains the selected decks plus bounded transport/session/room metadata, never authoritative simulated game state. This change requires no relay deployment.
`NetworkLobby._leave_lobby` is connected to the host-only Leave lobby button while a room exists. It clears pending automatic deck/start state and sends the authenticated leave command; the relay closes the host room and the next lobby update restores Create room.
Online preview switching: `_can_switch_pending_action` allows the owning player to cancel an unpaid preview. `_on_effect_completed` retains the requested replacement online; controller `_process` waits for host acknowledgement, drained replay, idle rules and connected peers before submitting it normally. Example: select a unit, press 2 or click Bow to replace Walk; clicking another friendly unit uses the same gate. Paid actions remain protected.
