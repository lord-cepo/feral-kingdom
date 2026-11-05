## One named rule that changes how a specific action occurrence is paid or resolved.
class_name ActionSticker
extends RefCounted

enum Kind { INSTANT, PIERCE, TIRELESS, ACTION_FREE }

var kind: Kind

## Creates a sticker definition; card factories attach it to a Phrase, never to a shared Verb.
func _init(sticker_kind: Kind) -> void:
	kind = sticker_kind

## Returns the named sticker definitions represented by legacy factory options.
## Collection uses this while composing actions; returned objects are immutable definitions.
static func from_options(options: ActionStickers) -> Array[ActionSticker]:
	var result: Array[ActionSticker] = []
	if options == null: return result
	if options.instant: result.append(ActionSticker.new(Kind.INSTANT))
	if options.pierce: result.append(ActionSticker.new(Kind.PIERCE))
	if options.tireless: result.append(ActionSticker.new(Kind.TIRELESS))
	if options.action_free: result.append(ActionSticker.new(Kind.ACTION_FREE))
	return result
