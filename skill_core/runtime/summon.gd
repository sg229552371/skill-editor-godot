class_name RuntimeSummon extends RefCounted

## Runtime summon admission ledger. The policy is resolved by the host; this
## class never reads or writes a skill CFG and purge never emits an event.

var last_error: String = ""
var _ready: bool = false
var _fields: Dictionary = {}
var _ledger_keys: Dictionary = {}
var _record_fields: Dictionary = {}
var _states: Dictionary = {}
var _reasons: Dictionary = {}
var _limit: int = 0
var _strategy: String = ""
var _summons: Dictionary = {}
var _instances: Dictionary = {}
var _issued_ids: Dictionary = {}
var _records: Array = []
var _notices: Array = []
var _next_seq: int = 0


func configure(policy: Dictionary) -> bool:
	if _ready:
		return _fail("Summon ledger is already configured")
	var fields: Variant = policy.get("fields", null)
	var keys: Variant = policy.get("ledger_keys", null)
	var records: Variant = policy.get("record_fields", null)
	var states: Variant = policy.get("states", null)
	var reasons: Variant = policy.get("reasons", null)
	if not fields is Dictionary or not keys is Dictionary or not records is Dictionary:
		return _fail("Summon policy requires fields, ledger_keys and record_fields")
	if not states is Dictionary or not reasons is Dictionary:
		return _fail("Summon policy requires states and reasons")
	var limit_value: Variant = policy.get("limit", null)
	# Author/injected limits are strict integers. String numbers and JSON floats
	# are rejected rather than silently normalized.
	if typeof(limit_value) != TYPE_INT or limit_value <= 0:
		return _fail("Summon limit must be a positive integer")
	var strategy_value: Variant = policy.get("strategy", null)
	var strategy_values: Variant = policy.get("strategy_values", null)
	if not strategy_values is Dictionary or not strategy_values.get("oldest", null) is String:
		return _fail("Summon oldest cleanup strategy binding is missing")
	var expected_strategy: String = strategy_values["oldest"]
	if expected_strategy.is_empty() or not strategy_value is String or strategy_value != expected_strategy:
		return _fail("Summon cleanup strategy must select the injected oldest policy")
	for name in ["id", "owner", "seq", "spawn_tick", "state"]:
		var field_value: Variant = fields.get(name, null)
		if not field_value is String or field_value.is_empty() or field_value.contains("[") or field_value.contains("]"):
			return _fail("Invalid summon field binding: " + str(name))
	for name in ["instances", "summons", "records", "notices"]:
		var key_value: Variant = keys.get(name, null)
		if not key_value is String or key_value.is_empty():
			return _fail("Invalid summon ledger key binding: " + str(name))
	for name in ["type", "id", "reason", "seq", "spawn_tick"]:
		var record_value: Variant = records.get(name, null)
		if not record_value is String or record_value.is_empty():
			return _fail("Invalid summon record field binding: " + str(name))
	for name in ["active", "purged"]:
		var state_value: Variant = states.get(name, null)
		if not state_value is String or state_value.is_empty():
			return _fail("Invalid summon state binding: " + str(name))
	for name in ["limit", "owner_death", "ignored_seq"]:
		var reason_value: Variant = reasons.get(name, null)
		if not reason_value is String or reason_value.is_empty():
			return _fail("Invalid summon reason binding: " + str(name))
	_fields = fields.duplicate(true)
	_ledger_keys = keys.duplicate(true)
	_record_fields = records.duplicate(true)
	_states = states.duplicate(true)
	_reasons = reasons.duplicate(true)
	_limit = limit_value
	_strategy = strategy_value
	_ready = true
	last_error = ""
	return true


## Load the host's runtime ledger. `instances` contains valid owner IDs and
## `summons` contains summon objects. Both are copied before validation.
func sync_instances(snapshot: Dictionary) -> bool:
	if not _ready:
		return _fail("Summon ledger is not configured")
	var instance_key: String = _ledger_keys["instances"]
	var summon_key: String = _ledger_keys["summons"]
	var source_instances: Variant = snapshot.get(instance_key, null)
	var source_summons: Variant = snapshot.get(summon_key, null)
	if not source_instances is Dictionary or not source_summons is Dictionary:
		return _fail("Summon ledger snapshot is missing instances or summons")
	var next_instances: Dictionary = source_instances.duplicate(true)
	var next_summons: Dictionary = {}
	var next_issued: Dictionary = _issued_ids.duplicate(true)
	var seen_sequences: Dictionary = {}
	var next_seq: int = _next_seq
	for id in next_instances:
		if not _valid_id(id):
			return _fail("Invalid owner instance ID")
		next_issued[id] = true
	for id in source_summons:
		var item: Variant = source_summons[id]
		var checked: Dictionary = _validate_item(item, next_instances, source_summons, true)
		if not checked["ok"]:
			return _fail(checked["error"])
		var normalized: Dictionary = checked["item"]
		if normalized[_fields["id"]] != id:
			return _fail("Summon ledger key does not match summon ID")
		var seq: int = normalized[_fields["seq"]]
		if seen_sequences.has(seq):
			return _fail("Duplicate summon registration sequence")
		seen_sequences[seq] = true
		next_seq = maxi(next_seq, seq + 1)
		if next_issued.has(id):
			return _fail("Summon ID was already issued: " + str(id))
		next_summons[id] = normalized
		next_issued[id] = true
	_instances = next_instances
	_summons = next_summons
	_issued_ids = next_issued
	_next_seq = next_seq
	last_error = ""
	return true


func sync_ledger(snapshot: Dictionary) -> bool:
	return sync_instances(snapshot)


## Register a new summon. The new summon is admitted even when the limit is
## full; the oldest active record is purged first.
func spawn(item: Dictionary) -> Dictionary:
	var result: Dictionary = {"ok": false, "summon": null, "purged": [], "notices": [], "error": ""}
	if not _ready:
		return _result_error(result, "Summon ledger is not configured")
	var checked: Dictionary = _validate_item(item, _instances, _summons, false)
	if not checked["ok"]:
		return _result_error(result, checked["error"])
	var normalized: Dictionary = checked["item"]
	var id: String = normalized[_fields["id"]]
	if _issued_ids.has(id) or _summons.has(id) or _instances.has(id):
		return _result_error(result, "Summon ID was already issued: " + id)
	if _active_count() >= _limit:
		var oldest: String = _oldest_id()
		if oldest.is_empty() or not _purge(oldest, _reasons["limit"], result["purged"]):
			return _result_error(result, "Unable to purge oldest summon")
	var supplied_seq: bool = item.has(_fields["seq"])
	normalized[_fields["seq"]] = _next_seq
	normalized[_fields["state"]] = _states["active"]
	if supplied_seq:
		var notice: Dictionary = {}
		notice[_record_fields["type"]] = _reasons["ignored_seq"]
		notice[_record_fields["id"]] = id
		notice[_record_fields["reason"]] = _reasons["ignored_seq"]
		notice[_record_fields["seq"]] = _next_seq
		notice[_record_fields["spawn_tick"]] = normalized[_fields["spawn_tick"]]
		_notices.append(notice)
		result["notices"].append(notice.duplicate(true))
	_next_seq += 1
	_summons[id] = normalized.duplicate(true)
	_issued_ids[id] = true
	result["summon"] = normalized.duplicate(true)
	result["ok"] = true
	last_error = ""
	return result


func register_summon(item: Dictionary) -> Dictionary:
	return spawn(item)


func on_owner_death(owner_id: Variant) -> Dictionary:
	var result: Dictionary = {"ok": false, "purged": [], "error": ""}
	if not _ready:
		return _result_error(result, "Summon ledger is not configured")
	if not _valid_id(owner_id) or not _instances.has(owner_id):
		return _result_error(result, "Owner instance does not exist")
	var ids: Array = []
	for id in _summons:
		var item: Dictionary = _summons[id]
		if item[_fields["owner"]] == owner_id:
			ids.append(id)
	ids.sort_custom(_by_order)
	for id in ids:
		if not _purge(id, _reasons["owner_death"], result["purged"]):
			return _result_error(result, "Unable to purge owned summon: " + str(id))
	result["ok"] = true
	last_error = ""
	return result


func purge_owner(owner_id: Variant) -> Dictionary:
	return on_owner_death(owner_id)


func active_summons() -> Array:
	var result: Array = []
	var ids: Array = _summons.keys()
	ids.sort_custom(_by_order)
	for id in ids:
		result.append(_summons[id].duplicate(true))
	return result


func snapshot_state() -> Dictionary:
	if not _ready:
		return {}
	var result: Dictionary = {}
	result[_ledger_keys["instances"]] = _instances.duplicate(true)
	result[_ledger_keys["summons"]] = _summons.duplicate(true)
	result[_ledger_keys["records"]] = _records.duplicate(true)
	result[_ledger_keys["notices"]] = _notices.duplicate(true)
	return result


func _validate_item(value: Variant, owners: Dictionary, existing: Dictionary, from_snapshot: bool) -> Dictionary:
	if not value is Dictionary:
		return {"ok": false, "error": "Summon item must be an object"}
	var item: Dictionary = value
	var id_value: Variant = item.get(_fields["id"], null)
	if not _valid_id(id_value):
		return {"ok": false, "error": "Summon ID is missing or invalid"}
	if not item.has(_fields["owner"]):
		return {"ok": false, "error": "Summon owner binding is missing"}
	var owner_value: Variant = item[_fields["owner"]]
	if not (owner_value == null or _valid_id(owner_value)):
		return {"ok": false, "error": "Summon owner binding is invalid"}
	if owner_value != null and not owners.has(owner_value) and not existing.has(owner_value):
		return {"ok": false, "error": "Summon owner instance does not exist"}
	var tick_value: Variant = item.get(_fields["spawn_tick"], null)
	if typeof(tick_value) != TYPE_INT or tick_value < 0:
		return {"ok": false, "error": "Summon spawn tick is invalid"}
	if from_snapshot:
		var seq_value: Variant = item.get(_fields["seq"], null)
		var state_value: Variant = item.get(_fields["state"], null)
		if typeof(seq_value) != TYPE_INT or seq_value < 0:
			return {"ok": false, "error": "Summon registration sequence is invalid"}
		if not state_value is String or state_value != _states["active"]:
			return {"ok": false, "error": "Summon state is not active"}
	return {"ok": true, "item": item.duplicate(true)}


func _active_count() -> int:
	var count: int = 0
	for item in _summons.values():
		if item[_fields["state"]] == _states["active"]:
			count += 1
	return count


func _oldest_id() -> String:
	var candidate: String = ""
	for id in _summons:
		var item: Dictionary = _summons[id]
		if item[_fields["state"]] != _states["active"]:
			continue
		if candidate.is_empty() or _comes_before(item, _summons[candidate]):
			candidate = id
	return candidate


func _comes_before(left: Dictionary, right: Dictionary) -> bool:
	return left[_fields["seq"]] < right[_fields["seq"]]


func _by_order(left: Variant, right: Variant) -> bool:
	return _comes_before(_summons[left], _summons[right])


func _purge(id: String, reason: String, output: Array) -> bool:
	if not _summons.has(id):
		return false
	var item: Dictionary = _summons[id]
	item[_fields["state"]] = _states["purged"]
	var record: Dictionary = {}
	record[_record_fields["type"]] = _reasons["owner_death"] if reason == _reasons["owner_death"] else _reasons["limit"]
	record[_record_fields["id"]] = id
	record[_record_fields["reason"]] = reason
	record[_record_fields["seq"]] = item[_fields["seq"]]
	record[_record_fields["spawn_tick"]] = item[_fields["spawn_tick"]]
	_records.append(record)
	output.append(record.duplicate(true))
	_summons.erase(id)
	return true


func _valid_id(value: Variant) -> bool:
	return value is String and not value.is_empty()


func _result_error(result: Dictionary, message: String) -> Dictionary:
	last_error = message
	result["error"] = message
	return result


func _fail(message: String) -> bool:
	last_error = message
	return false
