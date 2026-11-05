## Compile-only build entry; loads client scripts without creating controls, connecting sockets or executing gameplay tests.
extends Node

## Godot invokes this build scene once; failed script compilation returns a nonzero process exit code.
func _ready() -> void:
	for path in ["res://scripts/network/network_session.gd", "res://scripts/ui/network_lobby.gd", "res://scripts/ui/army_menu.gd", "res://scripts/ui/local_match_controller.gd", "res://scripts/board/board.gd", "res://tests/network_session_test.gd"]:
		var script := load(path) as GDScript
		if script == null or not script.can_instantiate():
			push_error("Client compilation failed: " + path)
			get_tree().quit(1)
			return
	print("Network client scripts compiled; no sockets connected or tests executed.")
	get_tree().quit()
