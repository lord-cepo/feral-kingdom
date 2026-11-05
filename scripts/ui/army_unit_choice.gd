## Army catalogue checkbox supplying presentation-only content for ArmyMenu's fixed inspector.
extends CheckBox

var info_text := ""
var unit: UnitInfo

## ArmyMenu calls on mouse/focus entry, without Godot's tooltip delay; the returned card never resolves rules.
## The left stripe uses red for the builder's player, blue for enemy-side deployment and grey for Front.
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
	var text := RichTextLabel.new()
	text.bbcode_enabled = true
	text.fit_content = true
	text.scroll_active = false
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.custom_minimum_size.x = 380
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_theme_font_size_override("normal_font_size", 22)
	text.text = info_text
	row.add_child(text)
	return margin
