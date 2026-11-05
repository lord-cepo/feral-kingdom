## A live contribution, never a counter mutation or a triggered action.
class_name StateModifier
extends RefCounted

var condition: Condition
var physical: int
var magical: int
var label: String

## Defines a live contribution; condition may be a Selector, Condition, or null for always-on.
## CardCatalogue attaches definitions to UnitInfo; values are derived on each state read.
func _init(when_any: RefCounted = null, physical_bonus: int = 0, magical_bonus: int = 0, description: String = "") -> void:
	if when_any is Selector: condition = Condition.Matches.new(when_any)
	elif when_any is Condition or when_any == null: condition = when_any
	else:
		condition = Condition.new()
		push_error("StateModifier requires a Condition, Selector or null.")
	physical = physical_bonus
	magical = magical_bonus
	label = description

## Returns this live contribution when its read-only Selector/Condition matches.
## UnitInfo.state_modifiers() calls it during a getter; it never changes counters or emits events.
func evaluate(ctx: RuleContext) -> Vector2i:
	if ctx == null: return Vector2i.ZERO
	if condition != null and not condition.test(ctx): return Vector2i.ZERO
	if not ctx.error.is_empty(): return Vector2i.ZERO
	# "While adjacent to a hero" contributes once, not once per adjacent hero.
	return Vector2i(physical, magical)

static func adjacent_to_hero(physical_bonus: int = 1, magical_bonus: int = 0) -> StateModifier:
	var heroes := QuerySelector.new(TargetRef.Kind.UNIT)
	heroes.type = Enum.type.HERO
	var adjacent := Selectors.UnitsOn.new(DistanceSelector.new(1)).where(heroes)
	return StateModifier.new(adjacent, physical_bonus, magical_bonus, "Adjacent to a hero")

## Creates the wounded-only +2 physical example used by Alps Lone Wolf.
## UnitInfo.state_modifiers() supplies SELF and reads the rule without accumulating it.
static func wounded_physical(physical_bonus: int = 2) -> StateModifier:
	return StateModifier.new(Condition.Wounded.new(), physical_bonus, 0, "Wounded")

## Creates an always-on contribution scoped to this deployed unit.
## UnitInfo.state_modifiers() already enforces the source's deployed lifetime.
static func permanent(physical_bonus: int = 0, magical_bonus: int = 0, description: String = "") -> StateModifier:
	return StateModifier.new(null, physical_bonus, magical_bonus, description)

## Rat Pikeman's derived physical bonus follows remaining deployment balances; negative differences remain negative and never become counters.
class DeploymentDifference extends StateModifier:
	## Catalogue supplies a label for hover text; evaluate receives the current unit owner through the normal RuleContext.
	func _init() -> void:
		super(null, 0, 0, "Physical = your deployments minus opponent deployments")
	## UnitInfo modifier reads evaluate both players live; control strength never reads this contribution.
	func evaluate(ctx: RuleContext) -> Vector2i:
		if ctx == null or ctx.source == null: return Vector2i.ZERO
		var owner := Match.owner_of(ctx.source)
		if owner not in [1, 2]: return Vector2i.ZERO
		return Vector2i(Match.players[owner].deployments_remaining - Match.players[3 - owner].deployments_remaining, 0)
