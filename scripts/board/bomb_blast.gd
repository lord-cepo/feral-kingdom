## Lit origin and resolution-time copies; presentation reads captured blast records without changing bombs or targets.
extends Node2D

const TRAVEL := 0.65
var board: GuerraBoard
var center_cell: HexCell
var center_hex := -1
var delay := 0.0
var elapsed := 0.0
var spread_start := -1.0
var retirement := -1.0
var center := AnimatedSprite2D.new()
var copies: Array[Dictionary] = []
var attacks: Array[CannonAttack] = []
var effective_hexes: Dictionary = {}
var origin_released := false

## Board bomb_light feedback keeps the original lit bomb alone throughout the response window; Fire arrival delays ignition.
func setup(owner_board: GuerraBoard, hex_id: int, fire_delay: float) -> void:
	board = owner_board
	center_hex = hex_id
	delay = fire_delay
	center_cell = board.hex_grid.get_child(hex_id) as HexCell
	center_cell.bomb_blast_overlays += 1
	center_cell.bomb_sprite.hide()
	z_index = 7
	_prepare_sprite(center)
	add_child(center)
	center.play(&"unlit" if delay > 0.0 else &"ignite")
	for attack: CannonAttack in Match.pending_cannon_attacks:
		if attack.explosion and attack.bomb_hex == center_hex and not attack.resolved: attacks.append(attack)

## Origin and travelling copies share the marker's ignition frames and retained bomb body.
func _prepare_sprite(sprite: AnimatedSprite2D) -> void:
	sprite.sprite_frames = center_cell.bomb_sprite.sprite_frames
	sprite.scale = Vector2.ONE * HexCell.BOMB_SCALE
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var body := Sprite2D.new()
	body.texture = load(HexCell.BOMB_ICON)
	body.z_index = -1
	body.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.add_child(body)

## The frozen window removes pending records before its first step; capture effective cells then, allowing intervening movement/defuse.
## Only contact-capable occupants or chain bombs receive neighbour copies; the complete authoritative area still resolves normally.
func _prepare_spread() -> void:
	if spread_start >= 0.0: return
	if not attacks.is_empty() and attacks.all(func(attack: CannonAttack) -> bool: return attack.outcome.get("status") == "defused"): return
	var resolving := attacks.is_empty()
	for attack in attacks:
		if not Match.pending_cannon_attacks.has(attack): resolving = true
	if not resolving: return
	spread_start = maxf(elapsed, delay)
	for attack in attacks:
		if not CombatResolver.bomb_blast_effective(attack): continue
		effective_hexes[attack.target_hex] = true
		if attack.target_hex == center_hex: continue
		var sprite := AnimatedSprite2D.new()
		_prepare_sprite(sprite)
		add_child(sprite)
		sprite.play(&"ignite")
		sprite.modulate.a = 0.0
		copies.append({"sprite": sprite, "hex": attack.target_hex, "attack": attack})

## Board waits for outward duplication to complete before the first ring explosion; pending response windows never spread or block phases.
func empty_fade_busy() -> bool:
	_prepare_spread()
	return spread_start >= 0.0 and elapsed < spread_start + TRAVEL

## Attack/Slash delay queries use remaining spread time rather than time since the bomb was first lit.
func remaining_spread() -> float:
	return maxf(0.0, spread_start + TRAVEL - elapsed) if spread_start >= 0.0 else 0.0

## Godot keeps the origin lit, eases copies outward at resolution, then hands each copy to its own sequential explosion.
## Empty/immune-only cells never get copies; the original retires after final resolution. Defuse instead crossfades to its restored unlit marker.
func _process(delta: float) -> void:
	elapsed += delta
	if not attacks.is_empty() and attacks.all(func(attack: CannonAttack) -> bool: return attack.outcome.get("status") == "defused"):
		_release_origin()
		if retirement < 0.0: retirement = elapsed
		modulate.a = 1.0 - smoothstep(retirement, retirement + 0.25, elapsed)
		if elapsed >= retirement + 0.25: queue_free()
		return
	var tile := Match.get_hex(center_hex)
	if tile == null:
		queue_free()
		return
	var start := board.axial_to_screen(tile.coordinate) + HexCell.BOMB_OFFSET
	center.position = start
	if elapsed < delay: return
	if center.animation != &"ignite": center.play(&"ignite")
	_prepare_spread()
	var progress := clampf((elapsed - spread_start) / TRAVEL, 0.0, 1.0) if spread_start >= 0.0 else 0.0
	for item in copies:
		var destination := Match.get_hex(item.hex)
		if destination == null: continue
		item.sprite.position = start.lerp(board.axial_to_screen(destination.coordinate) + HexCell.BOMB_OFFSET, smoothstep(0.0, 1.0, progress))
		item.sprite.modulate.a = 0.8 * smoothstep(0.0, 1.0, progress)
		if item.attack.resolved: item.sprite.hide()
	for attack in attacks:
		if attack.target_hex == center_hex and attack.resolved: center.hide()
	var pending := attacks.any(func(attack: CannonAttack) -> bool: return not attack.resolved)
	if pending: return
	if retirement < 0.0: retirement = maxf(elapsed, spread_start + TRAVEL)
	modulate.a = 1.0 - smoothstep(retirement, retirement + 0.35, elapsed)
	if elapsed >= retirement + 0.35: queue_free()

## Defuse reveals the restored unlit marker beneath the fading lit origin; teardown uses the same exactly-once visibility release.
func _release_origin() -> void:
	if origin_released or not is_instance_valid(center_cell): return
	origin_released = true
	center_cell.bomb_blast_overlays = maxi(0, center_cell.bomb_blast_overlays - 1)
	center_cell._refresh_bomb_indicator()

## Completion/scene teardown releases presentation ownership without changing any bomb or blast record.
func _exit_tree() -> void:
	_release_origin()
