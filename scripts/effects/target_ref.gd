class_name TargetRef
extends RefCounted

enum Kind { UNIT, HEX, PLAYER, PROPERTY, MATCH }
var kind: Kind
var id: int
var host: TargetRef
var property_key: StringName

func _init(k: Kind = Kind.UNIT, identifier: int = -1) -> void:
	kind = k
	id = identifier

static func unit(identifier: int) -> TargetRef:
	return TargetRef.new(Kind.UNIT, identifier)

static func hex(identifier: int) -> TargetRef:
	return TargetRef.new(Kind.HEX, identifier)

static func player(identifier: int) -> TargetRef:
	return TargetRef.new(Kind.PLAYER, identifier)

static func match_host() -> TargetRef:
	return TargetRef.new(Kind.MATCH, 0)

static func property(owner: TargetRef, key: StringName) -> TargetRef:
	var result := TargetRef.new(Kind.PROPERTY)
	result.host = owner
	result.property_key = key
	return result

func same(other: TargetRef) -> bool:
	if other == null or kind != other.kind: return false
	if kind == Kind.PROPERTY:
		return host != null and host.same(other.host) and property_key == other.property_key
	return id == other.id

func identity() -> String:
	if kind == Kind.PROPERTY:
		return "p:%s:%s" % [host.identity() if host != null else "missing", property_key]
	return "%d:%020d" % [kind, id]

func valid() -> bool:
	return Match.exists(self)

func hex_id() -> int:
	return Match.position_of(self)

func has_hex() -> bool:
	return hex_id() >= 0

## Board menus label stable identities; effect properties use captions and counter properties show a readable kind plus current stored balance.
func label() -> String:
	if kind == Kind.PROPERTY:
		var option := Match.get_property(self)
		if option is EffectOption: return option.caption
		if option != null and option.increment == Enum.p_increment.COUNTER:
			return "%s · %s (%d)" % [host.label(), String(property_key).replace("_", " ").capitalize(), option.value]
	match kind:
		Kind.UNIT:
			var info: UnitInfo = Match.get_unit(id)
			return "P%d · %s (#%d)" % [info.player, info.name, id] if info != null else "Missing unit #%d" % id
		Kind.HEX: return "Tile %d" % id
		Kind.PLAYER: return "Player %d" % id
		Kind.PROPERTY: return "%s · %s" % [host.label(), property_key] if host != null else "Missing property"
	return "Match"
