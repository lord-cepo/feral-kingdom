class_name Selector
extends RefCounted

const CONTEXTUAL := -1
enum Membership { UNKNOWN, EXCLUDED, INCLUDED }

## Declares the native reference domain for TargetResolver validation; reads bindings only.
func output_kind(_ctx: RuleContext = null) -> int:
	return CONTEXTUAL

## Checks this definition and domain constraints before selection/payment; returns an error or empty string.
func validate(_ctx: RuleContext = null) -> String:
	return ""

## Returns current matching identities without mutation; TargetResolver/composition supplies the query bindings.
func resolve(_ctx: RuleContext) -> Array[TargetRef]:
	return []

## Answers whether one native candidate is selected, when the answer does not require a full query.
## TargetResolver calls this after definition and domain validation. UNKNOWN requests the full resolve().
func membership(_candidate: TargetRef, _ctx: RuleContext) -> Membership:
	return Membership.UNKNOWN

## Answers an existence query for native candidates in a read-only context.
## TargetResolver calls this after validation. UNKNOWN retains ordinary full resolution.
func any_native(_ctx: RuleContext, _accept: Callable) -> Membership:
	return Membership.UNKNOWN

func and_with(other: Selector) -> Selector:
	return Selectors.Group.new(self, other, false)

func or_with(other: Selector) -> Selector:
	return Selectors.Group.new(self, other, true)

func where(other: Selector) -> Selector:
	return and_with(other)
