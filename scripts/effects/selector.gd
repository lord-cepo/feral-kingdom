class_name Selector
extends RefCounted

const CONTEXTUAL := -1

## Declares the native reference domain for TargetResolver validation; reads bindings only.
func output_kind(_ctx: RuleContext = null) -> int:
	return CONTEXTUAL

## Checks this definition and domain constraints before selection/payment; returns an error or empty string.
func validate(_ctx: RuleContext = null) -> String:
	return ""

## Returns current matching identities without mutation; TargetResolver/composition supplies the query bindings.
func resolve(_ctx: RuleContext) -> Array[TargetRef]:
	return []

func and_with(other: Selector) -> Selector:
	return Selectors.Group.new(self, other, false)

func or_with(other: Selector) -> Selector:
	return Selectors.Group.new(self, other, true)

func where(other: Selector) -> Selector:
	return and_with(other)
