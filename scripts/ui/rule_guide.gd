## Shared presentation glossary: hover labels decorate words/images and the controller displays these entries while Ctrl is held.
class_name RuleGuide
extends RefCounted

const STICKERS := {
	"F": "F: Instant — resolves the attack immediately; normal costs still apply.",
	"P": "P: Pierce — ignores the relevant defensive modifier. Magical Pierce bypasses Obsidian; physical Pierce does not bypass Titanium.",
	"A": "[A]: spend one player action. [S] pays self-Stun; [AS] pays both. Unmarked actions default to [AS].",
}

const ENTRIES := {
	"end": "End: resolve End effects and activation followups, then remove grants that last until this turn's End.",
	"friend": "Friend: a deployed friendly unit unless a different zone is stated. Event watchers retain the historical participant described by the trigger.",
	"it": "It: the trigger's subject.",
	"target": "Target: the trigger's object.",
	"itself": "Itself: this unit.",
	"friendly": "Friendly unit: a deployed unit belonging to you, unless a different zone is explicitly stated. Event watchers use their stated historical participants, including cards being returned to hand.",
	"wild": "Wild: the unit's name contains Wild, case-insensitively. Name groups such as squirrel or mouse work the same way; they are not passive abilities or flags.",
	"disable": "Disable: choose a unit in hand and change its state to defeated. Ownership is specified by the effect. It does not cause death triggers; health, counters and abilities are preserved.",
	"reset": "Reset: restore printed health and effects; remove wounds, counters, upgrades and copied effects. The unit keeps its current location and state.",
	"deploy": "Deploy: place a unit from hand on a legal vacant hex in a region you control. Requires a deployment and an action.",
	"revive": "Revive: return a friendly defeated non-hero to hand at full health. Other counters and effects are preserved.",
	"flee": "Flee: take one free use of this unit's Walk or Fly ability. A Bash defender leaving alive dodges the encounter; the attacker leaving does not count as an enemy fleeing from it.",
	"upgrade": "Upgrade: choose a unit, then one numeric ability. M Upgrade N grants +M/+N permanently to that chosen ability. A following number is range; otherwise use the stated selector. Reset removes upgrades.",
	"return": "return: move a deployed unit to its owner's hand inactive, preserving health, counters and abilities. Revive also causes return.",
	"c": "C — Cost: pay the written cost and spend an action.",
	"ac": "AC — Additional cost: self-Stun as for a normal action, in addition to the written cost.",
	"a": "[A]: spend one player action plus written costs; no implicit self-Stun.",
	"s": "[S]: become inactive and gain one Stun, plus written costs; no player action.",
	"as": "[AS]: spend one action and pay ordinary self-Stun plus written costs. Default for unmarked actions.",
	"2s": "[2S]: pay two self-Stun instead of one, without spending a player action.",
	"a2s": "[A2S]: spend one action and pay two self-Stun.",
	"sacrifice": "Sacrifice: defeat a chosen deployed friend as payment. This emits Die and Sacrifice; costs are not refunded after later failure.",
	"ember": "Ember: each counter adds one damage to the next declared Fire, then current Ember is consumed. Queued attacks keep their captured values.",
	"projectile": "Projectile: ammunition paid by the printed action. Deploy can grant more; Reset does not itself cause Deploy.",
	"control": "Control counters add to a unit's regional strength, separately from physical protection.",
	"hit": "Hit: actual physical or magical attack contact, including zero damage; misses and immunity do not count.",
	"wound": "Wound: positive life loss from attack contact. Nonlethal Fire creates Hit without Wound.",
	"attacks": "Attacks: starts a Bash or uses Bow, Fire or Cannon. The trigger watches the declaration.",
	"die": "Death: the unit is defeated. Its death triggers are captured before it leaves the board.",
	"bash": "Bash: opposing units share a hex. The unit that entered is the attacker; the other is the defender.",
	"move": "Walk: move up to the shown number of hexes along a legal route.",
	"bow": "Bow: a physical ranged attack. The left number is damage; the right is range.",
	"fire": "Fire: a magical attack resolved in the opposing combat window. It defeats a vulnerable target; survivors take no partial damage.",
	"cannon": "Cannon: a magical attack along a straight line, potentially hitting either player's units.",
	"stun": "Stun: deactivate and add Stun counters; preserve all other counters, including shields. Stun counters prevent activation. At your Start, your hero removes one Stun from each friendly deployed unit.",
	"shield": "Shield: temporary physical protection, consumed on contact unless contact is prevented.",
	"mshield": "Magic shield: temporary magical protection, consumed on magical contact.",
	"heart": "Life: current health and maximum health. Damage changes current health; upgrades can change both.",
	"bomb": "Bomb: Fire ignites it, spreading blasts radially to affected hexes.",
	"shifted": "Shifted: this unit changed position through forced displacement (currently Push or Pull). Walk and Fly do not count.",
	"push": "Push: move the chosen target away from the acting unit.",
	"pull": "Pull: move the chosen target toward the acting unit.",
}

## Controller hover labels call this once on creation; BBCode tags/asset paths stay intact and existing links are never nested.
## Keyword links include attack declarations and use explicit underlines; icon entries share GameIcons' asset vocabulary.
## Sticker letters immediately preceding an icon are captured in its guide metadata, keeping each attack's explanation local to that occurrence.
## Bracketed A/S cost markers link independently; ordinary English articles are not mistaken for action costs.
static func decorate(text: String) -> String:
	var regex := RegEx.new()
	regex.compile("\\[img[^\\]]*\\][^\\[]+\\[/img\\]|\\[[^\\]]*\\]|(?<=\\[lb\\])(?i:A2S|2S|AS|A|S)(?=\\[rb\\])|\\b(?i:upgrade|disable|reset|sacrific(?:e|ed)|embers?|projectiles?|control|attacks|hits?|wounds?|deploys?|revive|flees?|returns?|friends?|friendly|wild|itself|it|target|End|AC|C)\\b|⚔️")
	var result := ""
	var offset := 0
	var link_depth := 0
	for found in regex.search_all(text):
		result += text.substr(offset, found.get_start() - offset)
		var token := found.get_string()
		var key := token.to_lower()
		if token.begins_with("[url"): link_depth += 1
		if token == "[/url]": link_depth = maxi(0, link_depth - 1)
		if token.begins_with("[img"):
			key = ""
			for action in ["die", "bash", "move", "bow", "fire", "cannon", "stun", "shield", "mshield", "heart", "bomb", "push", "pull"]:
				if token.contains(GameIcons.action_path(StringName(action))) and not GameIcons.action_path(StringName(action)).is_empty():
					key = action
					break
		elif token == "⚔️": key = "bash"
		elif key == "flees": key = "flee"
		elif key == "friends": key = "friend"
		elif key == "returns": key = "return"
		elif key == "deploys": key = "deploy"
		elif key == "sacrificed": key = "sacrifice"
		elif key == "hits": key = "hit"
		elif key == "wounds": key = "wound"
		elif key == "embers": key = "ember"
		elif key == "projectiles": key = "projectile"
		if link_depth == 0 and ENTRIES.has(key):
			var display := token if token.begins_with("[img") or key == "bash" else "[u]%s[/u]" % token
			var guide_key := key
			if token.begins_with("[img"):
				var tags := RegEx.new()
				tags.compile("\\[[^\\]]*\\]")
				var prefix := tags.sub(text.substr(0, found.get_start()), "", true)
				var markers := RegEx.new()
				markers.compile("(?<![A-Za-z])(?:[XY])?([FPA]+)[ \\t]*$")
				var matched := markers.search(prefix)
				if matched != null: guide_key += ":" + matched.get_string(1)
			result += "[url=guide:%s]%s[/url]" % [guide_key, display]
		else: result += token
		offset = found.get_end()
	return result + text.substr(offset)

## Controller glossary requests resolve one icon/keyword plus only its displayed stickers, each on a separate line.
## Unknown metadata returns empty; standard entries and existing links keep their previous behavior.
static func description(key: String) -> String:
	var parts := key.split(":")
	if not ENTRIES.has(parts[0]): return ""
	var text: String = ENTRIES[parts[0]]
	if parts.size() > 1:
		for marker in ["F", "P", "A"]:
			if parts[1].contains(marker): text += "\n" + STICKERS[marker]
	return text
