class_name TargetResolver
extends RefCounted

class Result extends RefCounted:
	var candidates: Array[TargetRef] = []
	var error: String = ""

static func compatible(native_kind: int, expected_kind: int) -> bool:
	return native_kind == expected_kind or (native_kind == TargetRef.Kind.HEX and expected_kind == TargetRef.Kind.UNIT)

## Returns current matching identities without mutation; TargetResolver/composition supplies the query bindings.
static func resolve(selector: Selector, expected_kind: int, ctx: RuleContext) -> Result:
	var result := Result.new()
	if selector == null:
		result.error = "A selector is required."
		return result
	result.error = selector.validate(ctx)
	if not result.error.is_empty(): return result
	var native_kind := selector.output_kind(ctx)
	if native_kind == Selector.CONTEXTUAL: return result # An unavailable anchor.
	if not compatible(native_kind, expected_kind):
		result.error = "Cannot adapt kind %d to %d; use an explicit projection." % [native_kind, expected_kind]
		return result
	for ref in selector.resolve(ctx):
		if ref == null or ref.kind != native_kind:
			result.error = "Selector returned a reference outside its declared domain."
			result.candidates.clear()
			return result
		if not ref.valid(): continue
		if native_kind == expected_kind: result.candidates.append(ref)
		else: result.candidates.append_array(Match.occupants(ref.id))
	result.candidates = unique(result.candidates)
	return result

static func contains(refs: Array[TargetRef], ref: TargetRef) -> bool:
	for item in refs:
		if item.same(ref): return true
	return false

static func unique(refs: Array[TargetRef]) -> Array[TargetRef]:
	var result: Array[TargetRef] = []
	for ref in refs:
		if not contains(result, ref): result.append(ref)
	result.sort_custom(func(a: TargetRef, b: TargetRef) -> bool: return a.identity() < b.identity())
	return result
