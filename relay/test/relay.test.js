/** Focused transport regressions. Do not execute unless the user's request ends TEST. */
import test from "node:test";
import assert from "node:assert/strict";
import { RelayLobby } from "../src/worker.js";
import { armyKeys, compatibility, decodeMessage, relayDirection, settings } from "../src/protocol.js";

const BUILD = { protocol_version: 1, game_version: "0.1.0", rules_hash: "a".repeat(64) };
const DECK = Array.from({ length: 8 }, (_, index) => `card-${index}`);

/** In-memory Durable Object stand-in retains snapshots/alarms, without a Cloudflare account or network. */
class Storage {
  values = new Map();
  alarm = null;
  /** Return a copy, mirroring storage's serialization boundary. */
  async get(key) { return structuredClone(this.values.get(key)); }
  /** Preserve values independently of the live object's mutable state. */
  async put(key, value) { this.values.set(key, structuredClone(value)); }
  /** Read the single object alarm. */
  async getAlarm() { return this.alarm; }
  /** Capture the requested expiration boundary. */
  async setAlarm(value) { this.alarm = value; }
  /** Allow an entirely idle relay to stop scheduling work. */
  async deleteAlarm() { this.alarm = null; }
}

/** Socket double exposes only the hibernation attachment/send/close contract used by the relay. */
class Socket {
  sent = [];
  closed = false;
  /** Attach stable connection identity and a fresh rate bucket. */
  constructor() { this.info = { connectionId: crypto.randomUUID(), sessionId: null, ip: "test", helloDeadline: Date.now() + 15000, bucket: 60, bucketAt: Date.now() }; }
  /** Preserve an independent attachment, as Cloudflare does while hibernating. */
  serializeAttachment(info) { this.info = structuredClone(info); }
  /** Reads must not mutate attachments implicitly. */
  deserializeAttachment() { return structuredClone(this.info); }
  /** Capture observable output; closed sockets reject delivery. */
  send(value) { if (this.closed) throw new Error("closed"); this.sent.push(JSON.parse(value)); }
  /** The test invokes the corresponding close callback explicitly when needed. */
  close() { this.closed = true; }
  /** Mirror the runtime's open/closed readiness used by the connection index. */
  get readyState() { return this.closed ? 3 : 1; }
  /** Find the latest server envelope of a given type. */
  last(type) { return this.sent.findLast(value => value.type === type); }
}

/** Build one serialized Durable Object context; concurrent incoming messages queue instead of racing seats. */
async function fixture() {
  const ctx = {
    storage: new Storage(), sockets: [], tail: Promise.resolve(),
    /** Run a single gated task after all previous tasks, including constructor restoration. */
    blockConcurrencyWhile(callback) {
      const next = this.tail.then(callback);
      this.tail = next.catch(() => {});
      return next;
    },
    /** Match Cloudflare's open-socket inventory. */
    getWebSockets() { return this.sockets.filter(socket => !socket.closed); }
  };
  const lobby = new RelayLobby(ctx, {});
  await ctx.tail;
  return { ctx, lobby };
}

/** Connect and complete hello; callers retain the once-returned plaintext token to exercise resume. */
async function connect(fixture, extra = {}) {
  const ws = new Socket();
  fixture.ctx.sockets.push(ws);
  await send(fixture, ws, { type: "hello", ...BUILD, nickname: "Player", ...extra });
  return ws;
}

/** Exercise the real decoded/rate-limited command path, never bypassing authentication in a scenario. */
async function send(fixture, ws, message) {
  await fixture.lobby.webSocketMessage(ws, JSON.stringify(message));
}

/** Create a complete started room with two structurally valid armies; rules legality remains the host's responsibility. */
async function playing() {
  const f = await fixture();
  const host = await connect(f);
  const guest = await connect(f);
  await send(f, host, { type: "create", settings: { army_size: 8, deployments: 10 } });
  const roomId = host.last("room").room.room_id;
  await send(f, guest, { type: "join", room_id: roomId });
  await send(f, host, { type: "ready", ready: true, army: DECK });
  await send(f, guest, { type: "ready", ready: true, army: DECK });
  await send(f, host, { type: "start" });
  return { ...f, host, guest, roomId };
}

test("bounds, exact compatibility, settings and army shape reject malformed input", () => {
  assert.throws(() => settings({ army_size: 10, deployments: 8 }));
  assert.throws(() => settings({ army_size: 8, deployments: 9 }));
  for (const army_size of [8, 12, 16]) for (const deployments of [8, 10, 12]) assert.deepEqual(settings({ army_size, deployments }), { army_size, deployments });
  assert.throws(() => compatibility({ ...BUILD, protocol_version: 2 }));
  assert.throws(() => compatibility({ ...BUILD, rules_hash: "old-rules" }));
  assert.throws(() => armyKeys(Array(8).fill("same-card"), 8));
  assert.deepEqual(armyKeys(DECK, 8), DECK);
  assert.throws(() => decodeMessage("[]"));
  assert.throws(() => decodeMessage(new ArrayBuffer(2)));
  assert.throws(() => decodeMessage(JSON.stringify({ type: "relay", payload: "x".repeat(262144) })));
  assert.throws(() => relayDirection(2, "state"));
  assert.equal(relayDirection(1, "snapshot"), 2);
});

test("room discovery filters incompatible builds, conceals credentials and serializes competing joins", async () => {
  const f = await fixture();
  const host = await connect(f);
  await send(f, host, { type: "create", settings: { army_size: 8, deployments: 12 } });
  const roomId = host.last("room").room.room_id;
  assert.equal(f.lobby.listRooms(BUILD).length, 1);
  assert.equal(f.lobby.listRooms({ ...BUILD, rules_hash: "b".repeat(64) }).length, 0);
  const wrong = await connect(f, { game_version: "different" });
  await send(f, wrong, { type: "join", room_id: roomId });
  assert.equal(wrong.last("error").code, "version_mismatch");
  const guests = await Promise.all([connect(f), connect(f)]);
  await Promise.all(guests.map(ws => send(f, ws, { type: "join", room_id: roomId })));
  assert.equal(guests.filter(ws => ws.last("room")?.room.room_id === roomId).length, 1);
  assert.equal(guests.filter(ws => ws.last("error")?.code === "room_unavailable").length, 1);
  const publicText = JSON.stringify(host.last("room"));
  assert.ok(!publicText.includes("tokenHash") && !publicText.includes("resume_token") && !publicText.includes("army" + '\":['));
});

test("ready/start preserve host-only authority and keep guest army private from public room views", async () => {
  const f = await playing();
  assert.equal(f.host.last("started").player, 1);
  assert.equal(f.guest.last("started").player, 2);
  assert.deepEqual(f.host.last("armies").armies, [DECK, DECK]);
  assert.equal(f.guest.last("armies"), undefined);
  assert.equal(f.host.last("guest_army").player, 2);
  assert.equal(f.lobby.listRooms(BUILD).length, 0);
  await send(f, f.guest, { type: "end" });
  assert.equal(f.guest.last("error").code, "host_only");
  assert.equal(f.lobby.state.rooms[f.roomId].phase, "playing");
});

test("unready or malformed armies cannot start a room and guests cannot become its authority", async () => {
  const f = await fixture();
  const host = await connect(f);
  const guest = await connect(f);
  await send(f, host, { type: "create", settings: { army_size: 8, deployments: 8 } });
  const roomId = host.last("room").room.room_id;
  await send(f, guest, { type: "join", room_id: roomId });
  await send(f, host, { type: "start" });
  assert.equal(host.last("error").code, "not_ready");
  await send(f, guest, { type: "start" });
  assert.equal(guest.last("error").code, "host_only");
  await send(f, guest, { type: "ready", ready: true, army: DECK.slice(1) });
  assert.equal(guest.last("error").code, "invalid_army");
  assert.equal(f.lobby.state.sessions[guest.last("hello").session_id].ready, false);
  assert.equal(f.lobby.state.rooms[roomId].phase, "waiting");
});

test("relay injects the authenticated sender and rejects wrong direction, duplicate and out-of-order commands", async () => {
  const f = await playing();
  await send(f, f.guest, { type: "relay", channel: "state", sequence: 1, payload: {} });
  assert.equal(f.guest.last("error").code, "forbidden_channel");
  const command = { type: "relay", channel: "command", sequence: 1, player: 1, payload: { action: "choose", player: 1 } };
  await send(f, f.guest, command);
  assert.equal(f.host.last("relay").player, 2);
  assert.deepEqual(f.host.last("relay").payload, command.payload);
  const count = f.host.sent.filter(value => value.type === "relay").length;
  await send(f, f.guest, command);
  assert.equal(f.guest.last("receipt").duplicate, true);
  assert.equal(f.host.sent.filter(value => value.type === "relay").length, count);
  await send(f, f.guest, { ...command, sequence: 3 });
  assert.equal(f.guest.last("error").next_sequence, 2);
  await send(f, f.host, { type: "relay", channel: "snapshot", sequence: 1, payload: { revision: 1 } });
  assert.equal(f.guest.last("relay").player, 1);
});

test("reconnect reserves identity, replaces stale sockets and asks the host to resynchronize", async () => {
  const f = await playing();
  const token = f.guest.last("hello").resume_token;
  const sessionId = f.guest.last("hello").session_id;
  await f.lobby.webSocketClose(f.guest, 1000, "test");
  await send(f, f.host, { type: "relay", channel: "state", sequence: 1, payload: {} });
  assert.equal(f.host.last("error").code, "peer_disconnected");
  const resumed = await connect(f, { resume_token: token });
  assert.equal(resumed.last("hello").session_id, sessionId);
  assert.equal(resumed.last("hello").room.players[1].connected, true);
  assert.equal(f.host.last("sync_required").reason, "peer_reconnected");
  const replacement = await connect(f, { resume_token: token });
  assert.equal(resumed.closed, true);
  await f.lobby.webSocketClose(resumed, 1000, "old close");
  assert.equal(f.lobby.socketFor(sessionId), replacement);
  const bad = await connect(f, { resume_token: "f".repeat(64) });
  assert.equal(bad.last("error").code, "invalid_session");
});

test("disconnect expiry during play ends the room without manufacturing a winner", async () => {
  const f = await playing();
  const id = f.guest.last("hello").session_id;
  await f.lobby.webSocketClose(f.guest, 1000, "test");
  f.lobby.state.sessions[id].expiresAt = Date.now() - 1;
  await f.lobby.alarm();
  assert.equal(f.lobby.state.rooms[f.roomId], undefined);
  assert.equal(f.host.last("ended").reason, "reconnect_expired");
  assert.equal(f.host.last("ended").winner, undefined);
  assert.equal(f.lobby.state.sessions[id], undefined);
});

test("waiting guest expiry frees the room, while explicit host leave releases both seats", async () => {
  const f = await fixture();
  const host = await connect(f);
  const guest = await connect(f);
  await send(f, host, { type: "create", settings: { army_size: 8, deployments: 8 } });
  const roomId = host.last("room").room.room_id;
  await send(f, guest, { type: "join", room_id: roomId });
  await f.lobby.webSocketClose(guest, 1000, "test");
  f.lobby.state.sessions[guest.last("hello").session_id].expiresAt = Date.now() - 1;
  await f.lobby.alarm();
  assert.equal(f.lobby.state.rooms[roomId].seats[1], null);
  assert.equal(f.lobby.listRooms(BUILD).length, 1);
  await send(f, host, { type: "leave" });
  assert.equal(f.lobby.state.rooms[roomId], undefined);
  assert.equal(f.lobby.state.sessions[host.last("hello").session_id].roomId, null);
});

test("hibernation restores persisted room/session metadata and socket attachments without game simulation", async () => {
  const f = await playing();
  const restored = new RelayLobby(f.ctx, {});
  await f.ctx.tail;
  assert.equal(restored.state.rooms[f.roomId].settings.deployments, 10);
  assert.equal(restored.socketFor(f.host.last("hello").session_id), f.host);
  assert.ok(Object.values(restored.state.sessions).every(session => !Object.hasOwn(session, "resume_token")));
});
