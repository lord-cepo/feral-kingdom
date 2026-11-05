## Typed output of a card-owned continuous rule; it never stores activation state.
class_name Contribution
extends RefCounted

enum Kind { MODIFIER, PASSIVE, ACTION_VALUE, SUPPRESS_DEFEAT_TRIGGERS, EXTRA_DEATH_TRIGGER, PLAYER_ACTIONS, SUPPRESS_DEPLOY_TRIGGERS }
var extra_triggers := 0
var actions := 0

## Pikeman grants a live player action allowance, not repeatable resource mutations on state reads.
static func player_actions(amount: int = 1) -> Contribution:
	var result := Contribution.new()
	result.kind = Kind.PLAYER_ACTIONS
	result.actions = amount
	return result

## Sentinel suppresses all abilities caused by a selected unit's Deploy occurrence, regardless of watcher ownership.
static func suppress_deploy() -> Contribution:
	var result := Contribution.new()
	result.kind = Kind.SUPPRESS_DEPLOY_TRIGGERS
	return result

var kind: Kind
var physical := 0
var magical := 0
var property: StringName = &""
var action_family: StringName = &""
var parameters: Array[int] = []

## Builds a live physical/magical modifier contribution for a selected recipient.
static func modifiers(physical_value: int = 0, magical_value: int = 0) -> Contribution:
	var result := Contribution.new()
	result.kind = Kind.MODIFIER
	result.physical = physical_value
	result.magical = magical_value
	return result

## Grants a temporary passive flag; UnitInfo combines this with printed and stored flags.
static func passive_flag(key: StringName) -> Contribution:
	var result := Contribution.new()
	result.kind = Kind.PASSIVE
	result.property = key
	return result

## Adjusts effective Bow parameters without changing the reusable action definition.
static func bow_values(damage: int = 0, bow_range: int = 0) -> Contribution:
	return action_values(&"bow", [damage, bow_range])

## Adjusts the named action's numeric parameters by index; unspecified values are zero.
## UnitInfo applies these to current card values without mutating the action definition.
static func action_values(family: StringName, values: Array[int]) -> Contribution:
	var result := Contribution.new()
	result.kind = Kind.ACTION_VALUE
	result.action_family = family
	result.parameters = values.duplicate()
	return result

## Filters triggers caused by a selected recipient's defeat while the source is live.
static func hushbringer() -> Contribution:
	var result := Contribution.new()
	result.kind = Kind.SUPPRESS_DEFEAT_TRIGGERS
	return result

## Wild Rat's live friendly aura adds captured death activations, rather than emitting fictional deaths or mutating a reusable trigger.
static func extra_death_trigger(amount: int = 1) -> Contribution:
	var result := Contribution.new()
	result.kind = Kind.EXTRA_DEATH_TRIGGER
	result.extra_triggers = amount
	return result
