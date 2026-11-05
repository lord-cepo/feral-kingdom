## Cosmetic ignition and radial bomb copies; reads captured blast records without delaying combat or changing bombs.
extends Node2D

const TRAVEL := 0.65
var board: GuerraBoard
var center_cell: HexCell
var center_hex := -1
var delay := 0.0
var elapsed := 0.0
var retirement := -1.0
var center := AnimatedSprite2D.new()
var copies: Array[Dictionary] = []
var attacks: Array[CannonAttack] = []
var empty_hexes: Dictionary = {}
var empty_fade_start := -1.0

## GuerraBoard calls after bomb_light repaint; waits for matching Fire travel, then lights and spreads to center-plus-adjacent playable hexes.
## Uses the live bomb frames, body and scale; keeps a pending blast visible until its captured records resolve.
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
	var origin := Match.get_hex(center_hex).coordinate
	for tile in Match.map:
		var difference: Vector2i = tile.coordinate - origin
		if maxi(absi(difference.x), maxi(absi(difference.y), absi(difference.x + difference.y))) != 1: continue
		var sprite := AnimatedSprite2D.new()
		_prepare_sprite(sprite)
		add_child(sprite)
		sprite.play(&"ignite")
		sprite.modulate.a = 0.0
		copies.append({"sprite": sprite, "hex": tile.hex_id})

## setup() shares the live marker's SpriteFrames and persistent body so lit animation transparency never loses its bomb silhouette.
func _prepare_sprite(sprite: AnimatedSprite2D) -> void:
	sprite.sprite_frames = center_cell.bomb_sprite.sprite_frames
	sprite.scale = Vector2.ONE * HexCell.BOMB_SCALE
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var body := Sprite2D.new()
	body.texture = load(HexCell.BOMB_ICON)
	body.z_index = -1
	body.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.add_child(body)

## Godot waits for Fire arrival, switches the source to lit, then eases copies outward with increasing opacity over 0.65s.
## Resolved/instant blasts hold briefly then fade; pending records retain their landing copies without replaying rules.
## Empty hex replicas fade together at the frozen combat window; occupied replicas hand off to individual explosions on resolution.
## Captured unresolved records remain pending after CombatResolver removes them from the public queue to freeze its resolution batch.
func _process(delta: float) -> void:
	elapsed += delta
	var tile := Match.get_hex(center_hex)
	if tile == null:
		queue_free()
		return
	var start := board.axial_to_screen(tile.coordinate) + HexCell.BOMB_OFFSET
	center.position = start
	if elapsed < delay: return
	_prepare_empty_fade()
	var empty_alpha := 1.0 if empty_fade_start < 0.0 else 1.0 - smoothstep(empty_fade_start, empty_fade_start + 0.35, elapsed)
	if center.animation != &"ignite": center.play(&"ignite")
	center.modulate.a = empty_alpha if empty_hexes.has(center_hex) else 1.0
	for attack in attacks:
		if attack.target_hex == center_hex and attack.resolved and not empty_hexes.has(center_hex): center.hide()
	var travel := elapsed - delay
	var progress := clampf(travel / TRAVEL, 0.0, 1.0)
	for item in copies:
		var destination := Match.get_hex(item.hex)
		if destination == null: continue
		item.sprite.position = start.lerp(board.axial_to_screen(destination.coordinate) + HexCell.BOMB_OFFSET, smoothstep(0.0, 1.0, progress))
		item.sprite.modulate.a = 0.8 * smoothstep(0.0, 1.0, progress)
		if empty_hexes.has(int(item.hex)): item.sprite.modulate.a *= empty_alpha
		for attack in attacks:
			if attack.target_hex == int(item.hex) and attack.resolved and not empty_hexes.has(int(item.hex)): item.sprite.hide()
	var pending := false
	for attack in attacks:
		if not attack.resolved: pending = true
	if pending: return
	if retirement < 0.0: retirement = maxf(elapsed, delay + TRAVEL) + 0.5
	modulate.a = 1.0 - smoothstep(retirement, retirement + 0.35, elapsed)
	if elapsed >= retirement + 0.35: queue_free()

## Process and Board's continuation query detect the frozen blast batch before its first damage step, capturing empty hexes once.
## Queue removal marks batch start, not completion; occupied replicas still follow their own captured record's resolved flag.
func _prepare_empty_fade() -> void:
	if empty_fade_start >= 0.0: return
	var resolving := false
	for attack in attacks:
		if not Match.pending_cannon_attacks.has(attack): resolving = true
	if not resolving: return
	for attack in attacks:
		var occupied := not Match.occupants(attack.target_hex).is_empty()
		if attack.resolved: occupied = not attack.outcome.get("targets", []).is_empty()
		if not occupied: empty_hexes[attack.target_hex] = true
	empty_fade_start = maxf(elapsed, delay + TRAVEL) + 0.5

## Board waits for empty replicas' shared 500ms hold/350ms fade before resolving occupied hexes one by one.
## No empty hexes means no added wait; pending future combat windows never start the fade.
func empty_fade_busy() -> bool:
	_prepare_empty_fade()
	return not empty_hexes.is_empty() and elapsed < empty_fade_start + 0.35

## Scene teardown/completion releases only this overlay's visibility claim, restoring the ordinary marker from authoritative state.
func _exit_tree() -> void:
	if not is_instance_valid(center_cell): return
	center_cell.bomb_blast_overlays = maxi(0, center_cell.bomb_blast_overlays - 1)
	center_cell._refresh_bomb_indicator()
