## Screen-space PixelLab inn sign; queues visible phase changes so synchronous phase signals each receive their animation.
extends Control

const CLIP_SECONDS := 0.75
const PLAYER_RED := Color("#ef7770")
const PLAYER_BLUE := Color("#6da9ee")
## Native terrain pixel at the upper-right pond circled by the user; the sign follows that landmark when the viewport changes.
@export var terrain_pixel := Vector2(1184, 176)
var board: GuerraBoard
var art := TextureRect.new()
var settled_art := TextureRect.new()
var caption := Label.new()
var frames: Array[Texture2D] = []
var pending: Array[Dictionary] = []
var requested := ""
var requested_player := -1
var elapsed := CLIP_SECONDS
var next_caption := ""
var next_player := 1
var text_fade := 0.0
var changing := false
var trigger_blink := AnimatedSprite2D.new()

## HUD builds the sign once; phase_changed queues Start/Action/Resolve/End, with both internal resolve phases sharing one visible name.
## state_changed synchronizes snapshots; the board reference anchors the sign over the circled pond, left of the side cards.
## Registers a matching trigger blink beside the phase word; both it and the unit cue share the runner acknowledgement gate.
## The refreshed idle artwork blends over the older PixelLab animation as the entrance settles.
## Phase and captured-trigger notifications show only meaningful boundaries; routine Start/End work still runs without sign delays.
func _ready() -> void:
	size = Vector2(192, 192)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for index in 9: frames.append(load("res://assets/ui/inn-sign/frame_%d.png" % index))
	art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(art)
	settled_art.texture = preload("res://assets/ui/inn-sign/idle.png")
	settled_art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	settled_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	settled_art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	settled_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	settled_art.modulate.a = 0.0
	add_child(settled_art)
	caption.position = Vector2(24, 91)
	caption.size = Vector2(144, 44)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	caption.add_theme_font_size_override("font_size", 28)
	caption.add_theme_color_override("font_color", Color("#f0e0ba"))
	caption.add_theme_color_override("font_outline_color", Color("#382419"))
	caption.add_theme_constant_override("outline_size", 2)
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(caption)
	var blink_frames := SpriteFrames.new()
	blink_frames.set_animation_loop(&"default", true)
	blink_frames.set_animation_speed(&"default", 8.0)
	for index in 8: blink_frames.add_frame(&"default", load("res://assets/effects/trigger/frame_%d.png" % index))
	trigger_blink.sprite_frames = blink_frames
	trigger_blink.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	trigger_blink.scale = Vector2.ONE * 0.8
	trigger_blink.modulate.a = 0.0
	add_child(trigger_blink)
	trigger_blink.play()
	if is_instance_valid(board): board.phase_sign_feedback = weakref(self)
	Match.phase_changed.connect(_on_phase_changed)
	Match.state_changed.connect(_sync_phase)
	Match.rules_runner.trigger_presentation_requested.connect(_on_trigger_presentation)
	_sync_phase.call_deferred()

## Match phase notifications always show Action, and show Resolve only when this combat window has eligible pending attacks.
## Start/End are announced by actual captured triggers instead of showing routine action refresh/recovery and activation.
func _on_phase_changed(phase: int, player: int) -> void:
	if phase == Match.Phase.ACTION:
		_queue_phase(phase, player)
	elif phase == Match.Phase.COMBAT_RESOLVE and _has_pending_combat(player):
		_queue_phase(phase, player)

## The runner requests acknowledgement only for an actually captured trigger; show its current non-Action boundary before the blink becomes ready.
## This also reveals End when automatic activation itself triggers an ability, without pre-running conditions or duplicating events.
func _on_trigger_presentation(_execution: EffectExecution) -> void:
	if Match.phase != Match.Phase.ACTION: _queue_phase(Match.phase, Match.active_player)

## Reads the same eligibility as CombatResolver.resolve_window: opposing queued attacks and Bash encounters responding to this player.
## Newly queued attacks awaiting the other player's window do not make the current Resolve special.
func _has_pending_combat(player: int) -> bool:
	for attacks in [Match.pending_bow_attacks, Match.pending_gore_attacks, Match.pending_cannon_attacks, Match.pending_attacks]:
		for attack in attacks:
			if not attack.resolved and attack.owner != player: return true
	for bash in Match.bashes:
		if not bash.resolved and bash.responding_player == player: return true
	return false

## Meaningful phase/trigger callbacks retain the captured owner and deduplicate the two internal Resolve phases for the sign queue.
func _queue_phase(phase: int, player: int) -> void:
	var name := _phase_name(phase)
	if name == requested and player == requested_player: return
	requested = name
	requested_player = player
	pending.append({"name": name, "player": player})

## Snapshot/reset state notifications use the same meaningful-phase filter without animating routine stat refreshes or empty boundaries.
func _sync_phase() -> void:
	_on_phase_changed(Match.phase, Match.active_player)

## Maps engine phases to the four player-facing words requested for the sign.
func _phase_name(phase: int) -> String:
	match phase:
		Match.Phase.START: return "Start"
		Match.Phase.ACTION: return "Action"
		Match.Phase.ACTION_RESOLVE, Match.Phase.COMBAT_RESOLVE: return "Resolve"
		Match.Phase.END: return "End"
	return "Action"

## Godot plays all nine frames once per queued phase; text uses the hover info's light red/blue for the captured player.
## The graphical runner waits for this finite entrance before advancing phase continuations; the looping blink never blocks that wait.
## Old words fade before replacement; the new word and owner color appear together during the entrance fade.
## Updated idle artwork crossfades over the final 180ms because PixelLab's existing animation retains the previous sign design.
## Keeps the landmark's horizontal placement and a 5px visible top margin, compensating for the artwork's 22px transparent top padding.
func _process(delta: float) -> void:
	if is_instance_valid(board):
		var world_point := board.origin + (terrain_pixel - board.terrain_anchor) * board.terrain_scale
		var screen_point := board.get_global_transform_with_canvas() * world_point
		var viewport_size := get_viewport_rect().size
		position = Vector2(clampf(screen_point.x - size.x * 0.5, 8, maxf(8, viewport_size.x - size.x - 8)),
			5.0 - 22.0 * size.y / 128.0)
	_update_trigger_blink(delta)
	if elapsed >= CLIP_SECONDS and not pending.is_empty() and not changing:
		var entry: Dictionary = pending.pop_front()
		next_caption = entry["name"]
		next_player = entry["player"]
		text_fade = 0.0
		changing = true
	if changing:
		text_fade += delta
		caption.modulate.a = 1.0 - smoothstep(0.0, 0.1, text_fade)
		if text_fade < 0.1 and not caption.text.is_empty(): return
		caption.text = next_caption
		caption.add_theme_color_override("font_color", PLAYER_RED if next_player == 1 else PLAYER_BLUE)
		changing = false
		elapsed = 0.0
	elapsed = minf(CLIP_SECONDS, elapsed + delta)
	art.texture = frames[mini(8, int(elapsed / CLIP_SECONDS * 9.0))]
	settled_art.modulate.a = smoothstep(CLIP_SECONDS - 0.18, CLIP_SECONDS, elapsed)
	art.modulate.a = 1.0 - settled_art.modulate.a
	caption.modulate.a = smoothstep(0.12, 0.35, elapsed)

## Board's finite-animation query uses the entrance/text queue only, excluding the persistent trigger blink.
func is_transitioning() -> bool:
	return changing or not pending.is_empty() or elapsed < CLIP_SECONDS

## Godot fades a small matching blink to the right of the measured phase word while either player acknowledgement is pending.
func _update_trigger_blink(delta: float) -> void:
	var runner := Match.rules_runner
	var showing := runner.presentation_waiting != null and runner.presentation_ready and runner.presentation_acknowledged.size() < 2
	trigger_blink.modulate.a = move_toward(trigger_blink.modulate.a, 1.0 if showing else 0.0, delta / (0.25 if showing else 0.35))
	var text_width := caption.get_theme_font("font").get_string_size(caption.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 28).x
	trigger_blink.position = Vector2(96 + minf(text_width * 0.5, 48) + 15, 113)

## Board input asks this before consuming a paused click; the sign blink acknowledges through the same player-identity path as the unit cue.
func contains_trigger_blink(viewport_position: Vector2) -> bool:
	if trigger_blink.modulate.a <= 0.05 or not Match.rules_runner.presentation_ready: return false
	var point := trigger_blink.get_global_transform_with_canvas().affine_inverse() * viewport_position
	return Rect2(-16, -16, 32, 32).has_point(point)
