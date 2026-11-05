class_name Selectors
extends RefCounted

enum Anchor { SELF, SUBJECT, EVENT_SUBJECT, EVENT_TARGET, RECIPIENT }

class Reference extends Selector:
	var anchor: Anchor
	func _init(value: Anchor = Anchor.SELF) -> void:
		anchor = value
	## Reads SELF, phrase SUBJECT, recipient, or captured event participant; unavailable bindings return null.
	func get_ref(ctx: RuleContext) -> TargetRef:
		if ctx == null or ctx.source == null: return null
		match anchor:
			Anchor.SELF: return ctx.source
			Anchor.SUBJECT: return ctx.subject
			Anchor.EVENT_SUBJECT:
				return ctx.triggering_event.subject if ctx.triggering_event != null else null
			Anchor.EVENT_TARGET:
				return ctx.triggering_event.target if ctx.triggering_event != null else null
			Anchor.RECIPIENT: return ctx.recipient
		return null
	## Declares the native reference domain for TargetResolver validation; reads bindings only.
	func output_kind(ctx: RuleContext = null) -> int:
		var ref := get_ref(ctx)
		return ref.kind if ref != null else CONTEXTUAL
	## Returns current matching identities without mutation; TargetResolver/composition supplies the query bindings.
	func resolve(ctx: RuleContext) -> Array[TargetRef]:
		var ref := get_ref(ctx)
		var result: Array[TargetRef] = []
		if ref != null and ref.valid(): result.append(ref)
		return result

class Self extends Reference:
	pass

## Historical spatial anchor for effects that follow an event's recorded hex rather than a participant's live position.
class EventHex extends Selector:
	var key: StringName
	## Beaver supplies origin_hex from the resolved movement occurrence; no activation data is stored on this selector.
	func _init(field: StringName = &"origin_hex") -> void:
		key = field
	## Declares native HEX output even when an occurrence is missing its historical position.
	func output_kind(_ctx: RuleContext = null) -> int:
		return TargetRef.Kind.HEX
	## TargetResolver reads only a captured integer hex ID; absent, malformed or removed map identities yield no candidates.
	func resolve(ctx: RuleContext) -> Array[TargetRef]:
		var result: Array[TargetRef] = []
		if ctx == null or ctx.triggering_event == null: return result
		var value: Variant = ctx.triggering_event.data.get(key)
		if typeof(value) != TYPE_INT: return result
		var ref := TargetRef.hex(int(value))
		if ref.valid(): result.append(ref)
		return result

class Subject extends Reference:
	func _init() -> void:
		super(Anchor.SUBJECT)

class Recipient extends Reference:
	## Reads the per-recipient binding used by continuous effects; ordinary executions leave it equal to SELF.
	func _init() -> void:
		super(Anchor.RECIPIENT)

class Completed extends Selector:
	## Explicit reference to a previous phase; no mutable shared TARGET slot.
	var phase: StringName
	var role: StringName
	var kind: int
	func _init(phase_name: StringName, participant_role: StringName, native_kind: int) -> void:
		phase = phase_name
		role = participant_role
		kind = native_kind
	## Declares the native reference domain for TargetResolver validation; reads bindings only.
	func output_kind(_ctx: RuleContext = null) -> int:
		return kind
	## Checks this definition and domain constraints before selection/payment; returns an error or empty string.
	func validate(_ctx: RuleContext = null) -> String:
		return "Completed role must be subject or targets." if role not in [&"subject", &"targets"] else ""
	## Returns current matching identities without mutation; TargetResolver/composition supplies the query bindings.
	func resolve(ctx: RuleContext) -> Array[TargetRef]:
		var result: Array[TargetRef] = []
		if ctx == null or ctx.source == null: return result
		var previous: Dictionary = ctx.completed_results.get(phase, {})
		if previous.is_empty() or not previous.get("success", false): return result
		if role == &"subject": result.append(previous.subject)
		else: result.append_array(previous.targets)
		return result

class Literal extends Selector:
	var refs: Array[TargetRef]
	var kind: int
	func _init(native_kind: int, values: Array[TargetRef]) -> void:
		kind = native_kind
		refs = values.duplicate()
	## Declares the native reference domain for TargetResolver validation; reads bindings only.
	func output_kind(_ctx: RuleContext = null) -> int:
		return kind
	## Checks this definition and domain constraints before selection/payment; returns an error or empty string.
	func validate(_ctx: RuleContext = null) -> String:
		for ref in refs:
			if ref == null or ref.kind != kind: return "Literal contains a reference of the wrong kind."
		return ""
	## Returns current matching identities without mutation; TargetResolver/composition supplies the query bindings.
	func resolve(_ctx: RuleContext) -> Array[TargetRef]:
		return refs.duplicate()

class Group extends Selector:
	var left: Selector
	var right: Selector
	var union: bool
	func _init(a: Selector, b: Selector, use_union: bool) -> void:
		left = a
		right = b
		union = use_union
	## Declares the native reference domain for TargetResolver validation; reads bindings only.
	func output_kind(ctx: RuleContext = null) -> int:
		return left.output_kind(ctx)
	## Checks this definition and domain constraints before selection/payment; returns an error or empty string.
	func validate(ctx: RuleContext = null) -> String:
		if left == null or right == null: return "Composition requires two selectors."
		for child in [left, right]:
			var error: String = child.validate(ctx)
			if not error.is_empty(): return error
		var a := left.output_kind(ctx)
		var b := right.output_kind(ctx)
		if a >= 0 and b >= 0 and a != b: return "Composition requires the same domain; use UnitsOn or HexOf first."
		return ""
	## Returns current matching identities without mutation; TargetResolver/composition supplies the query bindings.
	func resolve(ctx: RuleContext) -> Array[TargetRef]:
		var result: Array[TargetRef] = []
		var a := left.resolve(ctx)
		var b := right.resolve(ctx)
		if union:
			result.append_array(a)
			result.append_array(b)
		else:
			for ref in a:
				if TargetResolver.contains(b, ref): result.append(ref)
		return TargetResolver.unique(result)

class ProjectionSelector extends Selector:
	var input: Selector
	var required: int
	var produced: int
	func _init(source: Selector, from_kind: int, to_kind: int) -> void:
		input = source
		required = from_kind
		produced = to_kind
	## Declares the native reference domain for TargetResolver validation; reads bindings only.
	func output_kind(_ctx: RuleContext = null) -> int:
		return produced
	## Checks this definition and domain constraints before selection/payment; returns an error or empty string.
	func validate(ctx: RuleContext = null) -> String:
		if input == null: return "Projection requires an input selector."
		var error := input.validate(ctx)
		if not error.is_empty(): return error
		var kind := input.output_kind(ctx)
		if kind >= 0 and required >= 0 and kind != required: return "Projection input has the wrong kind."
		return ""

class UnitsOn extends ProjectionSelector:
	func _init(source: Selector) -> void:
		super(source, TargetRef.Kind.HEX, TargetRef.Kind.UNIT)
	## Returns current matching identities without mutation; TargetResolver/composition supplies the query bindings.
	func resolve(ctx: RuleContext) -> Array[TargetRef]:
		var result: Array[TargetRef] = []
		for ref in input.resolve(ctx):
			if ref.valid(): result.append_array(Match.occupants(ref.id))
		return TargetResolver.unique(result)

class BowTargets extends Selector:
	var printed_range: int
	## Stores the card's reusable printed Bow range; live bonuses remain on UnitInfo.
	func _init(value: int) -> void:
		printed_range = value
	## Declares HEX candidates; the live unit bonus only expands this Bow-specific range.
	func output_kind(_ctx: RuleContext = null) -> int:
		return TargetRef.Kind.HEX
	## Checks the printed range before an action can begin.
	func validate(_ctx: RuleContext = null) -> String:
		return "Bow range must be nonnegative." if printed_range < 0 else ""
	## Resolves cells within SELF's current printed-plus-upgraded Bow range without mutation.
	func resolve(ctx: RuleContext) -> Array[TargetRef]:
		var empty: Array[TargetRef] = []
		var source := Selectors.Reference.new(Selectors.Anchor.SELF).get_ref(ctx)
		if source == null or source.kind != TargetRef.Kind.UNIT or not source.has_hex(): return empty
		var unit := Match.get_unit(source.id)
		if unit == null: return empty
		var radius := maxi(0, printed_range + unit.effective_bow_bonus().y)
		if ctx.query_verb != null: radius += unit.ability_bonus(ctx.query_verb).y
		var origin := Match.get_hex(source.hex_id())
		if origin == null: return empty
		var result: Array[TargetRef] = []
		for ref in Match.all(TargetRef.Kind.HEX):
			var tile := Match.get_hex(ref.id)
			if tile != null and DistanceSelector.hex_distance(origin.coordinate, tile.coordinate) <= radius:
				result.append(ref)
		return result

class HexOf extends ProjectionSelector:
	func _init(source: Selector) -> void:
		super(source, TargetRef.Kind.UNIT, TargetRef.Kind.HEX)
	## Returns current matching identities without mutation; TargetResolver/composition supplies the query bindings.
	func resolve(ctx: RuleContext) -> Array[TargetRef]:
		var result: Array[TargetRef] = []
		for ref in input.resolve(ctx):
			if ref.has_hex(): result.append(TargetRef.hex(ref.hex_id()))
		return TargetResolver.unique(result)

## Explicit UNIT→COUNTER projection for Porcupine's second choice; flags, zero/negative counters and derived values are excluded.
class CountersOf extends ProjectionSelector:
	## Factories bind a host selector (usually a prior selected UNIT); duplicate property names remain subject to Match's key identity rules.
	func _init(source: Selector) -> void:
		super(source, TargetRef.Kind.UNIT, TargetRef.Kind.PROPERTY)
	## TargetResolver enumerates live positive stored counters on those exact hosts without selecting or removing any amount.
	func resolve(ctx: RuleContext) -> Array[TargetRef]:
		var result: Array[TargetRef] = []
		for host in input.resolve(ctx):
			var unit := Match.get_unit(host.id)
			if unit == null: continue
			for prop in unit.props:
				if prop.increment == Enum.p_increment.COUNTER and prop.value > 0:
					result.append(TargetRef.property(host, prop.name))
		return TargetResolver.unique(result)

## Explicit UNIT -> effect-PROPERTY projection; Copy selects one effect through the shared target resolver instead of a separate UI-only picker.
class EffectsOf extends ProjectionSelector:
	## Card authors supply a unit query or event anchor; each resolution reads its current available definitions without mutation.
	func _init(source: Selector) -> void:
		super(source, TargetRef.Kind.UNIT, TargetRef.Kind.PROPERTY)
	## Returns stable host/key references for every copyable effect of each resolved unit, including defeated event participants.
	func resolve(ctx: RuleContext) -> Array[TargetRef]:
		var result: Array[TargetRef] = []
		for ref in input.resolve(ctx):
			var unit := Match.get_unit(ref.id)
			if unit == null: continue
			for option in unit.effect_options(): result.append(TargetRef.property(ref, option.name))
		return TargetResolver.unique(result)

## Explicit unit-first Upgrade selections reject units without a numeric action, then expose only their upgradable action properties.
class UpgradeUnits extends QuerySelector:
	## Authors supply relative ownership through the ordinary QuerySelector fields.
	func _init() -> void:
		super(TargetRef.Kind.UNIT)
		state = Enum.t_state.DEPLOYED
	## The first CHOOSE_ONE step shows only units with a legal second-step ability choice.
	func resolve(ctx: RuleContext) -> Array[TargetRef]:
		var result: Array[TargetRef] = []
		for ref in super.resolve(ctx):
			if Match.get_unit(ref.id).effect_options().any(func(option: EffectOption) -> bool: return WoodlandActions.is_upgradable(option)): result.append(ref)
		return result

class UpgradeOptions extends EffectsOf:
	## The source selector normally references the preceding unit-choice result, preserving its exact identity.
	func _init(source: Selector) -> void:
		super(source)
	## PROPERTY candidates are numeric action definitions only; triggers/statics are not numeric attack upgrades.
	func resolve(ctx: RuleContext) -> Array[TargetRef]:
		return super.resolve(ctx).filter(func(ref: TargetRef) -> bool: return WoodlandActions.is_upgradable(Match.get_property(ref)))

class FleeDestinations extends Selector:
	## Flee uses the unit's current Move/Fly abilities; all hexes are proposed and the shared verb applies route/range legality.
	func output_kind(_ctx: RuleContext = null) -> int:
		return TargetRef.Kind.HEX
	## Units with multiple movement abilities may choose any destination reachable by one complete free movement use.
	func resolve(_ctx: RuleContext) -> Array[TargetRef]:
		return Match.all(TargetRef.Kind.HEX)

class PropertyOf extends ProjectionSelector:
	var key: StringName
	func _init(source: Selector, property_name: StringName) -> void:
		super(source, CONTEXTUAL, TargetRef.Kind.PROPERTY)
		key = property_name
	## Checks this definition and domain constraints before selection/payment; returns an error or empty string.
	func validate(ctx: RuleContext = null) -> String:
		var error := super.validate(ctx)
		if not error.is_empty(): return error
		if key.is_empty(): return "A property key is required."
		if input.output_kind(ctx) == TargetRef.Kind.PROPERTY: return "Properties cannot host properties."
		return ""
	## Returns current matching identities without mutation; TargetResolver/composition supplies the query bindings.
	func resolve(ctx: RuleContext) -> Array[TargetRef]:
		var result: Array[TargetRef] = []
		for ref in input.resolve(ctx):
			var property_ref := TargetRef.property(ref, key)
			if property_ref.valid(): result.append(property_ref)
		return TargetResolver.unique(result)

class EnemyOfSelf extends QuerySelector:
	func _init() -> void:
		super(TargetRef.Kind.UNIT)
		relative_owner = Enum.OPP
