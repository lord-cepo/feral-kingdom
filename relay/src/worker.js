import {
  PROTOCOL_VERSION, MAX_MESSAGE_BYTES, RECONNECT_MS, WAITING_MS, MATCH_MS,
  ProtocolError, requireThat, decodeMessage, compatibility, compatible, settings,
  displayName, armyKeys, roomView, relayDirection, randomToken, tokenHash
} from "./protocol.js";

const MAX_ROOMS = 100;
const MAX_SOCKETS = 256;
const MAX_SESSIONS = 512;
const HELLO_MS = 15000;
const IDLE_SESSION_MS = 600000;

/** Public HTTP entry point. Every lobby operation is serialized by one Durable Object for this initial small deployment. */
export default {
  /** Expose only documented public routes; the Durable Object binding is never addressed by user-provided object IDs. */
  async fetch(request, env) {
    const url = new URL(request.url);
    if (request.method !== "GET") return json({ error: "method_not_allowed" }, 405);
    if (url.pathname === "/health") return json({ service: "guerra-relay", protocol_version: PROTOCOL_VERSION });
    if (!["/v1/rooms", "/v1/socket"].includes(url.pathname)) return json({ error: "not_found" }, 404);
    if (url.pathname === "/v1/socket") {
      if (request.headers.get("Upgrade")?.toLowerCase() !== "websocket") return json({ error: "websocket_required" }, 426);
      const origin = request.headers.get("Origin");
      const allowed = (env.ALLOWED_ORIGINS ?? "").split(",").map(value => value.trim()).filter(Boolean);
      if (origin && !allowed.includes(origin)) return json({ error: "origin_not_allowed" }, 403);
    }
    return env.LOBBY.get(env.LOBBY.idFromName("public-v1")).fetch(request);
  }
};

/** Small JSON HTTP responses are public and uncached; no credentials ever enter query strings or request logs. */
function json(value, status = 200) {
  return new Response(JSON.stringify(value), { status, headers: { "Content-Type": "application/json", "Cache-Control": "no-store", "Access-Control-Allow-Origin": "*" } });
}

/** Hibernating two-player lobby/relay. Stores seats/settings/credential hashes, but no rules or match outcomes. */
export class RelayLobby {
  /** Restore durable metadata before any event; WebSocket attachments survive hibernation separately. */
  constructor(ctx, env) {
    this.ctx = ctx;
    this.env = env;
    this.state = { rooms: {}, sessions: {} };
    this.connections = new Map();
    ctx.blockConcurrencyWhile(async () => {
      this.state = await ctx.storage.get("state") ?? this.state;
      for (const ws of ctx.getWebSockets()) {
        const info = ws.deserializeAttachment();
        if (info?.sessionId && this.state.sessions[info.sessionId]?.connectionId === info.connectionId) this.connections.set(info.sessionId, ws);
      }
    });
  }

  /** List compatible waiting rooms or admit a bounded, initially unauthenticated WebSocket. */
  async fetch(request) {
    try {
      const url = new URL(request.url);
      if (url.pathname === "/v1/rooms") {
        const match = compatibility({ protocol_version: Number(url.searchParams.get("protocol_version")), game_version: url.searchParams.get("game_version"), rules_hash: url.searchParams.get("rules_hash") });
        return json({ rooms: this.listRooms(match) });
      }
      requireThat(url.pathname === "/v1/socket" && request.headers.get("Upgrade")?.toLowerCase() === "websocket", "not_found", "Unknown endpoint.");
      requireThat(this.ctx.getWebSockets().length < MAX_SOCKETS, "capacity", "Relay is full; try later.");
      const ip = request.headers.get("CF-Connecting-IP") ?? "local";
      requireThat(this.ctx.getWebSockets().filter(ws => ws.deserializeAttachment()?.ip === ip).length < 8, "capacity", "Connection limit reached for this address.");
      const pair = new WebSocketPair();
      const [client, server] = Object.values(pair);
      this.ctx.acceptWebSocket(server);
      server.serializeAttachment({ connectionId: crypto.randomUUID(), ip, sessionId: null, helloDeadline: Date.now() + HELLO_MS, bucket: 60, bucketAt: Date.now() });
      // This ping is answered by Cloudflare without waking or writing the Durable Object.
      this.ctx.setWebSocketAutoResponse(new WebSocketRequestResponsePair("ping", "pong"));
      await this.scheduleAlarm();
      return new Response(null, { status: 101, webSocket: client });
    } catch (error) {
      return json({ error: error instanceof ProtocolError ? error.code : "internal_error" }, error instanceof ProtocolError ? 400 : 500);
    }
  }

  /** Locate only the current authenticated connection; replaced sockets cannot act or detach a resumed player. */
  socketFor(sessionId) {
    const ws = this.connections.get(sessionId);
    return ws && ws.readyState !== 2 && ws.readyState !== 3 ? ws : undefined;
  }

  /** JSON envelopes never accept caller-controlled from/player identifiers. A failed socket send marks no outcome as confirmed. */
  send(ws, value) {
    if (!ws) return false;
    try { ws.send(JSON.stringify(value)); return true; }
    catch { return false; }
  }

  /** Public views include only matching unstarted rooms with a connected host and a genuinely vacant guest seat. */
  listRooms(match) {
    return Object.values(this.state.rooms)
      .filter(room => room.phase === "waiting" && room.expiresAt > Date.now() && !room.seats[1] && this.socketFor(room.seats[0]) && compatible(room.compatibility, match))
      .sort((left, right) => left.createdAt - right.createdAt)
      .map(room => this.view(room));
  }

  /** Bind roomView's connected predicate to this object's current hibernating sockets. */
  view(room) {
    return roomView(room, this.state.sessions, id => Boolean(this.socketFor(id)));
  }

  /** Notify both seats with the same public room state; credential/deck fields never appear here. */
  publish(room) {
    for (const id of room.seats) {
      if (!id) continue;
      this.send(this.socketFor(id), { type: "room", room: this.view(room), player: room.seats.indexOf(id) + 1, next_sequence: this.state.sessions[id].lastSequence + 1 });
    }
  }

  /** Persist small transport metadata before accepting another command; message payloads are never stored or logged. */
  async save() {
    await this.ctx.storage.put("state", this.state);
    await this.scheduleAlarm();
  }

  /** Install the nearest actual expiry, avoiding periodic keepalive alarms and continuous idle compute. */
  async scheduleAlarm() {
    const deadlines = [];
    for (const room of Object.values(this.state.rooms)) deadlines.push(room.expiresAt);
    for (const session of Object.values(this.state.sessions)) if (!this.socketFor(session.id)) deadlines.push(session.expiresAt);
    for (const ws of this.ctx.getWebSockets()) {
      const info = ws.deserializeAttachment();
      if (!info?.sessionId) deadlines.push(info.helloDeadline);
    }
    if (deadlines.length === 0) {
      await this.ctx.storage.deleteAlarm();
      return;
    }
    const next = Math.max(Date.now() + 1000, Math.min(...deadlines));
    const existing = await this.ctx.storage.getAlarm();
    if (existing === null || next < existing) await this.ctx.storage.setAlarm(next);
  }

  /** Serialize all commands including storage awaits; catch failures inside the gate so invalid clients cannot reset the object. */
  async webSocketMessage(ws, raw) {
    await this.ctx.blockConcurrencyWhile(async () => {
      try {
        const info = ws.deserializeAttachment();
        const now = Date.now();
        info.bucket = Math.min(60, info.bucket + (now - info.bucketAt) / 100);
        info.bucketAt = now;
        requireThat(info.bucket >= 1, "rate_limited", "Too many messages.");
        info.bucket -= 1;
        ws.serializeAttachment(info);
        const message = decodeMessage(raw);
        if (!info.sessionId) {
          requireThat(now <= info.helloDeadline && message.type === "hello", "hello_required", "Send hello before other messages.");
          await this.hello(ws, message);
          return;
        }
        const session = this.state.sessions[info.sessionId];
        requireThat(session?.connectionId === info.connectionId, "stale_connection", "This connection was replaced.");
        await this.command(ws, session, message);
      } catch (error) {
        const code = error instanceof ProtocolError ? error.code : "internal_error";
        this.send(ws, { type: "error", code, message: error instanceof ProtocolError ? error.message : "Relay request failed.", ...(error instanceof ProtocolError ? error.details : {}) });
        if (["rate_limited", "message_too_large", "text_required", "stale_connection"].includes(code)) ws.close(1008, code);
      }
    });
  }

  /** New players receive a random credential; reconnects prove possession and compatibility before replacing a socket. */
  async hello(ws, message) {
    const match = compatibility(message);
    let session;
    let token;
    let replaced;
    if (message.resume_token !== undefined) {
      requireThat(typeof message.resume_token === "string" && /^[a-f0-9]{64}$/.test(message.resume_token), "invalid_session", "Invalid reconnect credential.");
      const hash = await tokenHash(message.resume_token);
      session = Object.values(this.state.sessions).find(value => value.tokenHash === hash);
      requireThat(session && (this.socketFor(session.id) || session.expiresAt > Date.now()), "invalid_session", "Session expired or does not exist.");
      requireThat(compatible(session.compatibility, match), "version_mismatch", "Reconnect using the same build and rules.");
      replaced = this.socketFor(session.id);
    } else {
      requireThat(Object.keys(this.state.sessions).length < MAX_SESSIONS, "capacity", "Relay session limit reached.");
      token = randomToken();
      session = { id: crypto.randomUUID(), tokenHash: await tokenHash(token), nickname: displayName(message.nickname, "Player"), compatibility: match,
        roomId: null, ready: false, army: null, lastSequence: 0, expiresAt: Date.now() + IDLE_SESSION_MS };
      this.state.sessions[session.id] = session;
    }
    const info = ws.deserializeAttachment();
    session.connectionId = info.connectionId;
    session.expiresAt = Date.now() + IDLE_SESSION_MS;
    info.sessionId = session.id;
    ws.serializeAttachment(info);
    this.connections.set(session.id, ws);
    await this.save();
    if (replaced && replaced !== ws) replaced.close(1000, "session_resumed");
    this.send(ws, { type: "hello", protocol_version: PROTOCOL_VERSION, session_id: session.id, ...(token ? { resume_token: token } : {}), next_sequence: session.lastSequence + 1,
      room: session.roomId && this.state.rooms[session.roomId] ? this.view(this.state.rooms[session.roomId]) : null });
    const room = this.state.rooms[session.roomId];
    if (room) {
      this.publish(room);
      if (room.seats[0] === session.id && room.seats[1]) {
        this.send(ws, { type: "guest_army", player: 2, army: this.state.sessions[room.seats[1]].army });
      }
      if (room.phase === "playing" && room.seats.every(id => this.socketFor(id))) {
        this.send(this.socketFor(room.seats[0]), { type: "sync_required", reason: "peer_reconnected", player: room.seats.indexOf(session.id) + 1 });
      }
    }
  }

  /** Dispatch authenticated room commands; only the host starts/ends a room, and settings cannot drift after creation. */
  async command(ws, session, message) {
    if (message.type === "list") {
      this.send(ws, { type: "rooms", rooms: this.listRooms(session.compatibility) });
      return;
    }
    if (message.type === "create") {
      requireThat(!session.roomId, "already_in_room", "Leave your current room first.");
      requireThat(Object.keys(this.state.rooms).length < MAX_ROOMS, "capacity", "Room limit reached.");
      const room = { id: crypto.randomUUID(), title: displayName(message.title, `${session.nickname}'s game`, 64), settings: settings(message.settings),
        compatibility: session.compatibility, phase: "waiting", seats: [session.id, null], createdAt: Date.now(), expiresAt: Date.now() + WAITING_MS, relaySequence: 0 };
      session.roomId = room.id;
      session.ready = false;
      session.army = null;
      session.lastSequence = 0;
      this.state.rooms[room.id] = room;
      await this.save();
      this.publish(room);
      return;
    }
    if (message.type === "join") {
      requireThat(!session.roomId, "already_in_room", "Leave your current room first.");
      const room = this.state.rooms[message.room_id];
      requireThat(room && room.phase === "waiting" && room.expiresAt > Date.now(), "room_unavailable", "Room is unavailable.");
      requireThat(compatible(room.compatibility, session.compatibility), "version_mismatch", "Game build and rules must match.");
      requireThat(!room.seats[1] && this.socketFor(room.seats[0]), "room_unavailable", "Room is full or its host is disconnected.");
      room.seats[1] = session.id;
      session.roomId = room.id;
      session.lastSequence = 0;
      session.ready = false;
      session.army = null;
      await this.save();
      this.publish(room);
      return;
    }
    const room = this.state.rooms[session.roomId];
    requireThat(room, "not_in_room", "Join or create a room first.");
    const player = room.seats.indexOf(session.id) + 1;
    requireThat(player === 1 || player === 2, "not_in_room", "No seat belongs to this session.");
    if (message.type === "ready") {
      requireThat(room.phase === "waiting", "already_started", "The match has already started.");
      requireThat(typeof message.ready === "boolean", "invalid_ready", "ready must be a boolean.");
      session.army = message.ready ? armyKeys(message.army, room.settings.army_size) : null;
      session.ready = message.ready;
      await this.save();
      this.publish(room);
      if (player === 2) this.send(this.socketFor(room.seats[0]), { type: "guest_army", player: 2, army: session.army });
      return;
    }
    if (message.type === "start") {
      requireThat(player === 1, "host_only", "Only the host starts the match.");
      requireThat(room.phase === "waiting", "already_started", "Match already started.");
      requireThat(room.seats.every(id => id && this.socketFor(id) && this.state.sessions[id].ready), "not_ready", "Both players must be connected and ready.");
      room.phase = "playing";
      room.expiresAt = Date.now() + MATCH_MS;
      await this.save();
      for (const id of room.seats) this.send(this.socketFor(id), { type: "started", room: this.view(room), player: room.seats.indexOf(id) + 1 });
      this.send(ws, { type: "armies", armies: room.seats.map(id => this.state.sessions[id].army) });
      this.send(ws, { type: "sync_required", reason: "match_started", player: 2 });
      return;
    }
    if (message.type === "relay") {
      requireThat(room.phase === "playing", "not_started", "Start the match first.");
      const target = relayDirection(player, message.channel);
      const destination = this.socketFor(room.seats[target - 1]);
      requireThat(destination, "peer_disconnected", "Pause gameplay until the other player reconnects.");
      requireThat(Number.isSafeInteger(message.sequence) && message.sequence > 0, "invalid_sequence", "A positive sequence is required.");
      if (message.sequence === session.lastSequence) {
        this.send(ws, { type: "receipt", sequence: message.sequence, duplicate: true });
        return;
      }
      requireThat(message.sequence === session.lastSequence + 1, "sequence_mismatch", "Resynchronize the next sequence.", { next_sequence: session.lastSequence + 1 });
      requireThat(message.payload !== undefined, "invalid_payload", "An opaque JSON payload is required.");
      const forwarded = { type: "relay", room_id: room.id, player, channel: message.channel, sequence: message.sequence,
        relay_sequence: room.relaySequence + 1, payload: message.payload };
      requireThat(new TextEncoder().encode(JSON.stringify(forwarded)).byteLength <= MAX_MESSAGE_BYTES, "message_too_large", "Forwarded envelope exceeds 256 KiB.");
      requireThat(this.send(destination, forwarded), "peer_disconnected", "Peer connection failed; request a new snapshot after reconnecting.");
      session.lastSequence = message.sequence;
      room.relaySequence += 1;
      await this.save();
      this.send(ws, { type: "receipt", sequence: message.sequence, relay_sequence: room.relaySequence });
      return;
    }
    if (message.type === "leave" || message.type === "end") {
      if (message.type === "end") requireThat(player === 1, "host_only", "Only the host ends the room.");
      if (player === 1 || room.phase === "playing") this.endRoom(room, message.type === "end" ? "host_ended" : "player_left");
      else {
        room.seats[1] = null;
        session.roomId = null;
        session.ready = false;
        session.army = null;
        this.state.sessions[room.seats[0]].ready = false;
        this.publish(room);
        this.send(ws, { type: "left", room_id: room.id });
      }
      await this.save();
      return;
    }
    throw new ProtocolError("unknown_type", "Unknown message type.");
  }

  /** Remove a room and release both seats; the relay does not decide a winner or synthesize a forfeit. */
  endRoom(room, reason) {
    for (const id of room.seats) {
      const session = this.state.sessions[id];
      if (!session) continue;
      session.roomId = null;
      session.ready = false;
      session.army = null;
      this.send(this.socketFor(id), { type: "ended", room_id: room.id, reason });
    }
    delete this.state.rooms[room.id];
  }

  /** Network loss reserves the exact seat for two minutes; superseded sockets never detach the current connection. */
  async disconnected(ws) {
    const info = ws.deserializeAttachment();
    const session = this.state.sessions[info?.sessionId];
    if (!session || session.connectionId !== info.connectionId) return;
    session.connectionId = null;
    this.connections.delete(session.id);
    session.expiresAt = Date.now() + RECONNECT_MS;
    const room = this.state.rooms[session.roomId];
    if (room) {
      for (const id of room.seats) this.send(this.socketFor(id), { type: "peer_disconnected", player: room.seats.indexOf(session.id) + 1, reconnect_until: session.expiresAt });
      this.publish(room);
    }
    await this.save();
  }

  /** Acknowledge close and serialize seat reservation with incoming commands. */
  async webSocketClose(ws, code, reason) {
    try { ws.close(code === 1005 ? 1000 : code, reason); } catch { /* Already closed. */ }
    await this.ctx.blockConcurrencyWhile(() => this.disconnected(ws));
  }

  /** Transport errors follow the same reconnect policy as an ordinary disconnect. */
  async webSocketError(ws) {
    try { ws.close(1011, "transport_error"); } catch { /* Already closed. */ }
    await this.ctx.blockConcurrencyWhile(() => this.disconnected(ws));
  }

  /** Expire abandoned handshakes, disconnected sessions and old rooms without per-room ticking or game simulation. */
  async alarm() {
    await this.ctx.blockConcurrencyWhile(async () => {
      const now = Date.now();
      for (const ws of this.ctx.getWebSockets()) {
        const info = ws.deserializeAttachment();
        if (!info?.sessionId && info.helloDeadline <= now) ws.close(1008, "hello_timeout");
      }
      for (const room of Object.values(this.state.rooms)) if (room.expiresAt <= now) this.endRoom(room, "room_expired");
      for (const session of Object.values(this.state.sessions)) {
        if (this.socketFor(session.id) || session.expiresAt > now) continue;
        const room = this.state.rooms[session.roomId];
        if (room) {
          if (room.seats[0] === session.id || room.phase === "playing") this.endRoom(room, "reconnect_expired");
          else {
            room.seats[1] = null;
            this.state.sessions[room.seats[0]].ready = false;
            this.publish(room);
          }
        }
        delete this.state.sessions[session.id];
      }
      await this.save();
    });
  }
}
