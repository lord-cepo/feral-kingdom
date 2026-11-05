extends Node

## Composition root for the Godot client.

## Starts the local match after its Board and UI children have entered the scene tree.
## LocalMatchController owns the sample setup and connects player input to Match.
@onready var local_match: LocalMatchController = $MatchSession
@onready var board: GuerraBoard = $Board
@onready var ui_layer: CanvasLayer = $UI

## Installs shared pixel pointer, text and drag/drop shapes, then starts the local-match HUD.
## Both client entry scenes use the same installer; cursor presentation does not change input handling.
func _ready() -> void:
	preload("res://scripts/ui/game_cursors.gd").install()
	local_match.start_match(board, ui_layer)
