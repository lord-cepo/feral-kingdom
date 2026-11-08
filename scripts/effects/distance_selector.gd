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
	var result: Array[TargetRef] = []
	var origin := Selectors.Reference.new(center).get_ref(ctx)
	if origin == null or not origin.has_hex(): return result
	var start := Match.get_hex(origin.hex_id()).coordinate
	var effective_distance := distance
	if ctx != null and ctx.subject != null and ctx.query_verb != null and ctx.subject.kind == TargetRef.Kind.UNIT:
		var actor := Match.get_unit(ctx.subject.id)
		if actor != null:
			var bonus := actor.ability_bonus(ctx.query_verb)
			effective_distance += bonus.x if ctx.query_verb.name in [&"move", &"fly"] else bonus.y
	if ctx != null and ctx.query_verb != null and ctx.subject != null \
			and ctx.subject.kind == TargetRef.Kind.UNIT:
		var unit := Match.get_unit(ctx.subject.id)
		if unit != null:
			var action_name: StringName = ctx.query_verb.name
			if action_name in [&"move", &"fly"]:
				effective_distance = unit.effective_action_values(action_name, [effective_distance])[0]
			elif action_name == &"fire":
				effective_distance = unit.effective_action_values(action_name, [0, effective_distance])[1]
			elif action_name == &"cannon":
				effective_distance = unit.effective_action_values(action_name, [0, effective_distance])[1]
	var destination: TargetRef
	var baseline := 0
	if direction != Enum.direction.FROM:
		destination = Selectors.Reference.new(reference).get_ref(ctx)
		if destination == null or not destination.has_hex(): return result
		baseline = hex_distance(start, Match.get_hex(destination.hex_id()).coordinate)
	for ref in Match.all(TargetRef.Kind.HEX):
		var coordinate := Match.get_hex(ref.id).coordinate
		var steps := hex_distance(start, coordinate)
		if (include_inside and steps > effective_distance) or (not include_inside and steps != effective_distance): continue
		if destination != null:
			var remaining := hex_distance(coordinate, Match.get_hex(destination.hex_id()).coordinate)
			if direction == Enum.direction.TOWARDS and remaining >= baseline: continue
			if direction == Enum.direction.AWAY and remaining <= baseline: continue
		result.append(ref)
	return result

static func hex_distance(from: Vector2i, to: Vector2i) -> int:
	var delta := to - from
	return maxi(maxi(abs(delta.x), abs(delta.y)), abs(delta.x + delta.y))
