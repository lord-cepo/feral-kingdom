/** Transport-only protocol. No Godot rules, card catalogue or outcome validation belongs here. */
export const PROTOCOL_VERSION = 1;
export const MAX_MESSAGE_BYTES = 262144;
export const RECONNECT_MS = 120000;
export const WAITING_MS = 1800000;
export const MATCH_MS = 86400000;

/** Validation failures cross the wire as stable codes; arbitrary exceptions never expose server details. */
export class ProtocolError extends Error {
  /** Construct a client-readable protocol error with an optional expected sequence. */
  constructor(code, message, details = {}) {
    super(message);
    this.code = code;
    this.details = details;
  }
}

/** Enforce one protocol invariant before modifying room/session state. */
export function requireThat(condition, code, message, details) {
  if (!condition) throw new ProtocolError(code, message, details);
}

/** Decode bounded JSON text only; binary frames and JSON arrays are not protocol messages. */
export function decodeMessage(value) {
  requireThat(typeof value === "string", "text_required", "Send JSON text frames.");
  requireThat(new TextEncoder().encode(value).byteLength <= MAX_MESSAGE_BYTES, "message_too_large", "Message exceeds 256 KiB.");
  let message;
  try { message = JSON.parse(value); }
  catch { throw new ProtocolError("invalid_json", "Invalid JSON."); }
  requireThat(message && typeof message === "object" && !Array.isArray(message), "invalid_message", "Expected a JSON object.");
  requireThat(typeof message.type === "string", "invalid_message", "A message type is required.");
  return message;
}

/** The client supplies an exact game build and rules fingerprint, alongside this relay protocol's version. */
export function compatibility(value) {
  requireThat(value.protocol_version === PROTOCOL_VERSION, "protocol_mismatch", "Unsupported relay protocol.");
  requireThat(typeof value.game_version === "string" && /^[A-Za-z0-9.+_-]{1,64}$/.test(value.game_version), "invalid_version", "Invalid game version.");
  requireThat(typeof value.rules_hash === "string" && /^[a-f0-9]{64}$/.test(value.rules_hash), "invalid_rules_hash", "Expected a lowercase SHA-256 rules fingerprint.");
  return { protocol_version: PROTOCOL_VERSION, game_version: value.game_version, rules_hash: value.rules_hash };
}

/** Public games are compatible only when protocol, build and rule fingerprint all agree exactly. */
export function compatible(left, right) {
  return left.protocol_version === right.protocol_version && left.game_version === right.game_version && left.rules_hash === right.rules_hash;
}

/** Host-selected settings are immutable after room creation; deployments are the initial per-player pool. */
export function settings(value) {
  requireThat(value && [8, 12, 16].includes(value.army_size), "invalid_settings", "Army size must be 8, 12 or 16.");
  requireThat([8, 10, 12].includes(value.deployments), "invalid_settings", "Deployments must be 8, 10 or 12.");
  return { army_size: value.army_size, deployments: value.deployments };
}

/** Nicknames/titles are plain display strings; clients must escape them before displaying rich text. */
export function displayName(value, fallback, maximum = 32) {
  const name = typeof value === "string" ? value.trim() : fallback;
  requireThat(name.length > 0 && name.length <= maximum && !/[\u0000-\u001f\u007f]/.test(name), "invalid_name", "Invalid display name.");
  return name;
}

/** Check only army shape, size and unique stable card keys. The host validates heroes and card legality. */
export function armyKeys(value, size) {
  requireThat(Array.isArray(value) && value.length === size, "invalid_army", "Army must match the selected size.");
  requireThat(value.every(key => typeof key === "string" && /^[a-z0-9][a-z0-9-]{0,95}$/.test(key)) && new Set(value).size === size,
    "invalid_army", "Army requires distinct stable card keys.");
  return [...value];
}

/** Emit a public room view without deck lists, session credentials, IP addresses or reconnect tokens. */
export function roomView(room, sessions, connected) {
  return {
    room_id: room.id, title: room.title, settings: room.settings, compatibility: room.compatibility,
    phase: room.phase, created_at: room.createdAt,
    players: room.seats.map((id, index) => {
      const session = sessions[id];
      return session ? { player: index + 1, nickname: session.nickname, ready: session.ready, connected: connected(id) } : null;
    })
  };
}

/** Derive the allowed direction from the authenticated seat, never a client-supplied sender field. */
export function relayDirection(player, channel) {
  requireThat(player === 1 ? ["state", "snapshot"].includes(channel) : ["command", "sync_request"].includes(channel),
    "forbidden_channel", "Only the host sends state/snapshots; the guest sends commands/sync requests.");
  return player === 1 ? 2 : 1;
}

/** Generate unguessable reconnect credentials; room IDs are public discovery identifiers, not credentials. */
export function randomToken() {
  return Array.from(crypto.getRandomValues(new Uint8Array(32)), byte => byte.toString(16).padStart(2, "0")).join("");
}

/** Store only credential hashes; the plaintext token is returned to its owner once in the hello response. */
export async function tokenHash(token) {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(token));
  return Array.from(new Uint8Array(digest), byte => byte.toString(16).padStart(2, "0")).join("");
}
