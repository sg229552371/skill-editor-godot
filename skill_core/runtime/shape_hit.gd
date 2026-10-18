class_name RuntimeShapeHit extends RefCounted

## One instance per effect body. Runtime ledgers are never written into CFG.
const BodyScript = preload("res://skill_core/runtime/effect_body.gd")
const META_PATH: String = "res://data/shape_hit_meta.json"

## 待素材抽取后替换：仅供显式注入的过渡表；默认路径失败绝不回退到此表。
## TODO(U-T043-geometry): wedge full-angle / flat line / centered rectangle are
## explicit point-geometry conventions pending review, not newly frozen CFG.
const PROVISIONAL_META: Dictionary = {
	"geometry_shape_field": "shape",
	"shapes": {
		"circle": {"kernel": "disk", "arguments": ["radius"]},
		"sector": {"kernel": "wedge", "arguments": ["radius", "sector_angle"]},
		"line": {"kernel": "forward_box", "arguments": ["length", "width"]},
		"rectangle": {"kernel": "centered_box", "arguments": ["length", "width"]},
	},
	"geometry_fields": {
		"shape": {"type": "string", "enum": ["circle", "sector", "line", "rectangle"]},
		"radius": {"type": "number", "exclusiveMinimum": 0},
		"sector_angle": {"type": "number", "exclusiveMinimum": 0, "maximum": 100, "default": 25},
		"length": {"type": "number", "exclusiveMinimum": 0},
		"width": {"type": "number", "exclusiveMinimum": 0},
		"wavefront_start_radius": {"type": "number", "minimum": 0},
		"wavefront_end_radius": {"type": "number", "exclusiveMinimum": 0},
		"wavefront_speed": {"type": "number", "exclusiveMinimum": 0},
		"area_profile": {"type": "string", "runtime_adapter_required": true},
	},
	"hit_policy_fields": {
		"per_target_limit": {"type": "integer", "minimum": 1, "default": 1},
		"rehit_interval_ticks": {"type": "integer", "minimum": 1},
		"max_hits": {"type": "integer", "minimum": 1},
	},
	"hit_policy_required": ["per_target_limit"],
	"policy_roles": {"target_limit": "per_target_limit", "interval": "rehit_interval_ticks", "hit_limit": "max_hits"},
	"hit_event": "hit",
}
const META_SECTIONS: Dictionary = {
	"shapes": TYPE_DICTIONARY,
	"geometry_fields": TYPE_DICTIONARY,
	"hit_policy_fields": TYPE_DICTIONARY,
	"hit_policy_required": TYPE_ARRAY,
	"geometry_shape_field": TYPE_STRING,
	"policy_roles": TYPE_DICTIONARY,
	"hit_event": TYPE_STRING,
}

static var _meta_cache: Dictionary = {}
var last_error: String = ""
var _meta: Dictionary = {}
var _meta_error: String = ""
var _adapter_error: String = ""
var _ready: bool = false
var _body: RefCounted
var _clock: RefCounted
var _geometry: Dictionary = {}
var _policy: Dictionary = {}
var _arguments: Array = []
var _kernel: Callable
var _kernels: Dictionary = {}
var _resolver: Callable
var _target_limit: int = 0
var _interval: int = 0
var _hit_limit: int = 0
var _targets: Dictionary = {}
var _candidate_count: int = 0
var _hit_count: int = 0
var _last_tick: int = -1


func _init(metadata_path: String = META_PATH, metadata_override: Variant = null):
	var candidate: Variant = metadata_override
	if candidate == null:
		if not _meta_cache.has(metadata_path):
			var loaded: Dictionary = _read_metadata(metadata_path)
			_meta_cache[metadata_path] = loaded
		var cached: Dictionary = _meta_cache[metadata_path]
		_meta_error = cached["error"]
		candidate = cached["metadata"]
	if _meta_error.is_empty():
		_meta_error = _metadata_error(candidate)
	if _meta_error.is_empty():
		_meta = candidate.duplicate(true)
	last_error = _meta_error


static func _read_metadata(path: String) -> Dictionary:
	if not path.begins_with("res://data/") or not FileAccess.file_exists(path):
		return {"metadata": null, "error": "Shape/hit metadata missing or outside res://data/: " + path}
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"metadata": null, "error": "Cannot open shape/hit metadata: " + path}
	var parser: JSON = JSON.new()
	var status: Error = parser.parse(file.get_as_text())
	if status != OK:
		return {"metadata": null, "error": "Invalid shape/hit JSON: %s: %s" % [path, parser.get_error_message()]}
	var error: String = _metadata_error(parser.data)
	return {"metadata": parser.data, "error": "" if error.is_empty() else path + ": " + error}


static func _metadata_error(candidate: Variant) -> String:
	if not candidate is Dictionary:
		return "Shape/hit metadata must be an object"
	for section in META_SECTIONS:
		if not candidate.has(section) or typeof(candidate[section]) != META_SECTIONS[section]:
			return "Missing or invalid shape/hit metadata section: " + str(section)
	for section in ["shapes", "geometry_fields", "hit_policy_fields", "hit_policy_required", "policy_roles"]:
		if candidate[section].is_empty():
			return "Empty shape/hit metadata section: " + str(section)
	var supported_types: Array = ["number", "integer", "string"]
	for section in ["geometry_fields", "hit_policy_fields"]:
		var definitions: Dictionary = candidate[section]
		for key in definitions:
			var definition: Variant = definitions[key]
			if not definition is Dictionary or not supported_types.has(definition.get("type", null)):
				return "Invalid metadata field definition: " + str(key)
			for bound in ["minimum", "exclusiveMinimum", "maximum"]:
				if definition.has(bound) and (definition["type"] == "string" or not _finite_number(definition[bound])):
					return "Invalid metadata numeric bound: " + str(key)
			if definition.has("enum") and (not definition["enum"] is Array or definition["enum"].is_empty()):
				return "Invalid metadata enum: " + str(key)
	var geometry_fields: Dictionary = candidate["geometry_fields"]
	var shape_field: String = candidate["geometry_shape_field"]
	if not geometry_fields.has(shape_field) or geometry_fields[shape_field]["type"] != "string":
		return "Missing shape selector definition"
	var shapes: Dictionary = candidate["shapes"]
	var allowed: Variant = geometry_fields[shape_field].get("enum", null)
	if not allowed is Array or allowed.size() != shapes.size():
		return "Shape enum and kernel bindings disagree"
	var arities: Dictionary = {"disk": 1, "wedge": 2, "forward_box": 2, "centered_box": 2}
	for name in shapes:
		var binding: Variant = shapes[name]
		if not allowed.has(name) or not binding is Dictionary:
			return "Invalid shape metadata binding: " + str(name)
		var kernel: Variant = binding.get("kernel", null)
		var keys: Variant = binding.get("arguments", null)
		if not kernel is String or not arities.has(kernel) or not keys is Array:
			return "Invalid or unimplemented geometry kernel: " + str(name)
		if keys.size() != arities[kernel]:
			return "Wrong geometry kernel arity: " + str(name)
		for key in keys:
			if not geometry_fields.has(key) or geometry_fields[key]["type"] != "number":
				return "Unregistered numeric geometry argument: " + str(key)
	var policy_fields: Dictionary = candidate["hit_policy_fields"]
	var roles: Dictionary = candidate["policy_roles"]
	for role in ["target_limit", "interval", "hit_limit"]:
		var field: Variant = roles.get(role, null)
		if not field is String or not policy_fields.has(field) or policy_fields[field]["type"] != "integer":
			return "Missing integer hit-policy role: " + str(role)
		if not policy_fields[field].has("minimum") or policy_fields[field]["minimum"] < 1:
			return "Hit-policy role must have a positive minimum: " + str(role)
	var required: Array = candidate["hit_policy_required"]
	if not required.has(roles["target_limit"]):
		return "Target quota must be required in metadata"
	for key in required:
		if not policy_fields.has(key):
			return "Unregistered required hit-policy field: " + str(key)
	if candidate["hit_event"].is_empty():
		return "Empty hit event binding"
	return ""


## resolver(target, logic_rng) -> bool: T-044 supplies the all-parts evasion
## decision. No resolver means deterministic hit. No presentation RNG is passed.
func configure(template: Dictionary, body: RefCounted, clock: RefCounted, resolver: Callable = Callable()) -> bool:
	if not _meta_error.is_empty():
		return _fail(_meta_error)
	if _ready:
		return _fail("Shape/hit is already configured")
	if body == null or clock == null or not body.is_alive():
		return _fail("A live effect body and clock are required")
	if not template.get("geometry", null) is Dictionary or not template.get("hit_policy", null) is Dictionary:
		return _fail("geometry and hit_policy must be objects")
	var geometry: Dictionary = template["geometry"].duplicate(true)
	var policy: Dictionary = template["hit_policy"].duplicate(true)
	var shape_field: String = _meta["geometry_shape_field"]
	var shape_name: Variant = geometry.get(shape_field, null)
	var shapes: Dictionary = _meta["shapes"]
	if not shape_name is String or not shapes.has(shape_name):
		return _fail("Missing or unregistered geometry shape")
	_kernels = {"disk": _disk, "wedge": _wedge, "forward_box": _forward_box, "centered_box": _centered_box}
	var binding: Dictionary = shapes[shape_name]
	if not _kernels.has(binding["kernel"]):
		return _fail("Unimplemented geometry kernel: " + str(binding["kernel"]))
	var fields: Dictionary = _meta["geometry_fields"]
	var argument_keys: Array = binding["arguments"]
	for key in argument_keys:
		var definition: Dictionary = fields[key]
		if not geometry.has(key) and definition.has("default"):
			geometry[key] = definition["default"]
		if not geometry.has(key):
			return _fail("Missing geometry field: " + str(key))
	if not _validate_fields(geometry, fields, "geometry"):
		return false
	# Required is checked before defaults: a schema default is not permission
	# to accept a missing per-target quota at this runtime boundary.
	for key in _meta["hit_policy_required"]:
		if not policy.has(key):
			return _fail("Missing hit_policy field: " + str(key))
	if not _validate_fields(policy, _meta["hit_policy_fields"], "hit_policy"):
		return false
	var roles: Dictionary = _meta["policy_roles"]
	_target_limit = int(policy[roles["target_limit"]])
	_interval = int(policy.get(roles["interval"], 0))
	_hit_limit = int(policy.get(roles["hit_limit"], 0))
	_geometry = geometry
	_policy = policy
	_arguments.clear()
	for key in argument_keys:
		_arguments.append(float(geometry[key]))
	_kernel = _kernels[binding["kernel"]]
	_body = body
	_clock = clock
	_resolver = resolver
	_ready = true
	last_error = ""
	return true


func _validate_fields(values: Dictionary, definitions: Dictionary, prefix: String) -> bool:
	var validators: Dictionary = {"number": _finite_number, "integer": _integer, "string": _string}
	for key in values:
		if not definitions.has(key):
			return _fail("Unknown " + prefix + " field: " + str(key))
		var definition: Dictionary = definitions[key]
		var validator: Callable = validators[definition["type"]]
		var value: Variant = values[key]
		if not validator.call(value):
			return _fail("Invalid " + prefix + "." + str(key) + " type/value")
		if definition.has("enum") and not definition["enum"].has(value):
			return _fail("Unregistered " + prefix + "." + str(key))
		if definition.has("minimum") and value < definition["minimum"]:
			return _fail("Below minimum: " + prefix + "." + str(key))
		if definition.has("exclusiveMinimum") and value <= definition["exclusiveMinimum"]:
			return _fail("Below exclusive minimum: " + prefix + "." + str(key))
		if definition.has("maximum") and value > definition["maximum"]:
			return _fail("Above maximum: " + prefix + "." + str(key))
		if definition.get("runtime_adapter_required", false):
			return _fail("Unresolved runtime adapter: " + prefix + "." + str(key))
	return true


## Point targets; all edges are closed. Position and direction are runtime
## transforms, not extra CFG keys. Direction is normalized before projection.
func contains_point(point: Vector2, position: Vector2 = Vector2.ZERO, direction: Vector2 = Vector2.RIGHT) -> bool:
	if not _ready:
		return _fail("Shape/hit is not configured")
	if not point.is_finite() or not position.is_finite() or not direction.is_finite() or direction.is_zero_approx():
		return _fail("Geometry requires finite vectors and a nonzero direction")
	var heading: Vector2 = direction.normalized()
	var offset: Vector2 = point - position
	var local: Vector2 = Vector2(offset.dot(heading), offset.dot(heading.orthogonal()))
	return _kernel.call(local, _arguments)


func _disk(point: Vector2, args: Array) -> bool:
	return point.length_squared() <= float(args[0]) * float(args[0])


func _wedge(point: Vector2, args: Array) -> bool:
	if not _disk(point, args):
		return false
	# sector_angle is the full opening in degrees; apex belongs to the shape.
	return absf(atan2(point.y, point.x)) <= deg_to_rad(float(args[1]) * 0.5)


func _forward_box(point: Vector2, args: Array) -> bool:
	# Flat-ended line: [0, length] along forward, +/- width/2 sideways.
	return point.x >= 0.0 and point.x <= float(args[0]) and absf(point.y) <= float(args[1]) * 0.5


func _centered_box(point: Vector2, args: Array) -> bool:
	return absf(point.x) <= float(args[0]) * 0.5 and absf(point.y) <= float(args[1]) * 0.5


## Supply the complete target roster in stable FIFO order each simulation tick,
## including non-pulse ticks, so exits are observable. An omitted target left.
## inputs: position, direction, pulse (a due pulse supplied by the scheduler).
## Entry / rehit deadline / pulse are coalesced into ONE candidate per target
## per tick. Waiting is measured from the candidate, even when it all evaded.
## No interval + continuous overlap does not cause per-tick rerolls.
func step(targets: Array, inputs: Dictionary = {}) -> Dictionary:
	var result: Dictionary = {"ok": false, "candidates": [], "events": [], "error": ""}
	if not _ready:
		return _step_error(result, "Shape/hit is not configured: " + _meta_error)
	if not _adapter_error.is_empty():
		return _step_error(result, _adapter_error)
	var tick: int = int(_clock.snapshot_state()["tick"])
	if tick < _last_tick:
		return _step_error(result, "Reversed tick")
	if _last_tick >= 0 and tick > _last_tick + 1:
		return _step_error(result, "Skipped tick; supply the complete roster every tick")
	if tick == _last_tick:
		result["ok"] = true
		return result
	var position_value: Variant = inputs.get("position", Vector2.ZERO)
	var direction_value: Variant = inputs.get("direction", Vector2.RIGHT)
	var pulse_value: Variant = inputs.get("pulse", false)
	if not _valid_vector(position_value) or not _valid_vector(direction_value) or direction_value.is_zero_approx() or not pulse_value is bool:
		return _step_error(result, "Invalid runtime transform or pulse")
	# Preflight the whole roster before spending quota or RNG; duplicate IDs
	# are accepted only for identical samples and then coalesced in FIFO order.
	var samples: Dictionary = {}
	for target in targets:
		if not target is Dictionary or not _string(target.get("target_id", null)) or not _valid_vector(target.get("position", null)) or typeof(target.get("alive", null)) != TYPE_BOOL:
			return _step_error(result, "Each target requires target_id, finite position and alive")
		var id: String = target["target_id"]
		if samples.has(id) and samples[id] != target:
			return _step_error(result, "Conflicting samples for target: " + id)
		samples[id] = target
	_last_tick = tick
	result["ok"] = true
	last_error = ""
	if not _body.is_alive() or tick < _body.spawn_tick:
		return result
	# Carrier none has a zero-tick hit window, before its instant_end step.
	if _body.carrier != BodyScript.CARRIER_NONE and tick >= _body.spawn_tick + _body.lifetime_ticks:
		return result
	if _body.carrier == BodyScript.CARRIER_NONE and tick != _body.spawn_tick:
		return result
	var inside_now: Dictionary = {}
	var seen: Dictionary = {}
	for target in targets:
		var id: String = target["target_id"]
		if seen.has(id):
			continue
		seen[id] = true
		# A prior FIFO resolver can kill a later target or purge this body.
		if not _body.is_alive():
			break
		if not target["alive"] or not contains_point(target["position"], position_value, direction_value):
			continue
		inside_now[id] = true
		var ledger_value: Variant = _targets.get(id, null)
		if ledger_value == null:
			ledger_value = {"candidate_count": 0, "hit_count": 0, "last_candidate_tick": -1, "inside": false}
			_targets[id] = ledger_value
		var ledger: Dictionary = ledger_value
		if int(ledger["candidate_count"]) >= _target_limit or (_hit_limit > 0 and _hit_count >= _hit_limit):
			continue
		var contacted: bool = int(ledger["candidate_count"]) > 0
		var due: bool = contacted and _interval > 0 and tick - int(ledger["last_candidate_tick"]) >= _interval
		if contacted and _interval > 0 and not due:
			continue
		if bool(ledger["inside"]) and not due and not pulse_value:
			continue
		ledger["candidate_count"] += 1
		ledger["last_candidate_tick"] = tick
		_candidate_count += 1
		var candidate: Dictionary = {"tick": tick, "body_id": _body.body_id, "target_id": id, "hit": false}
		result["candidates"].append(candidate)
		var successful: Variant = true
		if _resolver.is_valid():
			successful = _resolver.call(target, _clock.rng_logic())
		if typeof(successful) != TYPE_BOOL:
			# Fail closed: contact and any RNG consumed stay spent; never retry
			# the same tick to turn a bad adapter into a free second roll.
			_update_inside(inside_now)
			_adapter_error = "Hit resolver must return bool; candidate remains spent; checker is faulted"
			return _step_error(result, _adapter_error)
		if successful:
			candidate["hit"] = true
			ledger["hit_count"] += 1
			_hit_count += 1
			result["events"].append({"type": _meta["hit_event"], "tick": tick, "body_id": _body.body_id, "target_id": id})
	_update_inside(inside_now)
	return result


func _update_inside(inside_now: Dictionary):
	for id in _targets:
		var ledger: Dictionary = _targets[id]
		ledger["inside"] = inside_now.has(id)


func snapshot_state() -> Dictionary:
	return {"candidate_count": _candidate_count, "hit_count": _hit_count, "targets": _targets.duplicate(true), "last_tick": _last_tick}


func _step_error(result: Dictionary, message: String) -> Dictionary:
	last_error = message
	result["ok"] = false
	result["error"] = message
	return result


static func _valid_vector(value: Variant) -> bool:
	return typeof(value) == TYPE_VECTOR2 and value.is_finite()


static func _finite_number(value: Variant) -> bool:
	return (typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT) and is_finite(float(value))


static func _integer(value: Variant) -> bool:
	return typeof(value) == TYPE_INT


static func _string(value: Variant) -> bool:
	return typeof(value) == TYPE_STRING and not value.is_empty()


func _fail(message: String) -> bool:
	last_error = message
	return false
