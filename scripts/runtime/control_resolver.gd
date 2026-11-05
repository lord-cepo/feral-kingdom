## Calculates region ownership from current board state; it never stores bonus counters.
class_name ControlResolver
extends RefCounted

## Returns whether two tiles belong to the same geographical region.
## RegionMap identifies each region by type, home side, and local region number.
static func same_region(a: HexInfo, b: HexInfo) -> bool:
	return a != null and b != null and a.region == b.region and a.side == b.side and a.region_count == b.region_count

## Sums current life, printed control bonuses and stored control counters for one player in a region.
## Used by region_owner(); the home bonus is half a point and applies only to
## starting/intermediate regions. Bash participants count at their shared destination.
static func strength(region_hex: HexInfo, player_id: int) -> float:
	if region_hex == null or player_id not in [1, 2]: return 0.0
	var total := 0.0
	if region_hex.region != Enum.region.FRONT and int(region_hex.side) == player_id:
		total += 0.5
	for unit in Match.army:
		if unit == null or unit.player != player_id or unit.t_state != Enum.t_state.DEPLOYED:
			continue
		var unit_hex := Match.get_hex(unit.ihx)
		if same_region(region_hex, unit_hex):
			total += unit.actual_life + unit.control_bonus + unit._counter_value(UnitInfo.CONTROL_COUNTER)
	return total

## Returns player 1, player 2, or NONE when the regional strengths tie.
## Deployment checks and control selectors use this live result.
static func region_owner(region_hex: HexInfo) -> int:
	if region_hex == null: return Enum.owner.NONE
	var first := strength(region_hex, 1)
	var second := strength(region_hex, 2)
	if is_equal_approx(first, second): return Enum.owner.NONE
	return 1 if first > second else 2

## Refreshes all display tiles while calculating each distinct geographical region only once in this pass.
## Match/Board call after mutations; this local memo never survives a refresh and live legality/physical_bonus queries remain uncached.
static func refresh() -> void:
	var regions: Dictionary = {}
	for tile in Match.map:
		if tile == null: continue
		var key := Vector3i(int(tile.region), int(tile.side), tile.region_count)
		if not regions.has(key): regions[key] = control_enum(region_owner(tile))
		tile.control = regions[key]

## Returns the owner's live +1 physical contribution while the unit is deployed.
## UnitInfo.modifier calls this; it is derived and never added to stored counters.
static func physical_bonus(unit) -> int:
	if unit == null or unit.t_state != Enum.t_state.DEPLOYED: return 0
	var tile := Match.get_hex(unit.ihx)
	return 1 if tile != null and region_owner(tile) == unit.player else 0

## Converts an owning player ID to the tile display/filter enum.
static func control_enum(player_id: int) -> int:
	match player_id:
		1: return Enum.control.P1
		2: return Enum.control.P2
	return Enum.control.NONE
