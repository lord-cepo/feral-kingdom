## Exports current object-authored card definitions for the standalone HTML catalogue, without loading or saving a match.
extends Node

## Export scene entry point enumerates the shared catalogue across both definition files, supplies movement and writes presentation data once.
## tools/build_unit_catalogue.py packages this data and local icons into an offline HTML file.
func _ready() -> void:
	var roster: Dictionary = {}
	for unit in CardCatalogue.starter_army(): roster[unit.uuid.trim_suffix("-p%d" % unit.player)] = true
	var records: Array = []
	for unit in CardCatalogue.all_units(1):
		var factory := unit.uuid.trim_suffix("-p1").replace("-", "_")
		unit.ensure_implicit_walk()
		unit.iun = Match.army.size()
		Match.army.append(unit)
		var key := unit.uuid.trim_suffix("-p1")
		var regions: Array = []
		for region in unit.deploy_regions: regions.append(String(Enum.region.keys()[region]).capitalize())
		if unit.deployment_enemy_side: regions.append("Opponent side")
		var effects: Array = []
		for line in EffectText.unit_lines(unit): effects.append(RuleGuide.decorate(line))
		records.append({"id": key, "name": unit.name, "kind": String(Enum.type.keys()[unit.type]).capitalize(),
			"life": unit.max_life, "deployment": ", ".join(regions), "effects": effects,
			"portrait": BoardCharacter.portrait_path(unit), "in_roster": roster.has(key), "factory": factory})
	var icons: Dictionary = {}
	for action in RuleGuide.ENTRIES:
		var path := GameIcons.action_path(StringName(action))
		if not path.is_empty(): icons[action] = path
	var output := FileAccess.open("res://.godot/unit-catalogue-data.json", FileAccess.WRITE)
	output.store_string(JSON.stringify({"units": records, "glossary": RuleGuide.ENTRIES, "stickers": RuleGuide.STICKERS, "icons": icons}, "\t"))
	print("Exported %d distinct unit definitions" % records.size())
	get_tree().quit()
