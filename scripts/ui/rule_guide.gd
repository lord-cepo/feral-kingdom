## Shared presentation glossary: hover labels decorate words/images and the controller displays these entries while Ctrl is held.
class_name RuleGuide
extends RefCounted

const STICKERS := {
	"F": "Instant",
	"P": "Pierce ignores defense modifiers",
	"A": "spends one action",
}

const ENTRIES := {
	"first strike": "First Strike — strike first in Bash. If both have it, the attacker goes first.",
	"steady": "Steady — ignore the opponent’s physical modifier in Bash.",
	"fast": "Fast — resolve a new Bash in the action’s Combat window.",
	"titanium": "Titanium — prevents physical contact, including Pierce.",
	"obsidian": "Obsidian — prevents magical contact unless the attack has Pierce.",
	"end": "End — resolve End effects, activate eligible units, then clean up.",
	"friend": "Friend — your deployed unit, unless another zone is stated.",
	"it": "It: the trigger's subject.",
	"target": "Target: the trigger's object.",
	"itself": "Itself: this unit.",
	"friendly": "Friendly — belongs to you. Defaults to deployed units.",
	"wild": "Wild — a unit with Wild in its name, ignoring case.",
	"disable": "Disable — defeat a unit in hand without triggering Death.",
	"reset": "Reset — restore printed health and abilities. Clear acquired changes.",
	"deploy": "Deploy — spend a deployment and action to place a unit on a vacant hex you control.",
	"revive": "Revive: return another friendly defeated non-hero to hand at printed state and full printed health.",
	"flee": "Flee — take a free Walk or Fly, or Walk up to a fixed distance when specified. Leaving a Bash dodges the encounter.",
	"upgrade": "Upgrade — choose a unit and ability. M Upgrade N adds +M/+N until Reset.",
	"return": "Return — put the unit in its owner’s hand at printed state.",
	"c": "C — Cost: pay the written cost and spend an action.",
	"ac": "AC — Additional cost: self-Stun as for a normal action, in addition to the written cost.",
	"a": "[A]: spend one player action plus written costs; no implicit self-Stun.",
	"s": "[S]: become inactive and gain one Stun, plus written costs; no player action.",
	"as": "[AS]: spend one action and pay ordinary self-Stun plus written costs. Default for unmarked actions.",
	"2s": "[2S]: pay two self-Stun instead of one, without spending a player action.",
	"a2s": "[A2S]: spend one action and pay two self-Stun.",
	"sacrifice": "Sacrifice — defeat a chosen deployed friend to pay a cost.",
	"ember": "Ember — spend all Ember on your next Fire for +1 damage each.",
	"projectile": "Projectile — ammunition spent when the action calls for it.",
	"control": "Control counters add to a unit's regional strength, separately from physical protection.",
	"hit": "Hit: actual physical or magical attack contact, including zero damage; misses and immunity do not count.",
	"wound": "Wound: positive life loss from attack contact. Nonlethal Fire creates Hit without Wound.",
	"attacks": "Attacks: starts a Bash or uses Bow, Fire or Cannon. The trigger watches the declaration.",
	"die": "Death: the unit is defeated. Its death triggers are captured before it leaves the board.",
	"bash": "Bash: opposing units share a hex. The unit that entered is the attacker; the other is the defender.",
	"move": "Walk: follow a legal route up to the shown distance. A unit moves when it Walks or Flies on its own.",
	"bow": "Bow: a physical ranged attack. The left number is damage; the right is range.",
	"fire": "Fire — resolves in opposing Combat. Survivors lose no life.",
	"cannon": "Cannon: a magical attack along a straight line, potentially hitting either player's units.",
	"stun": "Stun — deactivate and block activation. Your hero removes one at your Start.",
	"shield": "Shield: stored physical protection counters. Physical contact clears them, even at zero damage.",
	"mshield": "Mshield: stored magical protection counters. Magical contact clears them, even at zero damage.",
	"heart": "Life — current health on the left, maximum health on the right.",
	"bomb": "Bomb: Fire ignites it, spreading blasts radially to affected hexes.",
	"shifted": "Is moved — another unit causes a position change, such as Push, Pull or a card effect.",
	"push": "Push: choose a target within range on a straight hex line from the acting unit. Move it farther away along that line.",
	"pull": "Pull: choose a target within range on a straight hex line from the acting unit. Move it toward the acting unit along that line.",
}

## Controller hover labels call this once on creation; BBCode tags/asset paths stay intact and existing links are never nested.
## Keyword links include named passives and attack declarations; icon entries share GameIcons' asset vocabulary.
## Sticker letters immediately preceding an icon are captured in its guide metadata, keeping each attack's explanation local to that occurrence.
## Bracketed A/S cost markers link independently; ordinary English articles are not mistaken for action costs.
## Unit and trigger hover cards supply the rule owner's player ID for enemy colors.
static func decorate(text: String, owner: int = 0) -> String:
	var regex := RegEx.new()
	regex.compile("\\[img[^\\]]*\\][^\\[]+\\[/img\\]|\\[[^\\]]*\\]|(?<=\\[lb\\])(?i:A2S|2S|AS|A|S)(?=\\[rb\\])|\\b(?i:enem(?:y|ies)|first strike|steady|fast|titanium|obsidian|upgrade|disable|reset|sacrific(?:e|ed)|embers?|projectiles?|control|attacks|hits?|wounds?|deploys?|revive|flees?|returns?|friends?|friendly|wild|itself|it|target|End|AC|C)\\b|⚔️")
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
		if key in ["enemy", "enemies"] and owner in [1, 2]:
			result += EffectText._owner_color(token, 3 - owner)
		elif link_depth == 0 and ENTRIES.has(key):
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

## Controller glossary requests resolve one icon or keyword and append a compact list of its displayed stickers.
## Unknown metadata returns empty; standard entries and existing links keep their previous behavior.
static func description(key: String) -> String:
	var parts := key.split(":")
	if not ENTRIES.has(parts[0]): return ""
	var text: String = ENTRIES[parts[0]]
	if parts.size() > 1:
		var stickers := PackedStringArray()
		for marker in ["F", "P", "A"]:
			if parts[1].contains(marker): stickers.append(STICKERS[marker])
		if not stickers.is_empty(): text += " · " + ", ".join(stickers)
	return text
