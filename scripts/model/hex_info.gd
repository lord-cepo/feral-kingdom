class_name HexInfo
extends RefCounted

# fixed attibutes
var hex_id: int
var coordinate: Vector2i
var region: Enum.region
var side := Enum.side.NONE
var region_count: int

# variable attributes
var props: Array[Prop] = []
var control := Enum.control.NONE
var iun := Vector2i(-1,-1)
var owner := Enum.owner.NONE

func _init(_hex_id: int, _coordinate: Vector2i, _region: Enum.region, _side: Enum.side, _region_count: int):
	self.hex_id = _hex_id
	self.coordinate = _coordinate
	self.region = _region
	self.side = _side
	self.region_count = _region_count
