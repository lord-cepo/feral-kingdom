## Cosmetic grass and weather sprites; no rules, selection or input ownership lives here.
class_name BoardAmbience
extends Node2D

const GRASS_TALL := "res://assets/environment/grass-tall/animations/The_blades_of_grass_sway_rhythmically_bending_in/unknown/"
const GRASS_BUSH := "res://assets/environment/grass-bush/animations/The_dense_foliage_sways_rhythmically_leaning_heav/unknown/"
const TORNADO := "res://assets/environment/tornado/animations/The_wispy_form_begins_to_tighten_its_nebulous_edg/unknown/"
const WIND := "res://assets/environment/wind/"
## Off by default while screen-wide weather presentation is being considered; enable before setup to restore local one-shots.
@export var weather_enabled := false
var board: GuerraBoard
var grass: Array[Dictionary] = []
var clips: Dictionary = {}
var random := RandomNumberGenerator.new()
## Native terrain pixel at the lower-left wooden island; realign keeps the banner's feet attached during resize.
@export var banner_pixel := Vector2(252, 760)
var banners: Array[AnimatedSprite2D] = []
var banner_player := 0
var banner_fade: Tween

## Creates six perimeter clusters of resting grass and bushes with independent pause timers; starts local weather only when enabled.
## GuerraBoard._ready() calls once after layout. AnimatedSprite2D/Timer run independently of Match commands and never intercept input.
## Also creates the active-player island banner and listens for turn/snapshot changes without affecting rules.
func setup(owner_board: GuerraBoard) -> void:
	board = owner_board
	random.randomize()
	var placements: Array = JSON.parse_string(FileAccess.get_file_as_string("res://assets/environment/grass-placements.json"))
	for placement: Dictionary in placements:
		var sprite := _sprite(GRASS_TALL if placement.kind == "tall" else GRASS_BUSH, false, 6.0)
		sprite.offset.y = -11.0
		sprite.stop()
		var pause := Timer.new()
		pause.one_shot = true
		add_child(pause)
		var index := grass.size()
		grass.append({"sprite": sprite, "cell": Vector2(placement.x, placement.y), "size": float(placement.size), "group": int(placement.group), "pause": pause})
		pause.timeout.connect(_grass_pause_finished.bind(index))
		sprite.animation_finished.connect(_grass_finished.bind(index))
		pause.start(random.randf_range(2.0, 10.0))
	_setup_banner()
	realign()
	if not weather_enabled: return
	var timer := Timer.new()
	timer.wait_time = 3.0
	timer.timeout.connect(_spawn_weather)
	add_child(timer)
	timer.start()

## Maps authored PixelLab terrain cells to the same native PNG origin/scale as the background.
## setup() and Board._layout_board() call this so grass stays attached to terrain when layout changes.
## Both banner colors share a grounded anchor on the wooden island and preserve their independent looping clips.
func realign() -> void:
	if board == null: return
	for placement in grass:
		var pixel: Vector2 = (placement.cell + Vector2(2.5, 2.5)) * 32.0
		placement.sprite.position = board.origin + (pixel - board.terrain_anchor) * board.terrain_scale
		placement.sprite.scale = board.terrain_scale * (placement.size * 32.0 / 24.0)
	for sprite: AnimatedSprite2D in banners:
		sprite.position = board.origin + (banner_pixel - board.terrain_anchor) * board.terrain_scale
		sprite.scale = board.terrain_scale * 1.3

## setup() creates the user's red/blue PixelLab clips at 7fps and initializes the current player's visible banner.
## Texture fallback handles freshly downloaded PNGs; both clips loop continuously throughout a 0.6s turn crossfade.
func _setup_banner() -> void:
	for color in ["red", "blue"]:
		var sprite := AnimatedSprite2D.new()
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		sprite.offset.y = -28.0
		var frames := SpriteFrames.new()
		frames.set_animation_loop(&"default", true)
		frames.set_animation_speed(&"default", 7.0)
		for index in 9:
			var path := "res://assets/environment/banner/%s/frame_%d.png" % [color, index]
			var texture: Texture2D
			if ResourceLoader.exists(path, "Texture2D"): texture = load(path) as Texture2D
			if texture == null:
				var image := Image.load_from_file(path)
				if image != null and not image.is_empty(): texture = ImageTexture.create_from_image(image)
			if texture != null: frames.add_frame(&"default", texture)
			else: push_error("Cannot load banner frame: %s" % path)
		sprite.sprite_frames = frames
		sprite.modulate.a = 1.0 if banners.size() + 1 == Match.active_player else 0.0
		add_child(sprite)
		banners.append(sprite)
		sprite.play()
	banner_player = Match.active_player
	Match.phase_changed.connect(_banner_phase_changed)
	Match.state_changed.connect(_sync_banner)

## Match.phase_changed calls this at Start and later phases; only a different active player starts a crossfade.
func _banner_phase_changed(_phase: int, _player: int) -> void:
	_sync_banner()

## Turn notifications and state/snapshot repaint use this idempotent transition; a new turn interrupts from current alpha.
## Initializes no game state and never restarts the waving animation when the phase changes within the same turn.
func _sync_banner() -> void:
	if banner_player == Match.active_player or banners.is_empty(): return
	banner_player = Match.active_player
	if banner_fade != null: banner_fade.kill()
	banner_fade = create_tween().set_parallel(true)
	banner_fade.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	for index in banners.size():
		banner_fade.tween_property(banners[index], "modulate:a", 1.0 if index + 1 == banner_player else 0.0, 0.6)

## Loads and shares nine-frame SpriteFrames per source folder; grass and weather currently stop after one pass.
## _sprite() calls this at creation; wind follows wind.pxo's exported six-fps timing.
func _clip(folder: String, looped: bool, fps: float) -> SpriteFrames:
	if clips.has(folder): return clips[folder]
	var frames := SpriteFrames.new()
	frames.set_animation_loop(&"default", looped)
	frames.set_animation_speed(&"default", fps)
	for index in 9:
		frames.add_frame(&"default", load(folder + "frame_%03d.png" % index))
	clips[folder] = frames
	return frames

## Adds a nearest-filtered animation above terrain but beneath hexes, figures and HUD.
## setup() immediately stops grass until its pause expires; _weather_effect() starts one-shots immediately.
func _sprite(folder: String, looped: bool, fps: float) -> AnimatedSprite2D:
	var sprite := AnimatedSprite2D.new()
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.sprite_frames = _clip(folder, looped, fps)
	add_child(sprite)
	sprite.play()
	return sprite

## Each plant's Timer.timeout starts one pass after its independent 2–10 second rest.
## A private 10% roll instead restarts every member of its group together; their pending pauses are cancelled.
func _grass_pause_finished(index: int) -> void:
	var plant: Dictionary = grass[index]
	var whole_group := random.randf() < 0.1
	for member_index in grass.size():
		var member: Dictionary = grass[member_index]
		if member_index != index and (not whole_group or member.group != plant.group): continue
		member.pause.stop()
		member.sprite.stop()
		member.sprite.play()

## A plant's animation_finished signal restores its resting frame and schedules its next independent pause.
## Group passes finish together, then each plant draws a fresh delay; no rules state or global RNG is touched.
func _grass_finished(index: int) -> void:
	var plant: Dictionary = grass[index]
	plant.sprite.stop()
	plant.pause.start(random.randf_range(2.0, 10.0))

## Timer.timeout spawns one wind and one tornado every three seconds at separate unoccupied board hexes when possible.
## Only live Match queries are read; a private RNG keeps decorative randomness separate from game decisions.
func _spawn_weather() -> void:
	var vacant := Match.map.filter(func(tile: HexInfo) -> bool: return Match.occupants(tile.hex_id).is_empty())
	if vacant.is_empty(): return
	var wind_index := random.randi_range(0, vacant.size() - 1)
	var wind_tile: HexInfo = vacant[wind_index]
	if vacant.size() > 1: vacant.remove_at(wind_index)
	var tornado_tile: HexInfo = vacant[random.randi_range(0, vacant.size() - 1)]
	_weather_effect(WIND, wind_tile, 6.0, 0.65)
	_weather_effect(TORNADO, tornado_tile, 8.0, 0.7)

## Fades a new weather sprite in over 0.2 seconds while it plays once, then delegates its final fade to _fade_weather().
## _spawn_weather() supplies a vacant tile and opacity; the small random offset stays inside the hex's central ground area.
func _weather_effect(folder: String, tile: HexInfo, fps: float, opacity: float) -> void:
	var sprite := _sprite(folder, false, fps)
	sprite.position = board.axial_to_screen(tile.coordinate) + Vector2(random.randf_range(-50, 50), random.randf_range(-25, 25))
	sprite.scale = Vector2.ONE * 3.0
	sprite.modulate.a = 0.0
	sprite.animation_finished.connect(_fade_weather.bind(sprite), CONNECT_ONE_SHOT)
	var tween := sprite.create_tween()
	tween.tween_property(sprite, "modulate:a", opacity, 0.2)

## AnimatedSprite2D.animation_finished calls this after a transient clip; hold its last frame during a 0.45-second fade, then free it.
## Completed effects retain no pending rule/execution references and cannot accumulate between timer ticks.
func _fade_weather(sprite: AnimatedSprite2D) -> void:
	var tween := sprite.create_tween()
	tween.tween_property(sprite, "modulate:a", 0.0, 0.45)
	tween.tween_callback(sprite.queue_free)
