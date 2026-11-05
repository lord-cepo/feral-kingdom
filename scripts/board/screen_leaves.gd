## Screen-space leaf ambience above the board and below Interface; owns no input or Match state.
extends CanvasLayer

const LEAF_ROOT := "res://assets/environment/windy-leaves/"
const SHEETS := ["ELR_SpringlLeaf.png", "ELR_FallLeaf.png", "ELR_WinterlLeaf.png"]
@export_range(0, 40) var leaf_count := 12
var leaves: Array[Dictionary] = []
var leaf_frames: Array[SpriteFrames] = []
var random := RandomNumberGenerator.new()

## The Board/ScreenLeaves scene node calls this on tree entry; caches five-frame sheets and seeds a bounded sprite pool.
## Initial progress fills the screen immediately; normalized routes automatically follow viewport resizing without camera drift.
func _ready() -> void:
	random.randomize()
	for sheet in SHEETS:
		var frames := SpriteFrames.new()
		frames.set_animation_speed(&"default", 7.0)
		var texture: Texture2D = load(LEAF_ROOT + sheet)
		for index in 5:
			var atlas := AtlasTexture.new()
			atlas.atlas = texture
			atlas.region = Rect2(index * 16, 0, 16, 16)
			frames.add_frame(&"default", atlas)
		leaf_frames.append(frames)
	for index in leaf_count:
		var sprite := AnimatedSprite2D.new()
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		add_child(sprite)
		var leaf := {"sprite": sprite}
		_reset_leaf(leaf, random.randf())
		leaves.append(leaf)

## _ready() and _process() recycle one leaf with a fresh route, flutter phase, size and animation variation.
## The sprite pool stays fixed; a private RNG keeps cosmetic decisions independent of gameplay and saves.
func _reset_leaf(leaf: Dictionary, progress: float = 0.0) -> void:
	leaf.progress = progress
	leaf.height = random.randf_range(-0.2, 0.95)
	leaf.speed = random.randf_range(65.0, 110.0)
	leaf.phase = random.randf_range(0.0, TAU)
	leaf.amplitude = random.randf_range(10.0, 25.0)
	leaf.sprite.sprite_frames = leaf_frames[0 if random.randf() < 0.7 else random.randi_range(1, 2)]
	leaf.sprite.scale = Vector2.ONE * random.randf_range(1.4, 2.2)
	leaf.sprite.speed_scale = random.randf_range(0.7, 1.2)
	leaf.sprite.play()
	leaf.sprite.frame = random.randi_range(0, 4)

## Godot's frame callback carries leaves left-to-right with a shallow downward drift and sinusoidal flutter.
## Fades at both screen edges, reuses off-screen sprites, and samples viewport size so HUD/camera layout never affects routes.
func _process(delta: float) -> void:
	var size := get_viewport().get_visible_rect().size
	for leaf in leaves:
		leaf.progress += delta * leaf.speed / maxf(size.x + 96.0, 1.0)
		if leaf.progress > 1.0:
			_reset_leaf(leaf)
		leaf.phase += delta * 1.8
		var progress: float = leaf.progress
		leaf.sprite.position = Vector2(lerpf(-48.0, size.x + 48.0, progress), (leaf.height + progress * 0.25) * size.y + sin(leaf.phase) * leaf.amplitude)
		leaf.sprite.rotation = sin(leaf.phase * 0.6) * 0.35
		leaf.sprite.modulate.a = 0.65 * smoothstep(0.0, 0.09, progress) * (1.0 - smoothstep(0.91, 1.0, progress))
