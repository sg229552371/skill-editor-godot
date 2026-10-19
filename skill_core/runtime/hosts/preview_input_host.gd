extends RefCounted

## Input-side preview adapter. D-93 (:5390, :9500-9504): the input host,
## not the skill runner, owns buffered requests. All times are simulation ticks.
const CastScript = preload("res://skill_core/runtime/hosts/host_cast.gd")

var _configured: bool = false
var _bound: bool = false
var _tick: int = 0
var _window: int = 0
var _tick_rate: int = 0
var _locks: Dictionary = {"cast_gate": false, "pause_cast": false, "interrupts_cast": false}
var _pending: Array = []
var _ready: Array = []
var _discarded: Array = []
var _actions: Array = []
var _shots: Array = []
var _adapters: Dictionary = {}
var _templates: Dictionary = {}
var _sequence: int = 0
var _equipment_slots: Dictionary = {}
var _pending_equipment: Dictionary = {}
var _equipment_cfg_params: Dictionary = {}
var _equipment_cooldown_until: int = -1
var _equipment_configured: bool = false


func configure(config: Dictionary) -> Dictionary:
	if _bound:
		return _failure("configure", "Host is bound to a preview")
	var buffer: Variant = config.get("input_buffer", null)
	if not buffer is Dictionary or not buffer.get("window_ticks", null) is int or buffer["window_ticks"] < 0:
		return _failure("input_buffer.window_ticks", "Explicit nonnegative integer project input window required")
	_window = buffer["window_ticks"]
	_configured = true
	return {"ok": true, "error": ""}


## Resolved action-lock facts, not control-type names or author CFG overrides.
func set_locks(locks: Dictionary) -> Dictionary:
	for field in _locks:
		if not locks.get(field, null) is bool:
			return _failure("locks." + str(field), "All resolved lock facts must be booleans")
	if locks.size() != _locks.size():
		return _failure("locks", "Unknown action-lock fact")
	_locks = locks.duplicate(true)
	return {"ok": true, "error": ""}


func request_cast(request: Dictionary) -> Dictionary:
	if not _bound:
		return _failure("request_cast", "Host must be bound to a running preview")
	var checked: Dictionary = _check_request(request)
	if not checked["ok"]:
		return checked
	var item: Dictionary = request.duplicate(true)
	item["expires_tick"] = _tick + _window
	if _locks["cast_gate"]:
		_pending.append(item)
		return {"ok": false, "buffered": true, "path": "cast_gate", "error": "Cast gate closed"}
	_ready.append(item)
	return {"ok": true, "buffered": false, "error": ""}


## Equipment is a separate input channel from HostCast's skill cooldown.
## Changes are copied into a pending batch and become visible only at a boundary.
func configure_equipment(config: Dictionary) -> Dictionary:
	if _bound:
		return _failure("equipment", "Equipment must be configured before binding a preview")
	var slots: Variant = config.get("slots", null)
	if not slots is Dictionary or config.size() != 1:
		return _failure("equipment", "Expected only slots object; cooldown duration belongs in CFG")
	_equipment_slots = slots.duplicate(true)
	_equipment_cooldown_until = -1
	_pending_equipment.clear()
	_equipment_configured = true
	return {"ok": true, "error": ""}


## Validate the complete batch before staging it; no partial slot mutation occurs.
func request_equipment_changes(changes: Dictionary) -> Dictionary:
	if not _equipment_configured:
		return _failure("equipment", "Equipment is not configured")
	if not _bound:
		return _failure("equipment", "Host must be bound to a running preview")
	var checked: Dictionary = _check_equipment_cfg(_equipment_cfg_params)
	if not checked["ok"]:
		return checked
	if _equipment_cooldown_until >= 0 and _tick < _equipment_cooldown_until:
		return {"ok": false, "path": "params.assembly_shared_cooldown_ticks", "code": "EQUIPMENT_COOLDOWN",
			"error": "Equipment is cooling down; remaining ticks: %d" % (_equipment_cooldown_until - _tick)}
	if changes.is_empty():
		return _failure("equipment", "At least one equipment slot change is required")
	for slot in changes:
		if not _equipment_slots.has(slot):
			return _failure("equipment." + str(slot), "Unknown equipment slot")
	_pending_equipment = changes.duplicate(true)
	return {"ok": true, "staged": true, "error": ""}


## Apply one staged batch at tick start, before the input host can release a cast.
func apply_equipment_boundary(tick: int) -> Dictionary:
	if not _equipment_configured:
		return {"ok": true, "applied": false, "error": ""}
	_tick = tick
	if _pending_equipment.is_empty():
		return {"ok": true, "applied": false, "error": ""}
	var checked: Dictionary = _check_equipment_cfg(_equipment_cfg_params)
	if not checked["ok"]:
		return checked
	var duration: int = _equipment_cfg_params["assembly_shared_cooldown_ticks"]
	for slot in _pending_equipment:
		_equipment_slots[slot] = _pending_equipment[slot]
	_pending_equipment.clear()
	_equipment_cooldown_until = tick + duration
	return {"ok": true, "applied": true, "error": ""}


func equipment_snapshot() -> Dictionary:
	return {"slots": _equipment_slots.duplicate(true), "pending": _pending_equipment.duplicate(true),
		"assembly_shared_cooldown_until": _equipment_cooldown_until,
		"skill_cooldown_until": -1, "passive_internal_cooldown_until": -1}


func snapshot_state() -> Dictionary:
	return {"tick": _tick, "locks": _locks.duplicate(true), "pending": _pending.duplicate(true),
		"discarded": _discarded.duplicate(true), "actions": _actions.duplicate(true),
		"shots": _shots.duplicate(true), "X": _shots.size()}


func _bind(templates: Dictionary, roots: Array, rate: int, cfg_params: Dictionary) -> Dictionary:
	if not _configured or _bound:
		return _failure("runtime_host", "Configure a fresh input host for each preview")
	if _equipment_configured:
		var checked: Dictionary = _check_equipment_cfg(cfg_params)
		if not checked["ok"]:
			return checked
	_equipment_cfg_params = cfg_params.duplicate(true)
	_templates = templates.duplicate(true)
	_tick_rate = rate
	_bound = true
	for root in roots:
		var template: Dictionary = _templates[root["template_id"]]
		if template.has("cast") and not template["cast"].is_empty():
			var requested: Dictionary = request_cast(root)
			if not requested["ok"] and not requested.get("buffered", false):
				return requested
	return {"ok": true, "error": ""}


func _check_request(request: Dictionary) -> Dictionary:
	var id: Variant = request.get("template_id", null)
	var shot: Variant = request.get("shot_id", null)
	if not id is String or not _templates.has(id) or not shot is String or shot.is_empty():
		return _failure("request_cast", "Registered template_id and nonempty shot_id required")
	var template: Dictionary = _templates[id]
	var cast: Variant = template.get("cast", null)
	if not cast is Dictionary or cast.is_empty():
		return _failure("request_cast.template_id", "Requested template needs a cast schedule")
	var count: Variant = request.get("instance_count", 1)
	if not count is int or count < 1:
		return _failure("request_cast.instance_count", "Positive integer instance count required")
	return {"ok": true, "error": ""}


func _boundary(tick: int) -> Dictionary:
	_tick = tick
	return {"ok": true, "error": ""}


func _advance(tick: int) -> Dictionary:
	var elapsed_ticks: int = maxi(0, tick - _tick)
	_tick = tick
	var retained: Array = []
	for item in _pending:
		if tick >= int(item["expires_tick"]):
			_discarded.append({"request": item.duplicate(true), "tick": tick, "error": "Input buffer expired"})
		elif not _locks["cast_gate"]:
			_ready.append(item)
		else:
			retained.append(item)
	_pending = retained
	var emissions: Dictionary = {"spawn": [], "attach": [], "events": [], "records": []}
	# One skill loop at a time, FIFO; no request priority arbitration (:5394).
	var busy: bool = false
	for action in _actions:
		if action["state"]["status"] == "active":
			busy = true
	if not busy and not _locks["cast_gate"] and not _ready.is_empty():
		var item: Dictionary = _ready.pop_front()
		var id: String = item["template_id"]
		if not _adapters.has(id):
			_adapters[id] = CastScript.new()
		var ctx: Dictionary = {"template_id": id, "shot_id": item["shot_id"],
			"tick": tick, "tick_rate": _tick_rate}
		var begun: Dictionary = _adapters[id].begin(_templates[id]["cast"], ctx)
		if not begun["ok"]:
			_discarded.append({"request": item, "tick": tick, "error": begun["error"]})
		else:
			var action_id: String = "action:%d" % _sequence
			_sequence += 1
			_actions.append({"action_id": action_id, "state": begun["state"], "ctx": ctx,
				"instance_count": item.get("instance_count", 1), "template": _templates[id].duplicate(true)})
	for action in _actions:
		var state: Dictionary = action["state"]
		var ctx: Dictionary = action["ctx"].duplicate(true)
		ctx["interrupt"] = _locks["interrupts_cast"]
		if state["status"] == "active" and _locks["pause_cast"] and not _locks["interrupts_cast"]:
			# Freeze remaining schedule time, not the simulation or existing bodies.
			state["start_tick"] = int(state["start_tick"]) + elapsed_ticks
			continue
		var index: int = state["next_index"]
		var advanced: Dictionary = _adapters[state["template_id"]].advance(state, tick, ctx)
		if not advanced["ok"]:
			return advanced
		if int(state["next_index"]) > index:
			var shot_id: String = "%s:%s:%d" % [state["shot_id"], action["action_id"], index]
			_shots.append({"action_id": action["action_id"], "shot_id": shot_id, "tick": tick})
			for spawn in advanced["emissions"]["spawn"]:
				for _instance in range(int(action["instance_count"])):
					var launch: Dictionary = spawn.duplicate(true)
					launch["shot_id"] = shot_id
					launch["template_snapshot"] = action["template"].duplicate(true)
					launch["equipment_snapshot"] = _equipment_slots.duplicate(true)
					emissions["spawn"].append(launch)
	return {"ok": true, "error": "", "emissions": emissions}


func _unbind() -> void:
	_bound = false
	_pending.clear()
	_ready.clear()


func _check_equipment_cfg(params: Dictionary) -> Dictionary:
	var duration: Variant = params.get("assembly_shared_cooldown_ticks", null)
	if not duration is int or duration < 0:
		return _failure("params.assembly_shared_cooldown_ticks", "Explicit nonnegative integer assembly_shared_cooldown_ticks required in CFG")
	return {"ok": true, "error": ""}


func _failure(path: String, error: String) -> Dictionary:
	return {"ok": false, "path": path, "error": error}
