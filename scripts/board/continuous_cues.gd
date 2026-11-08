## Board-owned presentation of live continuous rules; no execution, events or acknowledgement gates.
extends Node

var board: GuerraBoard
var entries: Dictionary = {}
var banner: Sprite2D
var banner_text := ""

## GuerraBoard._ready installs this observer after its cells; authoritative state signals refresh eligibility.
func setup(owner_board: GuerraBoard) -> void:
	board = owner_board
	Match.state_changed.connect(refresh)
	refresh.call_deferred()

## Returns currently applicable authored rules, including static state modifiers, without changing counters.
## A recipient aura needs at least one eligible deployed recipient; owner/recipient predicates use the engine's own query.
func active_rules(unit: UnitInfo) -> PackedStringArray:
	var lines := PackedStringArray()
	if unit.t_state != Enum.t_state.DEPLOYED: return lines
	var ctx := RuleContext.new(TargetRef.unit(unit.iun))
	ctx.subject = ctx.source
	for state in unit.state_effects:
		if state == null: continue
		ctx.error = ""
		if state.condition != null and not state.condition.test(ctx): continue
		if not ctx.error.is_empty(): continue
		var text := state.label
		if state.physical != 0 or state.magical != 0:
			text += ": " + EffectText._modifiers(state.physical, state.magical)
		lines.append(text)
	for aura in unit.continuous_effects:
		if aura == null: continue
		for recipient: UnitInfo in Match.army:
			if aura.applies_to(unit.iun, recipient.iun):
				lines.append(EffectText._continuous(aura, unit))
				break
	return lines

## State changes group active rules by source, using the same player colors as the phase sign for each unit name.
func refresh() -> void:
	entries.clear()
	var descriptions := PackedStringArray()
	for unit: UnitInfo in Match.army:
		var rules := active_rules(unit)
		if rules.is_empty(): continue
		var owner_color := "#ef7770" if unit.player == 1 else "#6da9ee"
		var text := "[color=%s]%s[/color]\n%s" % [owner_color, unit.name.replace("[", "[lb]"), "\n".join(rules)]
		entries[unit.iun] = text
		descriptions.append(text)
	banner_text = "\n\n".join(descriptions)

## The controller polls the circle's stable hitbox; hovering lists active continuous rules grouped by source.
func hovered_text(pointer: Vector2) -> String:
	if is_instance_valid(banner) and banner.modulate.a > 0.05:
		var point := banner.get_global_transform_with_canvas().affine_inverse() * pointer
		if banner.get_rect().has_point(point): return banner_text
	return ""

## Godot fades the half-size (22px) pixel circle inside the sign, left of its caption; the transformed hover hitbox follows its size/position.
func _process(delta: float) -> void:
	var sign: Control = board.phase_sign_feedback.get_ref() if board.phase_sign_feedback != null else null
	if not is_instance_valid(sign): return
	if not is_instance_valid(banner):
		banner = Sprite2D.new()
		banner.texture = preload("res://assets/ui/continuous-circle.png")
		banner.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		banner.scale = Vector2(22.0, 22.0) / banner.texture.get_size()
		banner.modulate.a = 0.0
		sign.add_child(banner)
	banner.position = Vector2(44, 113)
	banner.modulate.a = move_toward(banner.modulate.a, 0.0 if entries.is_empty() else 1.0, delta / 0.3)