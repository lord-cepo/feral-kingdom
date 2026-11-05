class_name QuerySelector
extends Selector

var kind: int
var owner := Enum.owner.ANY
var relative_owner := Enum.ANY
var type := Enum.type.ANY
## Optional type exclusion keeps non-hero targets inclusive of both troops and temples.
var excluded_type := Enum.type.ANY
var side := Enum.side.ANY
var control := Enum.control.ANY
var region := Enum.region.ANY
var state: int = -1
var required_flag: StringName
## Name groups match literal case-insensitive substrings independently of passive flags.
var name_contains: String = ""

func _init(native_kind: int = TargetRef.Kind.UNIT) -> void:
	kind = native_kind

## Declares the native reference domain for TargetResolver validation; reads bindings only.
func output_kind(_ctx: RuleContext = null) -> int:
	return kind

## Checks this definition and domain constraints before selection/payment; returns an error or empty string.
func validate(_ctx: RuleContext = null) -> String:
	if relative_owner not in [Enum.ANY, Enum.YOU, Enum.OPP]:
		return "Relative ownership must be ANY, YOU, or OPP."
	if kind not in [TargetRef.Kind.UNIT, TargetRef.Kind.HEX, TargetRef.Kind.PLAYER]:
		return "Query requires UNIT, HEX, or PLAYER."
	if kind != TargetRef.Kind.UNIT and (type != Enum.type.ANY or excluded_type != Enum.type.ANY or state >= 0 or not name_contains.is_empty()):
		return "Unit type/state filters require a UNIT query."
	return ""

## Enumerates the native domain and filters against current ownership/location/control and optional unit passive identity.
## TargetResolver calls this; control filtering reads ControlResolver without updating caches.
func resolve(ctx: RuleContext) -> Array[TargetRef]:
	var result: Array[TargetRef] = []
	for ref in Match.all(kind):
		if matches(ref, ctx): result.append(ref)
	return result

## Queries live names for Wild/squirrel/mouse groups alongside ownership, zone and genuine passive flags; no group property is stored.
func matches(candidate: TargetRef, ctx: RuleContext) -> bool:
	if not candidate.valid(): return false
	if not name_contains.is_empty() and (candidate.kind != TargetRef.Kind.UNIT or not Match.get_unit(candidate.id).name.to_lower().contains(name_contains.to_lower())): return false
	if not required_flag.is_empty() and (candidate.kind != TargetRef.Kind.UNIT or not Match.get_unit(candidate.id).has_effective_flag(required_flag)): return false
	var actual_owner := Match.owner_of(candidate)
	if owner != Enum.owner.ANY and owner != actual_owner:
		if not (owner in [Enum.owner.P1, Enum.owner.P2] and actual_owner == Enum.owner.BOTH): return false
	if relative_owner != Enum.ANY:
		if ctx == null or ctx.source == null: return false
		var source_owner := Match.owner_of(ctx.source)
		if source_owner not in [1, 2]: return false
		var wanted := source_owner if relative_owner == Enum.YOU else 3 - source_owner
		if actual_owner != wanted: return false
	if type != Enum.type.ANY and Match.get_unit(candidate.id).type != type: return false
	if excluded_type != Enum.type.ANY and Match.get_unit(candidate.id).type == excluded_type: return false
	if state >= 0 and Match.get_unit(candidate.id).t_state != state: return false
	if side == Enum.side.ANY and control == Enum.control.ANY and region == Enum.region.ANY: return true
	if not candidate.has_hex(): return false
	var tile := Match.get_hex(candidate.hex_id())
	return (side == Enum.side.ANY or side == tile.side) and (control == Enum.control.ANY or control == ControlResolver.control_enum(ControlResolver.region_owner(tile))) and (region == Enum.region.ANY or region == tile.region)
