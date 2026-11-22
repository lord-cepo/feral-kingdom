extends RefCounted

class SearchNode:
	var visits := 0
	var total := 0.0
	var children: Dictionary[int, SearchNode] = {}
	var options: Array = []
	var order: Array[int] = []
	var opened := 0

var rng := RandomNumberGenerator.new()
const EXPLORATION := 1.41421356237
const ROLLOUT_LIMIT := 512

## Searches one live decision for the self-play driver. restore() resets to the root and
## returns its current decision. advance() consumes an option and returns the next decision.
## An optional rollout callback plays from the first expanded decision and returns its step count.
## The caller restores the actual match again before playing the returned option.
## Explored root indices include actions tried in incomplete simulations.
## A complete preferred order guides root expansion. ranker runs when search
## first selects from a live interior decision and may decline unsupported types.
## evaluate supplies a bounded player-one value after a truncated rollout.
func search(root: Dictionary, budget: int, restore: Callable, advance: Callable, winner: Callable,
		rollout: Callable = Callable(), preferred: Array[int] = [], ranker: Callable = Callable(),
		evaluate: Callable = Callable(), horizon: int = ROLLOUT_LIMIT) -> Dictionary:
	var tree := SearchNode.new()
	tree.options = root.options
	tree.order = preferred
	var completed := 0
	var simulated_steps := 0
	var estimated := 0
	for simulation in budget:
		var current: Dictionary = restore.call()
		if current != root: return {}
		var node := tree
		var path: Array[SearchNode] = []
		var owners: Array[int] = []
		while not current.is_empty():
			if node != tree and node.opened == 0 and ranker.is_valid() and node.options.size() > 1:
				node.order = ranker.call(current)
			var index := _select(node)
			var fresh := not node.children.has(index)
			if fresh: node.children[index] = SearchNode.new()
			var child := node.children[index]
			path.append(child)
			owners.append(current.player)
			current = advance.call(current.options[index])
			simulated_steps += 1
			node = child
			if fresh:
				if not current.is_empty(): node.options = current.options
				break
			if not current.is_empty() and current.options != node.options: return {}
		if rollout.is_valid():
			simulated_steps += int(rollout.call(current, rng, horizon))
		else:
			for step in horizon:
				if current.is_empty(): break
				current = advance.call(current.options[rng.randi_range(0, current.options.size() - 1)])
				simulated_steps += 1
		var victor: int = winner.call()
		var value := 0.0
		if victor != 0:
			completed += 1
			value = 1.0 if victor == 1 else -1.0
		elif evaluate.is_valid():
			estimated += 1
			value = clampf(float(evaluate.call()), -0.65, 0.65)
		else:
			continue
		tree.visits += 1
		for index in path.size():
			path[index].visits += 1
			path[index].total += value if owners[index] == 1 else -value
	var counts: Array[int] = []
	var best := rng.randi_range(0, root.options.size() - 1) if preferred.is_empty() else preferred[0]
	for index in root.options.size():
		counts.append(tree.children[index].visits if tree.children.has(index) else 0)
		if preferred.is_empty() and tree.children.has(index) and counts[index] > (tree.children[best].visits if tree.children.has(best) else 0):
			best = index
	for index in preferred:
		if counts[index] > counts[best] or (counts[index] > 0 and counts[index] == counts[best] \
				and tree.children[index].total > tree.children[best].total):
			best = index
	var advantage := 0.0
	if not preferred.is_empty() and counts[best] > 0 and counts[preferred[0]] > 0:
		advantage = tree.children[best].total / counts[best] - tree.children[preferred[0]].total / counts[preferred[0]]
	return {"index": best, "visits": counts, "completed": completed, "steps": simulated_steps,
		"estimated": estimated, "explored": tree.children.keys(), "advantage": advantage}


## Selects one edge for search(). Randomize unexplored edges to avoid catalogue-order bias.
## Values belong to the player who made the parent decision, including consecutive same-owner choices.
## A ranked node starts with one action and admits another after 1, 4, 9, ...
## selection attempts, including truncated simulations that gave no result.
func _select(node: SearchNode) -> int:
	var ranked := not node.order.is_empty()
	var size := mini(node.order.size(), 1 + int(sqrt(node.opened))) if ranked else node.options.size()
	node.opened += 1
	var offset := 0 if ranked else rng.randi_range(0, size - 1)
	var best := node.order[0] if ranked else offset
	var best_score := -INF
	for slot in size:
		var index := node.order[slot] if ranked else (slot + offset) % size
		if not node.children.has(index) or (not ranked and node.children[index].visits == 0):
			return index
	for slot in size:
		var index := node.order[slot] if ranked else (slot + offset) % size
		if node.children[index].visits == 0: return index
		var edge := node.children[index]
		var score := edge.total / edge.visits + EXPLORATION * sqrt(log(node.visits + 1.0) / edge.visits)
		if score > best_score:
			best_score = score
			best = index
	return best
