## Shared PixelLab icon vocabulary for RichTextLabel descriptions, board stats and plain Button textures.
class_name GameIcons
extends RefCounted

const ROOT := "res://assets/icons/ui/"

## HexCell and LocalMatchController share these fallback glyphs when no PixelLab icon is available.
## Returns an empty string for unknown actions; callers keep their own BBCode/plain-button formatting.
static func fallback_glyph(action: StringName) -> String:
	match action:
		&"move": return "🥾"
		&"fly": return "🪽"
		&"bash": return "⚔️"
		&"bow": return "🏹"
		&"fire": return "🔥"
		&"cannon": return "🧨"
		&"gore": return "🐏"
		&"shield", &"mshield": return "🛡️"
		&"push", &"push_bomb": return "🫸"
		&"pull", &"pull_bomb": return "🫷"
		&"stun": return "🚫"
		&"mend": return "❤️"
		&"bomb_throw", &"bomb_defuse", &"bomb_light": return "💣"
		&"revive": return "👼"
	return ""

## Presentation callers use tightly cropped assets with preserved aspect ratios; life/mend selects its owner's smaller heart.
## Shield uses steel; Mshield uses the user's purple PixelLab barrier, cropped/resized to the shared text height.
## Move uses the cropped boot and Cannon its side-view cannon; Fly retains its separate existing symbol.
## Push/Pull use PixelLab action-icon frames in info panels and buttons; Pull uses a horizontally mirrored UI copy.
## Die uses a tightly cropped UI copy of the PixelLab skull frame across event and consequence descriptions.
## Bash uses the cropped PixelLab crossed-weapons object, shared by rule text and glossary metadata.
## Unknown actions return an empty path, preserving the existing fallback vocabulary.
static func action_path(action: StringName, owner: int = 1) -> String:
	match action:
		&"bash": return ROOT + "bash.png"
		&"die": return ROOT + "skull.png"
		&"push": return "res://assets/effects/push-icons/frame_0.png"
		&"pull": return ROOT + "pull.png"
		&"move": return ROOT + "boot.png"
		&"cannon": return ROOT + "cannon.png"
		&"bow", &"upgrade_bow": return ROOT + "bow.png"
		&"fire": return ROOT + "fire.png"
		&"shield": return ROOT + "shield.png"
		&"mshield": return ROOT + "mshield.png"
		&"stun", &"self_stun": return ROOT + "stun.png"
		&"mend", &"up_life", &"heart": return ROOT + ("heart-blue.png" if owner == 2 else "heart-red.png")
		&"bomb_throw", &"bomb_light", &"bomb_defuse", &"push_bomb", &"pull_bomb", &"bomb": return ROOT + "bomb-unlit.png"
	return ""

## HexCell and EffectText call this for inline images; descriptions always show an unlit bomb, even for Light.
## Descriptions default to 32px; board rows request 48px so their pixel symbols stay legible at camera scale.
## Skull and Bash keep their original 32px source scale after cropping, removing padding without enlarging the visible glyph.
## Push/Pull frames normalize to the requested size; prepared UI art fits within 48px with a smaller heart; scale both dimensions together to preserve proportions and tight side gutters.
static func bb(action: StringName, owner: int = 1, size: int = 32) -> String:
	var path := action_path(action, owner)
	if path.is_empty(): return ""
	var icon: Texture2D = load(path)
	var base_size := float(maxi(icon.get_width(), icon.get_height())) if action in [&"push", &"pull"] else (32.0 if action in [&"die", &"bash"] else 48.0)
	var width := roundi(icon.get_width() * float(size) / base_size)
	var height := roundi(icon.get_height() * float(size) / base_size)
	return "[img=%dx%d]%s[/img]" % [width, height, path]

## LocalMatchController supplies this texture to plain action Buttons, which cannot interpret BBCode.
static func texture(action: StringName, owner: int = 1) -> Texture2D:
	var path := action_path(action, owner)
	return load(path) if not path.is_empty() else null
