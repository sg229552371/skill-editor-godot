extends RefCounted

## Capture starts at the already-started runner's tick zero, then advances one
## tick per sample. Numbers become JSON strings; the mandatory tick stays int.
## No identity rewriting: a difference in an instance ID is a real difference.
## runner_factory optionally supplies a fresh runner for the second replay.
## post_tick_hook(index, detached_sample, runner) is a trusted host/test hook;
## it may consume presentation_random(), but must not mutate runner internals.
var last_error: String = ""
var _ready: bool = false
var _max_ticks: int = 0
var _fields: Array = []
var _runner_options: Dictionary = {}
var _hook: Callable = Callable()
var _factory: Callable = Callable()


func configure(options: Dictionary = {}) -> Dictionary:
	_ready = false
	_max_ticks = 0
	_fields = []
	_runner_options = {}
	_hook = Callable()
	_factory = Callable()
	var limits: Variant = options.get("limits", null)
	if not limits is Dictionary:
		return _failure("Missing limits.max_trace_ticks")
	var maximum: Variant = limits.get("max_trace_ticks", null)
	if not (maximum is int or maximum is float):
		return _failure("limits.max_trace_ticks must be a positive integral number")
	var number: float = float(maximum)
	if not is_finite(number) or number < 1.0 or number >= 9223372036854775807.0 or number - floor(number) > 0.0:
		return _failure("limits.max_trace_ticks must be a finite positive integral number")
	_max_ticks = int(maximum)
	if options.has("trace_fields"):
		var fields: Variant = options["trace_fields"]
		if not fields is Array or fields.is_empty():
			return _failure("trace_fields must be a nonempty array of snapshot dictionary paths")
		for field in fields:
			if not field is String or field.is_empty():
				return _failure("trace_fields entries must be nonempty strings")
			for segment in field.split("."):
				if segment.is_empty() or segment.contains("[") or segment.contains("]"):
					return _failure("Invalid trace_fields path: " + field)
			if not _fields.has(field):
				_fields.append(field)
		_fields.sort()
	if options.has("runner_options"):
		if not options["runner_options"] is Dictionary:
			return _failure("runner_options must be a Dictionary")
		_runner_options = options["runner_options"].duplicate(true)
	for key in ["post_tick_hook", "runner_factory"]:
		if options.has(key):
			var callback: Variant = options[key]
			if not callback is Callable or not callback.is_valid():
				return _failure(key + " must be a valid Callable")
			if key == "post_tick_hook":
				_hook = callback
			else:
				_factory = callback
	_ready = true
	last_error = ""
	return {"ok": true, "error": ""}


func capture(runner: Variant, ticks: int) -> Dictionary:
	var trace: Array = []
	if not _ready:
		return _capture_failure("RunDiff.configure is required", trace)
	var error: String = _runner_error(runner)
	if not error.is_empty():
		return _capture_failure(error, trace)
	if ticks <= 0:
		return _capture_failure("ticks must be positive; received %d" % ticks, trace)
	var count: int = mini(ticks, _max_ticks)
	for index in range(count):
		if index > 0:
			var advanced: Variant = runner.call("advance_ticks", 1)
			error = _result_error(advanced, "advance_ticks")
			if not error.is_empty():
				return _capture_failure(error, trace)
		var snapshot: Variant = runner.call("snapshot_state")
		if not snapshot is Dictionary:
			return _capture_failure("snapshot_state must return a Dictionary", trace)
		var clock: Variant = snapshot.get("clock", null)
		var actual_tick: Variant = clock.get("tick", null) if clock is Dictionary else snapshot.get("tick", null)
		if not actual_tick is int or actual_tick != index:
			return _capture_failure("capture requires tick zero and one-tick progress: index=%d, snapshot tick=%s" % [index, str(actual_tick)], trace)
		var projected: Dictionary = _project(snapshot)
		if not projected["ok"]:
			return _capture_failure(projected["error"], trace)
		var encoded: Dictionary = _encode(projected["value"], "")
		if not encoded["ok"]:
			return _capture_failure(encoded["error"], trace)
		var sample: Dictionary = encoded["value"]
		sample["tick"] = index
		if _hook.is_valid():
			_hook.call(index, sample, runner)
			# Re-encode hook-added values and detach once more. tick is reserved.
			if not sample.get("tick", null) is int or sample["tick"] != index:
				return _capture_failure("post_tick_hook must not change tick at index %d" % index, trace)
			encoded = _encode(sample, "")
			if not encoded["ok"]:
				return _capture_failure(encoded["error"], trace)
			sample = encoded["value"]
			sample["tick"] = index
		trace.append(sample)
	last_error = ""
	return {"ok": true, "error": "", "trace": trace, "truncated": ticks > count,
		"requested_ticks": ticks, "captured_ticks": count}


func compare(trace_a: Array, trace_b: Array) -> Dictionary:
	if not _ready:
		return _comparison_failure("RunDiff.configure is required")
	if trace_a.size() != trace_b.size():
		return _comparison_failure("Trace lengths differ: left=%d, right=%d" % [trace_a.size(), trace_b.size()])
	if trace_a.is_empty():
		return _comparison_failure("Cannot certify empty traces (left=0, right=0)")
	# Validate every sample before certifying or returning a meaningful diff.
	for index in range(trace_a.size()):
		for sample in [trace_a[index], trace_b[index]]:
			if not sample is Dictionary or not sample.get("tick", null) is int or sample["tick"] != index:
				return _comparison_failure("trace[%d] requires tick:int equal to its zero-based index" % index)
			var encoded: Dictionary = _encode(sample, "")
			if not encoded["ok"]:
				return _comparison_failure(encoded["error"])
	for index in range(trace_a.size()):
		var difference: Dictionary = _first_difference(trace_a[index], trace_b[index], "trace[%d]" % index)
		if not difference.is_empty():
			last_error = ""
			return {"ok": true, "equal": false, "first_diff_index": index,
				"path": difference["path"], "left": difference["left"], "right": difference["right"], "error": ""}
	last_error = ""
	return {"ok": true, "equal": true, "first_diff_index": -1, "path": "", "left": null, "right": null, "error": ""}


func diff_runs(runner: Variant, cfg: Dictionary, ticks: int) -> Dictionary:
	if not _ready:
		return _comparison_failure("RunDiff.configure is required")
	var error: String = _runner_error(runner)
	if not error.is_empty():
		return _comparison_failure(error)
	if ticks <= 0:
		return _comparison_failure("ticks must be positive; received %d" % ticks)
	if not _runner_options.get("seed", null) is int:
		return _comparison_failure("diff_runs requires runner_options.seed:int")
	var traces: Array = []
	var truncated: bool = false
	for run_index in range(2):
		var current: Variant = runner
		if run_index == 1 and _factory.is_valid():
			current = _factory.call()
			error = _runner_error(current)
			if not error.is_empty():
				return _comparison_failure("runner_factory: " + error)
			if current == runner:
				return _comparison_failure("runner_factory must return a fresh runner")
		var stopped: Variant = current.call("stop")
		error = _result_error(stopped, "stop")
		if not error.is_empty():
			return _comparison_failure(error)
		# Never hand the caller's CFG or cached options to a runtime adapter.
		var started: Variant = current.call("start", cfg.duplicate(true), _runner_options.duplicate(true))
		error = _result_error(started, "start")
		if not error.is_empty():
			current.call("stop")
			return _comparison_failure("run[%d]: %s" % [run_index, error])
		var captured: Dictionary = capture(current, ticks)
		stopped = current.call("stop")
		if not captured["ok"]:
			return _comparison_failure("run[%d]: %s" % [run_index, captured["error"]])
		error = _result_error(stopped, "stop")
		if not error.is_empty():
			return _comparison_failure(error)
		truncated = captured["truncated"]
		traces.append(captured["trace"])
	var result: Dictionary = compare(traces[0], traces[1])
	result["trace_a"] = traces[0]
	result["trace_b"] = traces[1]
	result["truncated"] = truncated
	result["requested_ticks"] = ticks
	result["captured_ticks"] = traces[0].size()
	return result


func _runner_error(runner: Variant) -> String:
	var missing: PackedStringArray = []
	for method in ["start", "advance_ticks", "snapshot_state", "stop"]:
		if not runner is Object or not is_instance_valid(runner) or not runner.has_method(method):
			missing.append(method)
	return "runner missing methods: " + ", ".join(missing) if not missing.is_empty() else ""


func _result_error(result: Variant, method: String) -> String:
	if not result is Dictionary or not result.get("ok", null) is bool:
		return method + " must return {ok:bool, error?}"
	if not result["ok"]:
		return method + " failed: " + str(result.get("error", "no error detail"))
	return ""


func _project(snapshot: Dictionary) -> Dictionary:
	if _fields.is_empty():
		return {"ok": true, "value": snapshot}
	var result: Dictionary = {}
	for path in _fields:
		var source: Variant = snapshot
		var destination: Dictionary = result
		var segments: PackedStringArray = path.split(".")
		for index in range(segments.size()):
			var segment: String = segments[index]
			if not source is Dictionary or not source.has(segment):
				return {"ok": false, "error": "Missing trace_fields snapshot path: " + path}
			source = source[segment]
			if index == segments.size() - 1:
				destination[segment] = source
			else:
				var child: Variant = destination.get(segment, null)
				if not child is Dictionary:
					child = {}
					destination[segment] = child
				destination = child
	return {"ok": true, "value": result}


func _encode(value: Variant, path: String) -> Dictionary:
	if value is Dictionary:
		var result: Dictionary = {}
		var keys: Array = value.keys()
		# Snapshot keys must be textual; don't stringify arbitrary objects/keys.
		for key in keys:
			if not (key is String or key is StringName):
				return {"ok": false, "error": "Non-text dictionary key at " + path}
		keys.sort()
		for key in keys:
			var field_path: String = str(key) if path.is_empty() else path + "." + str(key)
			# Presentation state is not a logic trajectory. Do not omit logic_rng.
			if field_path == "clock.presentation_rng":
				continue
			var encoded: Dictionary = _encode(value[key], field_path)
			if not encoded["ok"]:
				return encoded
			result[str(key)] = encoded["value"]
		return {"ok": true, "value": result}
	if value is Array:
		var result: Array = []
		for index in range(value.size()):
			var encoded: Dictionary = _encode(value[index], "%s[%d]" % [path, index])
			if not encoded["ok"]:
				return encoded
			result.append(encoded["value"])
		return {"ok": true, "value": result}
	if value is Vector2:
		return _encode({"x": value.x, "y": value.y}, path)
	if value is Vector3:
		return _encode({"x": value.x, "y": value.y, "z": value.z}, path)
	if value is Color:
		return _encode({"r": value.r, "g": value.g, "b": value.b, "a": value.a}, path)
	if value is int or value is float:
		if value is float and not is_finite(value):
			return {"ok": false, "error": "Non-finite trajectory number at " + path}
		return {"ok": true, "value": JSON.stringify(value)}
	if value == null or value is bool or value is String or value is StringName:
		return {"ok": true, "value": str(value) if value is StringName else value}
	return {"ok": false, "error": "Unsupported trajectory value at %s (type=%d)" % [path, typeof(value)]}


func _first_difference(left: Variant, right: Variant, path: String) -> Dictionary:
	if left is Dictionary and right is Dictionary:
		var keys: Array = left.keys()
		for key in right:
			if not left.has(key):
				keys.append(key)
		keys.sort()
		for key in keys:
			var child_path: String = path + "." + str(key)
			if not left.has(key) or not right.has(key):
				return {"path": child_path, "left": left.get(key, null), "right": right.get(key, null)}
			var difference: Dictionary = _first_difference(left[key], right[key], child_path)
			if not difference.is_empty():
				return difference
		return {}
	if left is Array and right is Array:
		for index in range(maxi(left.size(), right.size())):
			var child_path: String = "%s[%d]" % [path, index]
			if index >= left.size() or index >= right.size():
				return {"path": child_path, "left": left[index] if index < left.size() else null,
					"right": right[index] if index < right.size() else null}
			var difference: Dictionary = _first_difference(left[index], right[index], child_path)
			if not difference.is_empty():
				return difference
		return {}
	# Compare serialized scalar values, never Variant float equality.
	if typeof(left) != typeof(right) or JSON.stringify(left) != JSON.stringify(right):
		return {"path": path, "left": left, "right": right}
	return {}


func _failure(error: String) -> Dictionary:
	last_error = error
	return {"ok": false, "error": error}


func _capture_failure(error: String, trace: Array) -> Dictionary:
	last_error = error
	return {"ok": false, "error": error, "trace": trace, "truncated": false, "captured_ticks": trace.size()}


func _comparison_failure(error: String) -> Dictionary:
	last_error = error
	return {"ok": false, "equal": false, "first_diff_index": -1, "path": "", "left": null, "right": null, "error": error}
