class_name TargetResolver
extends RefCounted

class Result extends RefCounted:
	var candidates: Array[TargetRef] = []
	var error: String = ""

static func compatible(native_kind: int, expected_kind: int) -> bool:
	return native_kind == expected_kind or (native_kind == TargetRef.Kind.HEX and expected_kind == TargetRef.Kind.UNIT)

## Lets a command-availability query stop at the first acceptable native candidate.
## Only same-domain selectors that explicitly support this can skip full validation of their result list.
static func any_matching(selector: Selector, expected_kind: int, ctx: RuleContext, accept: Callable) -> Selector.Membership:
	if selector == null or not selector.validate(ctx).is_empty(): return Selector.Membership.EXCLUDED
	var native_kind := selector.output_kind(ctx)
	if native_kind == Selector.CONTEXTUAL or not compatible(native_kind, expected_kind): return Selector.Membership.EXCLUDED
	if native_kind != expected_kind: return Selector.Membership.UNKNOWN
	return selector.any_native(ctx, accept)

## Returns current matching identities without mutation. PhraseExecution supplies selected
## when revalidating one actor or target; the selector can then answer a native membership query.
static func resolve(selector: Selector, expected_kind: int, ctx: RuleContext, selected: TargetRef = null) -> Result:
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
	if selected != null:
		_resolve_selected(selector, expected_kind, native_kind, ctx, selected, result)
		return result
	for ref in selector.resolve(ctx):
		if ref == null or ref.kind != native_kind:
			result.error = "Selector returned a reference outside its declared domain."
			result.candidates.clear()
			return result
		if not ref.valid(): continue
		if native_kind == expected_kind: result.candidates.append(ref)
		else: result.candidates.append_array(Match.occupants(ref.id))
	if result.candidates.size() > 1:
		result.candidates = unique(result.candidates) if expected_kind == TargetRef.Kind.PROPERTY \
			else _unique_ids(result.candidates)
	return result

## Rechecks a selected identity in the native domain after resolve() validates the contract.
## For HEX -> UNIT, the exact unit must still occupy a matching hex. Fallback checks every
## native result for definition errors, even when the selected candidate was already found.
static func _resolve_selected(selector: Selector, expected_kind: int, native_kind: int,
		ctx: RuleContext, selected: TargetRef, result: Result) -> void:
	var native: TargetRef
	if selected.kind == expected_kind and selected.valid():
		native = selected if native_kind == expected_kind else TargetRef.hex(Match.position_of(selected))
		var membership := selector.membership(native, ctx)
		if membership != Selector.Membership.UNKNOWN:
			if membership == Selector.Membership.INCLUDED and (native == selected or native.valid()):
				result.candidates.append(selected)
			return
	var found := false
	for ref in selector.resolve(ctx):
		if ref == null or ref.kind != native_kind:
			result.error = "Selector returned a reference outside its declared domain."
			return
		if native != null and native.same(ref) and ref.valid(): found = true
	if found: result.candidates.append(selected)

static func contains(refs: Array[TargetRef], ref: TargetRef) -> bool:
	for item in refs:
		if item.same(ref): return true
	return false

## Deduplicates a validated single-domain list of non-property references by integer ID.
## resolve() uses this after adaptation so order matches the original identity sort.
static func _unique_ids(refs: Array[TargetRef]) -> Array[TargetRef]:
	var by_id: Dictionary[int, TargetRef] = {}
	for ref in refs:
		if not by_id.has(ref.id): by_id[ref.id] = ref
	var ids := by_id.keys()
	ids.sort()
	var result: Array[TargetRef] = []
	for id in ids: result.append(by_id[id])
	return result

## Selector composition and resolve() deduplicate stable identities and preserve deterministic order.
## Compute the identity once per candidate rather than comparing all pairs and rebuilding sort keys.
static func unique(refs: Array[TargetRef]) -> Array[TargetRef]:
	var by_identity := {}
	for ref in refs:
		var key := ref.identity()
		if not by_identity.has(key): by_identity[key] = ref
	var keys := by_identity.keys()
	keys.sort()
	var result: Array[TargetRef] = []
	for key in keys: result.append(by_identity[key])
	return result
