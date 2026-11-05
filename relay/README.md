# Guerra lobby and message relay

Cloudflare Worker + one SQLite-backed Durable Object. The host's Godot client remains authoritative. This service contains **no game rules**: no card definitions, selector resolution, combat, costs, turns, victory calculations or graphical assets.

Implemented: public room discovery, exact build/rules compatibility, two authenticated seats, host settings, structural army checks, Ready/start, direction-restricted opaque messages, duplicate/sequence handling, private reconnect credentials, two-minute seat reservation, expiry and hibernating WebSockets. Godot Host/Find now connects through `NetworkSession`; [the client guide](../docs/MULTIPLAYER.md) covers saved armies, host authority, game handoff, reconnect and remaining verification.

## Run locally

Requires Node.js 22 or later. From this folder:

```powershell
npm.cmd ci
npm.cmd run dev
```

Wrangler normally serves `http://localhost:8787`. Health: `GET /health`. Game clients connect to `ws://localhost:8787/v1/socket` using ordinary JSON-text WebSockets. Use Godot's `WebSocketPeer` plus this application protocol, not `WebSocketMultiplayerPeer`'s incompatible high-level RPC framing.

The first local run can require downloading Cloudflare's local runtime. No Cloudflare login is needed for local development. If your machine restricts writes outside this project, set `XDG_CONFIG_HOME` to an absolute local `.wrangler/config` path and `WRANGLER_LOG_PATH` to `.wrangler/logs/dev.log`. Build logs and dependencies are ignored by Git.

## Deploy to Cloudflare

The configuration uses a SQLite Durable Object migration, suitable for the Workers Free plan. No paid plan, custom domain, external database or game-rules server is required by this configuration. Cloudflare's free usage limits still apply.

```powershell
npm.cmd exec wrangler login
npm.cmd run build
npm.cmd run deploy
```

Deployment requires your own Cloudflare account/login. `build` bundles and validates the deployment configuration without publishing it. `deploy` creates/updates the `guerra-relay` Worker and its `LOBBY` namespace; Wrangler prints the real service URL. Use the corresponding `wss://…/v1/socket` URL in clients. Do not invent a production URL before deployment.

`ALLOWED_ORIGINS` is a comma-separated browser origin allowlist. The supplied value allows only `http://localhost:5173`; add the actual origin if you later serve a browser client. Native Godot clients normally send no Origin and are supported. Public GET health/list responses allow cross-origin reads without cookies. Reconnect credentials go only in the first WebSocket JSON frame, never in URLs. Do not put Cloudflare credentials or reconnect tokens into source control.

## Room rules and limits

| Setting | Values |
| --- | --- |
| Army size | 8, 12, 16 |
| Initial deployments per player | 8, 10, 12 |
| Seats | 1 = host; 2 = guest |
| Compatibility | Exact protocol version, game version and lowercase SHA-256 rules fingerprint |
| Waiting room lifetime | 30 minutes from creation |
| Started room lifetime | 24 hours from start |
| Reconnect grace | 2 minutes after disconnect |
| Sessions outside a room | Expire after a disconnect; live sockets retain their session |
| Capacity of this small initial service | 100 rooms, 256 sockets, 512 retained sessions, 8 simultaneous sockets per address |
| JSON frame/envelope | At most 256 KiB UTF-8, including the forwarded envelope |
| Message rate per socket | Burst 60; replenishes 10 per second; excess closes the connection |

Rooms are listed only while waiting, their host is connected and their guest seat is vacant. A disconnected guest reserves its seat until the grace expires. Host departure ends the room; departure of either player during a started match ends it. The relay reports the reason, not a winner. A newly created/joined room starts each participant's outgoing sequence at 1; room messages include `player` and `next_sequence`.

Names are plain untrusted strings: escape them before putting them in Godot BBCode. Army keys are unique catalogue IDs without owner suffixes, such as `grey-squirrel-king`. The relay checks only array length/key syntax/uniqueness. The host must validate the actual cards, hero restrictions and all game commands.

## How traffic flows

1. Both clients connect and complete `hello` with matching compatibility fields.
2. Host creates a room with immutable settings. Guest discovers it with `list` or HTTP, then joins.
3. Both supply army keys and mark Ready. Guest army keys are delivered only to the host. The host checks game legality before issuing `start`.
4. The host receives both armies, initializes its existing Godot Match and sends the initial snapshot.
5. Guest sends `command` payloads; host validates them through the existing rules runner, then sends `state` or `snapshot` payloads.
6. Each side uses the relay-authenticated envelope `player`. Ignore any claimed player/source embedded in an untrusted payload. Turn legality, stale match revisions, exact choices and per-player trigger acknowledgements remain host responsibilities.
7. On disconnect, both clients pause new gameplay. Resume with the same token. The host receives `sync_required`; it sends a fresh authoritative snapshot. The guest waits for that snapshot before sending more actions.

The relay stores room/session metadata, army keys, token hashes and transport sequence counters. It does **not** store gameplay payloads, command history or match snapshots. A restarted host needs its own retained local match state to resume. A relay `receipt` means accepted/forwarded by the relay, **not** applied by the game or acknowledged by the opponent. Use a game revision/command ID in the opaque payload to deduplicate actual gameplay and recover uncertain delivery via snapshot resynchronization. The reconnect mechanism does not provide host migration or protection against a cheating host.

## Protocol and implementation map

See [PROTOCOL.md](PROTOCOL.md) for full wire examples, commands and events.

| Entry point | Responsibility |
| --- | --- |
| Worker `fetch` | Public route/method and browser-origin checks; forward to one private bound object. |
| `RelayLobby.fetch` | Compatible room list or bounded WebSocket admission. |
| Constructor / `save` | Restore/persist metadata across hibernation. |
| `webSocketMessage` → `hello` / `command` | JSON bounds, rate limit, authenticated identity and serialized room operations. |
| `relayDirection` / `command(relay)` | Host/guest channel direction, injected sender identity and per-session sequences. |
| `webSocketClose/Error` → `disconnected` | Reserve the seat and tell the other player to pause. |
| `alarm` / `scheduleAlarm` | Expire abandoned sockets/rooms/sessions without a game tick or periodic keepalive task. |
| `protocol.js` | Pure transport validation and public-room projection; no rules dependencies. |
| `test/relay.test.js` | Focused protocol/session/room/role/reconnect/hibernation regressions using an in-memory context. |

This intentionally starts with a single lobby object, keeping the code small for a low-traffic turn-based game. Capacity constants are admission limits, not a throughput guarantee. Higher traffic can later split individual rooms into objects behind the same protocol.

## Verification

`npm.cmd run check` and `npm.cmd run build` perform syntax and deployment-bundle checks. `node --check test/relay.test.js` checks the regression source without executing it. Behavioral tests are deliberately unrun because this task did not end `TEST`; when explicitly requested, run `npm.cmd test` and exercise two local WebSocket clients against Wrangler. Mock-context tests do not replace a real Cloudflare runtime check.

No production deployment or Cloudflare account change was performed while constructing this server.

## Platform references

- [Cloudflare hibernating WebSockets](https://developers.cloudflare.com/durable-objects/best-practices/websockets/) — connection attachments and automatic ping responses.
- [Durable Object limits](https://developers.cloudflare.com/durable-objects/platform/limits/) — SQLite storage and CPU limits.
- [Durable Object pricing](https://developers.cloudflare.com/durable-objects/platform/pricing/) — free quotas and billable operations. This code writes metadata on accepted state changes/messages; it forwards no artwork or animation frames.
