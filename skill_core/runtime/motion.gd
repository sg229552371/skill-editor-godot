class_name RuntimeMotion extends RefCounted

## Tick-local kinematics, not a lifecycle/event producer. Call after clock.tick()
## and before collision/termination arbitration. Never pass rendering delta.
## Inputs are runtime context, not additional CFG fields. No CFG is retained.
const BodyScript = preload("res://skill_core/runtime/effect_body.gd")
const MOTION_META_PATH: String = "res://data/motion_meta.json"

static var _meta_initialized: bool = false
static var _meta_valid: bool = false
static var _motion_meta: Dictionary = {}

var position: Vector2 = Vector2.ZERO
var direction: Vector2 = Vector2.RIGHT
var finished: bool = false
var last_error: String = ""
var distance: float = 0.0
var speed: float = 0.0
var radius: float = 0.0
var returning: bool = false
var target_lost: bool = false

var _modes: Dictionary = {}
var _allowed_modes: Array = []
var _fields: Dictionary = {}
var _params: Dictionary = {}
var _clock: RefCounted
var _body: RefCounted
var _handler: Callable
var _last_tick: int = 0
var _ready: bool = false
var _target: Vector2 = Vector2.ZERO
var _launch_position: Vector2 = Vector2.ZERO
var _flight_ticks: int = 0
var _flight_elapsed: int = 0
var _geometry_fields: Dictionary = {}
var _wave_end: float = 0.0
var _wave_speed: float = 0.0
var _center: Vector2 = Vector2.ZERO
var _angle: float = 0.0
var _angular_step: float = 0.0
var _tracking_profiles: Dictionary = {}
var _tracking: Callable
var _loss_handlers: Dictionary = {}
var _on_lost: Callable
var _loss_default: String = ""


func _init():
	if not _meta_initialized:
		_meta_initialized = true
		var raw_meta: String = ""
		if FileAccess.file_exists(MOTION_META_PATH):
			raw_meta = FileAccess.get_file_as_string(MOTION_META_PATH)
		var parsed_meta: Variant = JSON.parse_string(raw_meta)
		if typeof(parsed_meta) == TYPE_DICTIONARY:
			var candidate: Dictionary = parsed_meta
			var has_required_sections: bool = candidate.has("motion_modes")
			has_required_sections = has_required_sections and candidate.has("motion_fields")
			has_required_sections = has_required_sections and candidate.has("geometry_fields")
			has_required_sections = has_required_sections and candidate.has("on_target_lost")
			if has_required_sections:
				var modes_value: Variant = candidate["motion_modes"]
				var fields_value: Variant = candidate["motion_fields"]
				var geometry_value: Variant = candidate["geometry_fields"]
				var loss_value: Variant = candidate["on_target_lost"]
				var valid_shape: bool = typeof(modes_value) == TYPE_ARRAY
				valid_shape = valid_shape and typeof(fields_value) == TYPE_DICTIONARY
				valid_shape = valid_shape and typeof(geometry_value) == TYPE_DICTIONARY
				valid_shape = valid_shape and typeof(loss_value) == TYPE_DICTIONARY
				if valid_shape:
					_motion_meta = candidate
					_meta_valid = true
	if not _meta_valid:
		last_error = "运动元数据未载入"
		return
	var metadata: Dictionary = _motion_meta
	_allowed_modes = metadata["motion_modes"].duplicate()
	_fields = metadata["motion_fields"].duplicate(true)
	_geometry_fields = metadata["geometry_fields"].duplicate(true)
	# Dispatch bindings are explicit implementation registration, not mode branches.
	register_mode("straight", _straight, ["speed", "range", "acceleration", "speed_cap"], _init_moving)
	register_mode("lob", _lob, [], _init_lob)
	register_mode("stationary", _stationary, ["speed"], _init_stationary)
	register_mode("wavefront", _wavefront, [], _init_wavefront)
	register_mode("orbit", _orbit, ["orbit_radius", "angular_speed", "phase"], _init_orbit)
	register_mode("returning", _returning, ["speed", "range", "acceleration", "speed_cap"], _init_returning)
	register_mode("homing", _homing, ["speed", "range", "tracking_profile", "acceleration", "speed_cap"], _init_homing)
	var loss_bindings: Dictionary = {"continue": _straight, "terminate": _stop_on_loss}
	var loss_policy: Dictionary = metadata["on_target_lost"]
	for policy in loss_policy["enum"]:
		if loss_bindings.has(policy):
			_loss_handlers[policy] = loss_bindings[policy]
	_loss_default = str(loss_policy["default"])


## Extensions must already be registered in the schema. Their parameter names
## must also belong to the schema; unknown modes never fall back to straight.
func register_mode(mode: String, handler: Callable, keys: Array, initializer: Callable = Callable()) -> bool:
	if not _allowed_modes.has(mode) or not handler.is_valid() or _modes.has(mode):
		return false
	for key in keys:
		if not _fields.has(key):
			return false
	_modes[mode] = {"handler": handler, "keys": keys.duplicate(), "initializer": initializer}
	return true


func registered_modes() -> Array:
	return _modes.keys()


func configure(template: Dictionary, body: RefCounted, clock: RefCounted, inputs: Dictionary = {}) -> bool:
	if not _meta_valid:
		return _fail("运动元数据未载入")
	if _ready:
		return _fail("Motion is already configured")
	_tracking = Callable()
	finished = false
	returning = false
	target_lost = false
	distance = 0.0
	radius = 0.0
	if body == null or clock == null or not body.is_alive():
		return _fail("A live effect body and clock are required")
	# self must consume the displacement authority, not a second flight speed.
	# Its follow adapter is intentionally outside this seven-mode increment.
	if body.carrier != BodyScript.CARRIER_INDEPENDENT:
		return _fail("This increment supports only independent carrier motion")
	if typeof(template.get("motion")) != TYPE_DICTIONARY:
		return _fail("Motion must be a dictionary")
	var cfg: Dictionary = template["motion"]
	var mode: String = str(cfg.get("mode", ""))
	if not _modes.has(mode):
		return _fail("Unsupported motion mode: " + mode)
	var binding: Dictionary = _modes[mode]
	_params = cfg.duplicate(true)
	for key in binding["keys"]:
		if not _params.has(key) and _fields[key].has("default"):
			_params[key] = _fields[key]["default"]
	for key in _params:
		if not _fields.has(key):
			return _fail("Unknown motion parameter: " + str(key))
		var definition: Dictionary = _fields[key]
		if definition.get("type", "") == "number":
			var value: Variant = _params[key]
			if not _finite_number(value):
				return _fail("Expected finite number: " + str(key))
			if definition.has("minimum") and value < definition["minimum"]:
				return _fail("Below minimum: " + str(key))
			if definition.has("exclusiveMinimum") and value <= definition["exclusiveMinimum"]:
				return _fail("Below exclusive minimum: " + str(key))
	if float(_params.get("acceleration", 0.0)) != 0.0 and not _params.has("speed_cap"):
		return _fail("Acceleration requires speed_cap")
	if not _valid_vector(inputs.get("position", Vector2.ZERO)) or not _valid_vector(inputs.get("direction", Vector2.RIGHT)):
		return _fail("Invalid position or direction")
	position = inputs.get("position", Vector2.ZERO)
	direction = inputs.get("direction", Vector2.RIGHT)
	if direction.is_zero_approx():
		return _fail("Direction must be nonzero")
	direction = direction.normalized()
	speed = float(_params.get("speed", 0.0))
	var initializer: Callable = binding["initializer"]
	if initializer.is_valid() and not initializer.call(template, inputs):
		return false
	if _params.has("speed_cap"):
		speed = minf(speed, float(_params["speed_cap"]))
	_clock = clock
	_body = body
	_last_tick = int(clock.snapshot_state()["tick"])
	_handler = binding["handler"]
	_ready = true
	last_error = ""
	return true


## One call per simulation tick. Skips are rejected, not replayed with today's
## target/anchor positions (which would silently corrupt historical inputs).
func step(inputs: Dictionary = {}) -> bool:
	if not _ready or finished or not _body.is_alive():
		return false
	var tick: int = int(_clock.snapshot_state()["tick"])
	if tick == _last_tick:
		return false
	if tick != _last_tick + 1:
		return _fail("Skipped or reversed tick; supply each tick's inputs")
	if tick < _body.spawn_tick:
		_last_tick = tick
		return false
	if tick >= _body.spawn_tick + _body.lifetime_ticks:
		return false
	var result: bool = _handler.call(inputs)
	if result:
		_last_tick = tick
	return result


## Trusted runtime strategies, not author-authored scripts or expressions.
## Signature: (position, direction, target, clock.rng_logic()) -> Vector2.
func register_tracking_profile(reference: String, strategy: Callable) -> bool:
	if _ready or reference.is_empty() or not strategy.is_valid() or _tracking_profiles.has(reference):
		return false
	_tracking_profiles[reference] = strategy
	return true


func _init_homing(template: Dictionary, inputs: Dictionary) -> bool:
	if not _init_moving(template, inputs):
		return false
	var reference: String = str(_params.get("tracking_profile", ""))
	if not reference.is_empty():
		if not _tracking_profiles.has(reference):
			return _fail("Unregistered tracking_profile: " + reference)
		_tracking = _tracking_profiles[reference]
	var policy: String = str(template.get("on_target_lost", _loss_default))
	if not _loss_handlers.has(policy):
		return _fail("Unregistered target-loss policy: " + policy)
	_on_lost = _loss_handlers[policy]
	return true


func _homing(inputs: Dictionary) -> bool:
	if not _tracking.is_valid():
		return _straight(inputs)
	var target: Variant = inputs.get("target")
	if target == null:
		target_lost = true
		return _on_lost.call(inputs)
	if not _valid_vector(target):
		return _fail("Tracking target must be a finite Vector2 or null")
	var rng: RandomNumberGenerator = _clock.rng_logic()
	var previous_rng_state: int = rng.state
	var heading: Variant = _tracking.call(position, direction, target, rng)
	if not _valid_vector(heading) or heading.is_zero_approx():
		rng.state = previous_rng_state
		return _fail("Tracking strategy returned an invalid direction")
	target_lost = false
	direction = heading.normalized()
	return _straight(inputs)


func _stop_on_loss(_inputs: Dictionary) -> bool:
	finished = true
	return true


func _init_returning(template: Dictionary, inputs: Dictionary) -> bool:
	if not _init_moving(template, inputs):
		return false
	if not _params.has("range") or not _valid_vector(inputs.get("return_point")):
		return _fail("Returning requires range and an explicit return point")
	return true


func _returning(inputs: Dictionary) -> bool:
	if not _valid_vector(inputs.get("return_point")):
		return _fail("Returning requires this tick's resolved return point")
	# Host resolves a missing caster according to the recipe, not this module.
	if returning:
		finished = _move_toward(inputs["return_point"], _advance_speed())
	else:
		_straight(inputs)
		returning = finished
		finished = false
	return true


func _init_orbit(_template: Dictionary, inputs: Dictionary) -> bool:
	for key in ["orbit_radius", "angular_speed", "phase"]:
		if not _params.has(key):
			return _fail("Missing orbit parameter: " + key)
	# TODO(U-T042-angle): schema registers the keys but not angular units.
	# Require host conversion; do not silently freeze degrees or radians in CFG.
	if not _finite_number(inputs.get("angle_scale")) or float(inputs["angle_scale"]) <= 0.0:
		return _fail("Orbit requires explicit angle_scale to radians")
	if not _valid_vector(inputs.get("center")):
		return _fail("Orbit requires a finite reference center")
	_center = inputs["center"]
	_angle = float(_params["phase"]) * float(inputs["angle_scale"])
	_angular_step = float(_params["angular_speed"]) * float(inputs["angle_scale"])
	if not is_finite(_angle) or not is_finite(_angular_step):
		return _fail("Angular conversion overflow")
	position = _center + Vector2.from_angle(_angle) * float(_params["orbit_radius"])
	return true


func _orbit(inputs: Dictionary) -> bool:
	# A reference must be supplied each tick. A missing host is not silently
	# frozen forever; lifecycle arbitration decides what to do with its loss.
	if not _valid_vector(inputs.get("center")):
		return _fail("Orbit requires this tick's reference center")
	var previous: Vector2 = position
	_center = inputs["center"]
	_angle = fposmod(_angle + _angular_step, TAU)
	position = _center + Vector2.from_angle(_angle) * float(_params["orbit_radius"])
	var offset: Vector2 = position - previous
	if not offset.is_zero_approx():
		direction = offset.normalized()
	distance += offset.length()
	return true


func _init_wavefront(template: Dictionary, inputs: Dictionary) -> bool:
	if not _init_stationary(template, inputs):
		return false
	if typeof(template.get("geometry")) != TYPE_DICTIONARY:
		return _fail("Wavefront requires geometry parameters")
	var geometry: Dictionary = template["geometry"].duplicate(true)
	var keys: Array = ["wavefront_start_radius", "wavefront_end_radius", "wavefront_speed"]
	for key in keys:
		var definition: Dictionary = _geometry_fields[key]
		if not geometry.has(key) and definition.has("default"):
			geometry[key] = definition["default"]
		if not _finite_number(geometry.get(key)):
			return _fail("Missing or invalid wavefront parameter: " + key)
	radius = float(geometry["wavefront_start_radius"])
	_wave_end = float(geometry["wavefront_end_radius"])
	_wave_speed = float(geometry["wavefront_speed"])
	if radius < 0.0 or _wave_end <= radius or _wave_speed <= 0.0:
		return _fail("Wavefront requires ordered radii and positive speed")
	return true


func _wavefront(_inputs: Dictionary) -> bool:
	radius = minf(_wave_end, radius + _wave_speed)
	finished = radius >= _wave_end
	return true


func _init_stationary(_template: Dictionary, _inputs: Dictionary) -> bool:
	if speed != 0.0 or float(_params.get("acceleration", 0.0)) != 0.0:
		return _fail("Stationary motion must have zero speed and acceleration")
	return true


func _stationary(_inputs: Dictionary) -> bool:
	return true


func _init_moving(_template: Dictionary, _inputs: Dictionary) -> bool:
	if not _params.has("speed"):
		return _fail("Moving modes require speed")
	return true


func _init_lob(_template: Dictionary, inputs: Dictionary) -> bool:
	if not _valid_vector(inputs.get("target")):
		return _fail("Lob requires a finite fixed ground target")
	# TODO(U-T042-flight): ch04 freezes flight time semantically, but schema
	# has no flight-duration field. Host must resolve it; never infer from art.
	if typeof(inputs.get("flight_ticks")) != TYPE_INT or inputs["flight_ticks"] <= 0:
		return _fail("Lob requires a positive resolved flight_ticks input")
	if _params.has("speed") or _params.has("acceleration") or _params.has("speed_cap"):
		return _fail("Lob flight duration must have one authority, not a second speed curve")
	_target = inputs["target"]
	_launch_position = position
	_flight_ticks = inputs["flight_ticks"]
	_flight_elapsed = 0
	return true


func _lob(_inputs: Dictionary) -> bool:
	_flight_elapsed += 1
	var previous: Vector2 = position
	position = _launch_position.lerp(_target, minf(1.0, float(_flight_elapsed) / float(_flight_ticks)))
	var offset: Vector2 = position - previous
	if not offset.is_zero_approx():
		direction = offset.normalized()
	distance += offset.length()
	finished = _flight_elapsed >= _flight_ticks
	return true


func _move_toward(target: Vector2, amount: float) -> bool:
	var offset: Vector2 = target - position
	var length: float = offset.length()
	if length > 0.0:
		direction = offset / length
	var travelled: float = minf(amount, length)
	position = target if amount >= length else position + direction * travelled
	distance += travelled
	return amount >= length


func _straight(_inputs: Dictionary) -> bool:
	var amount: float = _advance_speed()
	if _params.has("range"):
		amount = minf(amount, maxf(0.0, float(_params["range"]) - distance))
	position += direction * amount
	distance += amount
	finished = _params.has("range") and distance >= float(_params["range"])
	return true


func _advance_speed() -> float:
	speed = maxf(0.0, speed + float(_params.get("acceleration", 0.0)))
	if _params.has("speed_cap"):
		speed = minf(speed, float(_params["speed_cap"]))
	return speed


func _finite_number(value: Variant) -> bool:
	return (typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT) and is_finite(float(value))


func _valid_vector(value: Variant) -> bool:
	return typeof(value) == TYPE_VECTOR2 and value.is_finite()


func _fail(message: String) -> bool:
	last_error = message
	return false
