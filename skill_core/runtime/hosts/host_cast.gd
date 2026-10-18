class_name HostCast extends RefCounted

var _cooldown_until: int = -1


func validate(request: Dictionary, ctx: Dictionary) -> Dictionary:
	var windup: Variant = request.get("windup_ticks", null)
	if not windup is int or windup < 0:
		return _failure("windup_ticks", "Expected nonnegative integer windup_ticks", "INVALID_CAST")
	var shots: Variant = request.get("shot_ticks", null)
	if not shots is Array or shots.is_empty():
		return _failure("shot_ticks", "Expected nonempty integer shot_ticks", "INVALID_CAST")
	var count: Variant = request.get("shot_count", null)
	if not count is int or count < 1:
		return _failure("shot_count", "Expected positive integer shot_count", "INVALID_CAST")
	if count != shots.size():
		return _failure("shot_count", "shot_count=%s does not match shot_ticks.size=%s" % [str(count), str(shots.size())], "CAST_COUNT_MISMATCH")
	var previous: int = -1
	for index in range(shots.size()):
		var shot_tick: Variant = shots[index]
		if not shot_tick is int:
			return _failure("shot_ticks[%d]" % index, "Expected integer shot tick", "INVALID_CAST")
		if shot_tick < windup:
			return _failure("shot_ticks[%d]" % index, "shot tick must be at least windup_ticks", "INVALID_CAST")
		if shot_tick <= previous:
			return _failure("shot_ticks[%d]" % index, "shot_ticks must be strictly increasing", "INVALID_CAST")
		previous = shot_tick
	var cooldown: Variant = request.get("cooldown_seconds", null)
	if not _number(cooldown) or cooldown <= 0:
		return _failure("cooldown_seconds", "Expected positive cooldown_seconds", "INVALID_CAST")
	var rate: Variant = _tick_rate(ctx)
	if not _integer_value(rate) or float(rate) < 1.0:
		return _failure("project_config.tick_rate", "A positive integral tick rate is required", "INVALID_CAST")
	var cooldown_ticks: float = ceil(float(cooldown) * float(rate))
	if cooldown_ticks < 1 or cooldown_ticks != floor(cooldown_ticks):
		return _failure("cooldown_seconds", "Cooldown cannot be represented in ticks", "INVALID_CAST")
	return {"ok": true, "error": "", "path": "", "code": ""}


func begin(request: Dictionary, ctx: Dictionary) -> Dictionary:
	var checked: Dictionary = validate(request, ctx)
	if not checked["ok"]:
		return checked
	var tick: int = _current_tick(ctx)
	if _cooldown_until >= 0 and tick < _cooldown_until:
		return _failure("cooldown_seconds", "Cast is cooling down; remaining ticks: %d" % (_cooldown_until - tick), "CAST_COOLDOWN")
	var template_id: Variant = ctx.get("template_id", null)
	var shot_id: Variant = ctx.get("shot_id", null)
	if not template_id is String or template_id.is_empty():
		return _failure("template_id", "Cast requires a template_id", "INVALID_CAST_CONTEXT")
	if not shot_id is String or shot_id.is_empty():
		return _failure("shot_id", "Cast requires a caller-provided shot_id", "INVALID_CAST_CONTEXT")
	var cooldown: float = float(request["cooldown_seconds"])
	var rate: int = int(_tick_rate(ctx))
	var cooldown_ticks: int = int(ceil(cooldown * float(rate)))
	var state: Dictionary = {"status": "active", "start_tick": tick, "next_index": 0,
		"shot_ticks": request["shot_ticks"].duplicate(), "shot_count": request["shot_count"],
		"cooldown_ticks": cooldown_ticks, "template_id": template_id, "shot_id": shot_id,
		"origin": ctx.get("origin", {}), "parent_ref": ctx.get("parent_ref", "")}
	return {"ok": true, "error": "", "state": state}


func advance(state: Dictionary, tick: int, ctx: Dictionary) -> Dictionary:
	var emissions: Dictionary = {"spawn": [], "attach": [], "events": [], "records": []}
	if not state is Dictionary:
		return {"ok": false, "error": "Invalid cast state", "path": "state", "code": "INVALID_CAST_STATE", "state": {}, "emissions": emissions}
	var status: String = str(state.get("status", ""))
	if status == "cancelled" or status == "done":
		return {"ok": true, "error": "", "state": state, "emissions": emissions}
	if bool(ctx.get("interrupt", false)):
		state["status"] = "cancelled"
		return {"ok": true, "error": "", "state": state, "emissions": emissions}
	var shot_ticks: Array = state["shot_ticks"]
	var next_index: int = int(state["next_index"])
	var elapsed: int = tick - int(state["start_tick"])
	if next_index < shot_ticks.size() and elapsed == int(shot_ticks[next_index]):
		var spawn: Dictionary = {"template_id": state["template_id"], "shot_id": state["shot_id"],
			"origin": state["origin"], "parent_ref": state["parent_ref"]}
		emissions["spawn"].append(spawn)
		next_index += 1
		state["next_index"] = next_index
		if next_index >= shot_ticks.size():
			state["status"] = "done"
			_cooldown_until = tick + int(state["cooldown_ticks"])
	return {"ok": true, "error": "", "state": state, "emissions": emissions}


func _tick_rate(ctx: Dictionary) -> Variant:
	var direct: Variant = ctx.get("tick_rate", null)
	if direct is int:
		return direct
	var config: Variant = ctx.get("project_config", null)
	if config is Dictionary:
		return config.get("tick_rate", null)
	return null


func _current_tick(ctx: Dictionary) -> int:
	var value: Variant = ctx.get("tick", ctx.get("current_tick", 0))
	return int(value) if value is int else 0


func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))


## 素材 JSON 解析出来的整数一律是 float（坑 9）：60 会变成 60.0，
## 所以这里只判「数值且值为整数」，不能用 `is int` 单判。
func _integer_value(value: Variant) -> bool:
	if not _number(value):
		return false
	var as_float: float = float(value)
	return as_float == floor(as_float)


func _failure(path: String, error: String, code: String) -> Dictionary:
	return {"ok": false, "error": error, "path": path, "code": code}
