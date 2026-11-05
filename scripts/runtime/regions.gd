class_name RegionMap
extends Node

const BOARD_X := 4
const BOARD_Y := 3 

## Rebuilds the axial board and assigns every tile its type, home side, and region ID.
## Called by GuerraBoard when Match has no map; type, side, and region ID define control regions.
func _generate_hex_grid() -> void:
	Match.map.clear()
	var i: int = 0
	for x in range(-BOARD_X, BOARD_X+1):
		for y in range(-BOARD_Y, BOARD_Y+1):
			if abs(x+y) > 3 or (x==0 and y==0):
				continue
			var kind := _region_kind_for(Vector2i(x, y))
			Match.map.append(HexInfo.new(
				i, Vector2i(x, y), 
				kind[0], kind[1], kind[2]
			))
			i += 1

## Maps one coordinate to its geographical region metadata; the generator calls this per tile without changing hex IDs.
## After excluding the left starting triangle, all remaining negative-x/positive-y cells form the same six-hex intermediate region.
## Do not restrict that region to x+y <= 0: that splits its triangle into three hexes and misassigns the other three to its neighbor.
func _region_kind_for(coordinate: Vector2i) -> Array:
	var x := coordinate.x
	var y := coordinate.y
	if x + y < 0 and y > 0: return [Enum.region.STARTING, Enum.side.P1, 0]
	if x < 0 and y > 0: return [Enum.region.INTERMEDIATE, Enum.side.P1, 1]
	if x > 0 and y >= 0: return [Enum.region.INTERMEDIATE, Enum.side.P2, 1]
	if x == 0: return [Enum.region.FRONT, Enum.side.NONE, 0]
	if x > 0 and x + y > 0: return [Enum.region.STARTING, Enum.side.P2, 0]
	if x > 0 and x + y <= 0: return [Enum.region.INTERMEDIATE, Enum.side.P2, 0]
	return [Enum.region.INTERMEDIATE, Enum.side.P1, 0]

func hexes_at_distance(origin: Vector2i, distance: int) -> Array[HexInfo]:
	if distance < 0:
		return []

	return Match.map.filter(
		func(hex: HexInfo) -> bool:
			return hex_distance(origin, hex.coordinate) == distance
	)

func hex_distance(from: Vector2i, to: Vector2i) -> int:
	var delta := to - from
	return maxi(
		maxi(abs(delta.x), abs(delta.y)),
		abs(delta.x + delta.y)
	)
	

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	_generate_hex_grid()


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
