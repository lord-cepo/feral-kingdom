## Small value network loaded by the headless self-play driver.
extends RefCounted

var _mean: Array
var _scale: Array
var _weights: Array
var _bias: Array
var _output: Array
var _intercept := 0.0
var _normalized_limit := INF


## Loads the trainer's JSON export and rejects a checkpoint with a different
## feature width or incompatible hidden layer before any game starts.
func load_checkpoint(path: String, feature_count: int) -> bool:
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary: return false
	for key in ["mean", "scale", "weights", "bias", "output"]:
		if not data.get(key) is Array: return false
	if not data.get("intercept") is float: return false
	var hidden_count: int = data.bias.size()
	if data.mean.size() != feature_count or data.scale.size() != feature_count \
			or data.weights.size() != feature_count or hidden_count == 0 or data.output.size() != hidden_count:
		return false
	for index in feature_count:
		if not data.weights[index] is Array or data.weights[index].size() != hidden_count \
				or float(data.scale[index]) <= 0.0:
			return false
	_mean = data.mean
	_scale = data.scale
	_weights = data.weights
	_bias = data.bias
	_output = data.output
	_intercept = data.intercept
	_normalized_limit = float(data.get("normalized_limit", INF))
	if _normalized_limit <= 0.0: return false
	return true


## Returns the predicted outcome on [-1, 1] for the feature owner's seat.
## The driver converts both seat predictions into one player-one value.
func value(features: Array) -> float:
	var hidden := _bias.duplicate()
	for feature in features.size():
		var normalized := (float(features[feature]) - float(_mean[feature])) / float(_scale[feature])
		normalized = clampf(normalized, -_normalized_limit, _normalized_limit)
		for neuron in hidden.size():
			hidden[neuron] += normalized * float(_weights[feature][neuron])
	var logit := _intercept
	for neuron in hidden.size():
		logit += tanh(float(hidden[neuron])) * float(_output[neuron])
	return tanh(logit * 0.5)
