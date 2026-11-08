## Army catalogue checkbox supplying presentation-only content for ArmyMenu's fixed inspector.
extends CheckBox

var info_text := ""
var unit: UnitInfo

## ArmyMenu calls on mouse/focus entry, without Godot's tooltip delay; the returned card never resolves rules.
## The left stripe uses red for the builder's player, blue for enemy-side deployment and grey for Front.
## Glossary metadata signals show a fading explanation below the rules on ordinary hover.
func make_info_card() -> Control:
	var margin := MarginContainer.new()
	for edge in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 14)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	margin.add_child(row)
	var bar := VBoxContainer.new()
	bar.custom_minimum_size.x = 8
	bar.add_theme_constant_override("separation", 0)
	row.add_child(bar)
	for region in [Enum.region.STARTING, Enum.region.INTERMEDIATE, Enum.region.FRONT]:
		if region not in unit.deploy_regions and Enum.region.ANY not in unit.deploy_regions: continue
		var segment := ColorRect.new()
		segment.custom_minimum_size = Vector2(8, 24)
		segment.size_flags_vertical = Control.SIZE_EXPAND_FILL
		match region:
			Enum.region.STARTING: segment.color = Color("#1d4ed8") if unit.deployment_enemy_side else Color("#b91c1c")
			Enum.region.INTERMEDIATE: segment.color = Color("#60a5fa") if unit.deployment_enemy_side else Color("#f87171")
			Enum.region.FRONT: segment.color = Color("#cbd5e1")
		bar.add_child(segment)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(content)
	var text := RichTextLabel.new()
	text.bbcode_enabled = true
	text.fit_content = true
	text.scroll_active = false
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.custom_minimum_size.x = 380
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_theme_font_size_override("normal_font_size", 22)
	text.text = RuleGuide.decorate(info_text)
	content.add_child(text)
	var guide := Label.new()
	guide.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	guide.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	guide.mouse_filter = Control.MOUSE_FILTER_IGNORE
	guide.add_theme_font_size_override("font_size", 18)
	guide.modulate.a = 0.0
	content.add_child(guide)
	text.meta_hover_started.connect(_show_rule_guide.bind(guide))
	text.meta_hover_ended.connect(_hide_rule_guide.bind(guide))
	return margin

## Inspector meta_hover_started resolves shared glossary metadata into this card's own explanation label.
func _show_rule_guide(meta: Variant, guide: Label) -> void:
	var value := str(meta)
	if not value.begins_with("guide:"): return
	var description := RuleGuide.description(value.trim_prefix("guide:"))
	if description.is_empty(): return
	guide.set_meta("guide_key", value)
	guide.text = description
	_fade_rule_guide(guide, 1.0)

## Inspector meta_hover_ended dismisses only its current keyword, preserving newer adjacent hover entries.
func _hide_rule_guide(meta: Variant, guide: Label) -> void:
	if str(meta) != str(guide.get_meta("guide_key", "")): return
	guide.set_meta("guide_key", "")
	_fade_rule_guide(guide, 0.0)

## Entry/exit callbacks blend from current opacity and cancel prior fades; retained layout space avoids shifting rules on exit.
func _fade_rule_guide(guide: Label, opacity: float) -> void:
	var previous: Tween = guide.get_meta("guide_tween", null)
	if previous != null: previous.kill()
	var tween := guide.create_tween()
	guide.set_meta("guide_tween", tween)
	tween.tween_property(guide, "modulate:a", opacity, 0.12)
