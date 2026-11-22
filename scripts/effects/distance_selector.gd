class_name DistanceSelector
extends Selector

var direction := Enum.direction.FROM
var distance: int
var include_inside := false
var center: Selectors.Anchor
var reference: Selectors.Anchor

func _init(value: int = 0, anchor: Selectors.Anchor = Selectors.Anchor.SELF) -> void:
	distance = value
	center = anchor
	reference = Selectors.Anchor.SELF

static func within(radius: int, anchor: Selectors.Anchor = Selectors.Anchor.SELF) -> DistanceSelector:
	var result := DistanceSelector.new(radius, anchor)
	result.include_inside = true
	return result

## Declares the native reference domain for TargetResolver validation; reads bindings only.
func output_kind(_ctx: RuleContext = null) -> int:
	return TargetRef.Kind.HEX

## Checks this definition and domain constraints before selection/payment; returns an error or empty string.
func validate(_ctx: RuleContext = null) -> String:
	return "Distance must be nonnegative." if distance < 0 else ""

## Returns current matching hexes without mutation; phrase execution and availability previews both include live range grants.
func resolve(ctx: RuleContext) -> Array[TargetRef]:
	return _matching_hexes(ctx)

## TargetResolver calls this at commit for one selected hex (or the chosen unit's live hex).
## Uses the same current range, anchor and directional rules as the full picker.
func membership(candidate: TargetRef, ctx: RuleContext) -> Membership:
	if candidate.kind != TargetRef.Kind.HEX or Match.get_hex(candidate.id) == null:
		return Membership.EXCLUDED
	return Membership.EXCLUDED if _matching_hexes(ctx, candidate.id).is_empty() else Membership.INCLUDED

## Stops the same spatial query at the first candidate accepted by the current verb.
## RulesRunner uses this when it only needs to know whether a command can begin.
func any_native(ctx: RuleContext, accept: Callable) -> Membership:
	return Membership.EXCLUDED if _matching_hexes(ctx, -1, accept).is_empty() else Membership.INCLUDED

## Resolves live range and geometry for a picker, a chosen cell, or an existence query.
## When supplied, accept() is a read-only legality check and stops the scan on its first match.
func _matching_hexes(ctx: RuleContext, only_hex: int = -1, accept: Callable = Callable()) -> Array[TargetRef]:
	var result: Array[TargetRef] = []
	var origin := Selectors.Reference.new(center).get_ref(ctx)
	var origin_tile := Match.get_hex(origin.hex_id()) if origin != null else null
	if origin_tile == null: return result
	var start := origin_tile.coordinate
	var effective_distance := distance
	if ctx != null and ctx.subject != null and ctx.query_verb != null and ctx.subject.kind == TargetRef.Kind.UNIT:
		var actor := Match.get_unit(ctx.subject.id)
		if actor != null:
			var bonus := actor.ability_bonus(ctx.query_verb)
			var action_name: StringName = ctx.query_verb.name
			if action_name in [&"move", &"fly"]:
				effective_distance = actor.effective_action_values(action_name, [distance + bonus.x])[0]
			else:
				effective_distance += bonus.y
				if action_name in [&"fire", &"cannon"]:
					effective_distance = actor.effective_action_values(action_name, [0, effective_distance])[1]
	var directional := direction != Enum.direction.FROM
	var destination_coordinate := Vector2i.ZERO
	var baseline := 0
	if directional:
		var destination := Selectors.Reference.new(reference).get_ref(ctx)
		var destination_tile := Match.get_hex(destination.hex_id()) if destination != null else null
		if destination_tile == null: return result
		destination_coordinate = destination_tile.coordinate
		baseline = hex_distance(start, destination_coordinate)
	var first := only_hex if only_hex >= 0 else 0
	var end := only_hex + 1 if only_hex >= 0 else Match.map.size()
	var first_only := accept.is_valid()
	for hex_id in range(first, end):
		var tile := Match.map[hex_id]
		if tile == null: continue
		var coordinate := tile.coordinate
		var steps := hex_distance(start, coordinate)
		if (include_inside and steps > effective_distance) or (not include_inside and steps != effective_distance): continue
		if directional:
			var remaining := hex_distance(coordinate, destination_coordinate)
			if direction == Enum.direction.TOWARDS and remaining >= baseline: continue
			if direction == Enum.direction.AWAY and remaining <= baseline: continue
		var candidate := TargetRef.hex(hex_id)
		if first_only:
			if accept.call(candidate): return [candidate]
		else:
			result.append(candidate)
	return result

static func hex_distance(from: Vector2i, to: Vector2i) -> int:
	var delta := to - from
	return maxi(maxi(abs(delta.x), abs(delta.y)), abs(delta.x + delta.y))
