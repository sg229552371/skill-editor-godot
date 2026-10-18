@tool
class_name PreviewLauncher
extends RefCounted

## UI-facing coordinator for deterministic preview runs.
## Runtime inputs are injected by the host; this class never constructs defaults
## and never mutates the author-owned CFG.

const REQUIRED_OPTIONS: Array = [
	"seed",
	"roots",
	"targets",
	"handlers",
	"template_families",
	"derivation_bindings",
]
const OPTIONAL_OPTIONS: Array = ["motion_inputs", "project_config"]

var _runner: Variant = null
var _running: bool = false
var _last_cfg: Variant = null
var _last_options: Dictionary = {}
var _last_error: String = ""


func configure(runner: Variant) -> Dictionary:
	if _running:
		return _fail("runner", "Stop the active preview before reconfiguring the runner")
	_runner = null
	_running = false
	_last_cfg = null
	_last_options = {}
	_last_error = ""
	if runner == null or not runner is Object:
		return _fail("runner", "A preview runner instance must be injected")
	for method_name in ["start", "stop"]:
		if not runner.has_method(method_name):
			return _fail("runner." + method_name, "Injected runner is missing " + method_name)
	_runner = runner
	return {"ok": true, "error": ""}


func launch(cfg: Variant, options: Dictionary) -> Dictionary:
	var ready: Dictionary = _require_runner()
	if not ready.is_empty():
		return ready
	if _running:
		return _fail("runner", "Stop the active preview before launching another")
	var checked: Dictionary = _validate_options(options)
	if not checked["ok"]:
		return checked
	var cfg_copy: Variant = _copy(cfg)
	var options_copy: Dictionary = options.duplicate(true)
	var result_value: Variant = _runner.call("start", cfg_copy, options_copy)
	if not result_value is Dictionary:
		return _fail("runner.start", "Preview runner returned a non-dictionary result")
	var result: Dictionary = result_value
	if result.get("ok", false) != true:
		_running = false
		_last_error = _runner_error(result)
		result["error"] = _last_error
		return result
	_running = true
	_last_cfg = _copy(cfg)
	_last_options = options_copy.duplicate(true)
	_last_error = ""
	return result


func switch_version(cfg: Variant, options: Dictionary) -> Dictionary:
	var ready: Dictionary = _require_runner()
	if not ready.is_empty():
		return ready
	var checked: Dictionary = _validate_options(options)
	if not checked["ok"]:
		return checked
	# A version switch is always a fresh run, even when the host did not track
	# an active run. The explicit stop is part of the observable contract.
	var was_running: bool = _running
	var stopped_value: Variant = _runner.call("stop")
	if not stopped_value is Dictionary:
		return _fail("runner.stop", "Preview runner returned a non-dictionary result")
	var stopped: Dictionary = stopped_value
	if stopped.get("ok", false) != true:
		_running = was_running
		_last_error = _runner_error(stopped)
		stopped["error"] = _last_error
		return stopped
	_running = false
	_last_cfg = null
	_last_options = {}
	return launch(cfg, options)


func stop() -> Dictionary:
	var ready: Dictionary = _require_runner()
	if not ready.is_empty():
		return ready
	var result_value: Variant = _runner.call("stop")
	if not result_value is Dictionary:
		return _fail("runner.stop", "Preview runner returned a non-dictionary result")
	var result: Dictionary = result_value
	if result.get("ok", false) == true:
		_running = false
		_last_cfg = null
		_last_options = {}
		_last_error = ""
	else:
		_last_error = _runner_error(result)
		result["error"] = _last_error
	return result


func is_running() -> bool:
	return _running


func get_last_error() -> String:
	return _last_error


func get_last_options() -> Dictionary:
	return _last_options.duplicate(true)


func _require_runner() -> Dictionary:
	if _runner == null:
		return _fail("runner", "A preview runner instance must be injected")
	return {}


func _validate_options(options: Dictionary) -> Dictionary:
	for key_value in options.keys():
		var key: String = str(key_value)
		if not REQUIRED_OPTIONS.has(key) and not OPTIONAL_OPTIONS.has(key):
			return _fail("options." + key, "Unregistered preview option: " + key)
	for key_value in REQUIRED_OPTIONS:
		var required_key: String = str(key_value)
		if not options.has(required_key):
			return _fail("options." + required_key, "Explicit preview option is required: " + required_key)
	var seed: Variant = options.get("seed", null)
	if not seed is int:
		return _fail("options.seed", "Explicit integer logic seed required")
	var shape_expectations: Dictionary = {
		"roots": TYPE_ARRAY,
		"targets": TYPE_ARRAY,
		"handlers": TYPE_DICTIONARY,
		"template_families": TYPE_DICTIONARY,
		"derivation_bindings": TYPE_DICTIONARY,
	}
	for key_value in shape_expectations.keys():
		var key: String = str(key_value)
		var value: Variant = options.get(key, null)
		var expected: int = int(shape_expectations[key])
		if expected == TYPE_ARRAY and not value is Array:
			return _fail("options." + key, "Expected explicit array")
		if expected == TYPE_DICTIONARY and not value is Dictionary:
			return _fail("options." + key, "Expected explicit dictionary")
	for key in OPTIONAL_OPTIONS:
		if not options.has(key):
			continue
		var optional_value: Variant = options.get(key, null)
		if not optional_value is Dictionary:
			return _fail("options." + key, "Expected explicit dictionary")
	return {"ok": true, "error": ""}


func _runner_error(result: Dictionary) -> String:
	var path: String = str(result.get("path", "runner"))
	var detail: String = str(result.get("error", "Preview runner rejected the request"))
	return path + ": " + detail


func _fail(path: String, detail: String) -> Dictionary:
	_last_error = path + ": " + detail
	return {"ok": false, "path": path, "error": _last_error, "diagnostics": []}


func _copy(value: Variant) -> Variant:
	if value is Dictionary or value is Array:
		return value.duplicate(true)
	return value
