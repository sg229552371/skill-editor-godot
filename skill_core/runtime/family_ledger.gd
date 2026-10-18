class_name RuntimeFamilyLedger extends RefCounted

## A runtime admission ledger. The host calls admit before spending ShapeHit's
## candidate quota, then may_hit before attempting settlement, record_hit after a
## successful hit, and record_judgment after every part has settled (even evaded_all).
## Neither contact nor part records are events.
const PARAMS_PATH: String = "res://data/params_meta.json"

static var _cache: Dictionary = {}
var last_error: String = ""
var _load_error: String = ""
var _clock: RefCounted
var _ready: bool = false
var _bindings: Dictionary = {}
var _permission_default: bool = false
var _members: Dictionary = {}
var _families: Dictionary = {}
var _shot_hits: Dictionary = {}
var _shot_judgments: Dictionary = {}
var _last_tick: int = -1


func _init(params_path: String = PARAMS_PATH):
	var loaded: Dictionary = _load_json(params_path)
	_load_error = loaded["error"]
	if _load_error.is_empty():
		var data: Variant = loaded["data"]
		if not data is Dictionary or not data.get("leaves", null) is Array:
			_load_error = "Missing parameter leaf registry"
		else:
			var found: bool = false
			for entry in data["leaves"]:
				if not entry is Dictionary:
					continue
				var path_value: Variant = entry.get("path", null)
				var path_text: String = path_value if path_value is String else ""
				if path_text == "templates[i].emission.shotgun_allowed":
					var type_value: Variant = entry.get("type", null)
					var type_text: String = type_value if type_value is String else ""
					if found or type_text != "boolean" or typeof(entry.get("default", null)) != TYPE_BOOL:
						_load_error = "Invalid shotgun permission declaration"
						break
					found = true
					_permission_default = entry["default"]
			if _load_error.is_empty() and not found:
				_load_error = "Missing registered shotgun permission"
	last_error = _load_error


static func _load_json(path: String) -> Dictionary:
	if _cache.has(path):
		return _cache[path].duplicate(true)
	var result: Dictionary = {"data": null, "error": ""}
	if not path.begins_with("res://data/") or not FileAccess.file_exists(path):
		result["error"] = "Family metadata missing or outside res://data/: " + path
	else:
		var file: FileAccess = FileAccess.open(path, FileAccess.READ)
		if file == null:
			result["error"] = "Cannot open family metadata: " + path
		else:
			var parser: JSON = JSON.new()
			if parser.parse(file.get_as_text()) != OK:
				result["error"] = "Invalid family JSON: " + path + ": " + parser.get_error_message()
			else:
				result["data"] = parser.data
	_cache[path] = result.duplicate(true)
	return result


static func _id(value: Variant) -> bool:
	return value is String and not value.is_empty()


static func _tick(value: Variant) -> bool:
	return typeof(value) == TYPE_INT and value >= 0


## bindings names the runtime facts supplied by the host's resolved split and
## shot routing, NOT author-writable CFG. No split/chain or shot grouping is
## inferred from template names, origin_cast_id, or coincident spawn ticks.
## {family: {id: field}, shotgun: {shot: field, independent: field, allow: field}}
func configure(clock: RefCounted, bindings: Dictionary) -> bool:
	if not _load_error.is_empty():
		return _fail(_load_error)
	if _ready or clock == null or not clock.has_method("snapshot_state"):
		return _fail("Family ledger requires an unconfigured clock")
	for section in ["family", "shotgun"]:
		var facts: Variant = bindings.get(section, null)
		if not facts is Dictionary:
			return _fail("Missing independent runtime policy binding: " + section)
		var roles: Array = ["id"] if section == "family" else ["shot", "independent", "allow"]
		for role in roles:
			if not _id(facts.get(role, null)):
				return _fail("Missing runtime policy fact: " + section + "." + role)
	_bindings = bindings.duplicate(true)
	_clock = clock
	_ready = true
	last_error = ""
	return true


## Derive.snapshot_state() provides identity, sequence, origin and source_chain.
## facts[body_id] provides separate, resolved family and shot policy identities.
## A new family_id does not replace or erase any Derive origin/source_chain.
func sync_instances(snapshot: Dictionary, facts: Dictionary) -> bool:
	if not _ready:
		return _fail("Family ledger is not configured: " + _load_error)
	var source: Variant = snapshot.get("instances", null)
	if not source is Dictionary or source.is_empty():
		return _fail("Missing nonempty derivation instance ledger")
	var next_members: Dictionary = _members.duplicate(true)
	var seqs: Dictionary = {}
	var family_key: String = _bindings["family"]["id"]
	var shot: Dictionary = _bindings["shotgun"]
	for id in source:
		var state: Variant = source[id]
		if not _id(id) or not state is Dictionary or not _id(state.get("body_id", null)) or state["body_id"] != id:
			return _fail("Invalid runtime body identity")
		var origin: Variant = state.get("origin", null)
		var chain: Variant = state.get("source_chain", null)
		var seq: Variant = state.get("seq", null)
		if not origin is Dictionary or not _id(origin.get("origin_cast_id", null)) or not _id(origin.get("origin_skill", null)):
			return _fail("Invalid runtime origin")
		if not chain is Array or chain.is_empty():
			return _fail("Invalid runtime source_chain")
		for ancestor in chain:
			if not _id(ancestor):
				return _fail("Invalid runtime ancestor ID")
		if chain[chain.size() - 1] != id:
			return _fail("Source chain must end at this body")
		if not _tick(seq) or seqs.has(seq) or not _tick(state.get("spawn_tick", null)) or typeof(state.get("purged", null)) != TYPE_BOOL:
			return _fail("Invalid runtime sequence, spawn tick or purge flag")
		seqs[seq] = true
		var parent: Variant = state.get("parent_ref", null)
		if chain.size() == 1:
			if parent != null:
				return _fail("Root has a parent")
		else:
			if not _id(parent) or chain[chain.size() - 2] != parent:
				return _fail("Descendant parent does not match source_chain")
			var parent_state: Variant = source.get(parent, null)
			if not parent_state is Dictionary or not parent_state.get("origin", null) is Dictionary:
				return _fail("Descendant has no registered parent")
			var parent_origin: Dictionary = parent_state["origin"]
			if not _id(parent_origin.get("origin_cast_id", null)) or parent_origin["origin_cast_id"] != origin["origin_cast_id"] or parent_state.get("source_chain", null) != chain.slice(0, chain.size() - 1):
				return _fail("Descendant changed origin or source lineage")
		var routing: Variant = facts.get(id, null)
		if not routing is Dictionary or not _id(routing.get(family_key, null)) or typeof(routing.get(shot["independent"], null)) != TYPE_BOOL:
			return _fail("Missing resolved family/shot facts for: " + id)
		var independent: bool = routing[shot["independent"]]
		if independent != (chain.size() == 1):
			return _fail("Only independent roots can enter a shot group")
		var shot_id: String = ""
		var allowed: bool = _permission_default
		if independent:
			if not _id(routing.get(shot["shot"], null)):
				return _fail("Independent root needs an actual shot identity")
			shot_id = routing[shot["shot"]]
			if routing.has(shot["allow"]):
				if typeof(routing[shot["allow"]]) != TYPE_BOOL:
					return _fail("Resolved shotgun permission must be bool")
				allowed = routing[shot["allow"]]
		var member: Dictionary = {"seq": seq, "origin": origin.duplicate(true), "chain": chain.duplicate(true),
			"family": routing[family_key], "shot": shot_id, "independent": independent,
			"allowed": allowed, "spawn_tick": state["spawn_tick"], "purged": state["purged"]}
		var old: Variant = next_members.get(id, null)
		if old != null and (old["seq"] != seq or old["origin"] != member["origin"] or old["chain"] != member["chain"] or old["family"] != member["family"] or old["shot"] != shot_id or old["allowed"] != allowed):
			return _fail("Runtime identity or policy was mutated")
		next_members[id] = member
	for id in _members:
		if not source.has(id):
			return _fail("Runtime instance disappeared without purge")
	_members = next_members
	last_error = ""
	return true


func _candidate_error(candidate: Dictionary) -> String:
	if not _ready:
		return "Family ledger is not configured: " + _load_error
	var id: Variant = candidate.get("body_id", null)
	var target: Variant = candidate.get("target_id", null)
	var tick: Variant = candidate.get("tick", null)
	if not _id(id) or not _id(target) or not _tick(tick) or typeof(candidate.get("alive", null)) != TYPE_BOOL:
		return "Candidate requires body_id, target_id, tick and live-target fact"
	var member: Variant = _members.get(id, null)
	if not member is Dictionary or member["purged"] or tick < member["spawn_tick"]:
		return "Candidate refers to an unknown, purged or unborn body"
	var clock_state: Variant = _clock.snapshot_state()
	if not clock_state is Dictionary or not _tick(clock_state.get("tick", null)) or tick != clock_state["tick"] or tick < _last_tick:
		return "Candidate tick must be current and monotonic"
	return ""


## A family consumes a target on the first eligible contact, including evaded_all.
## Rejected siblings never reach ShapeHit's quota, resolver or settle records.
func admit(candidate: Dictionary) -> Dictionary:
	var result: Dictionary = {"ok": false, "admitted": false, "reason": "", "error": ""}
	var error: String = _candidate_error(candidate)
	if not error.is_empty():
		return _error(result, error)
	var tick: int = candidate["tick"]
	if tick != _last_tick:
		_last_tick = tick
	var id: String = candidate["body_id"]
	var target: String = candidate["target_id"]
	var member: Dictionary = _members[id]
	result["ok"] = true
	if not candidate["alive"]:
		result["reason"] = "dead"
		return result
	var family: String = JSON.stringify([member["origin"]["origin_cast_id"], member["family"]])
	var targets: Variant = _families.get(family, null)
	if targets == null:
		targets = {}
		_families[family] = targets
	if targets.has(target) and targets[target] != id:
		result["reason"] = "family"
		return result
	targets[target] = id
	result["admitted"] = true
	last_error = ""
	return result


## Read-only preflight for an admitted contact. Only record_hit and
## record_judgment commit the separate successful-hit and all-parts ledgers.
## The host must not commit damage/parts or consume max_hits after a denial.
func may_hit(candidate: Dictionary) -> Dictionary:
	var result: Dictionary = {"ok": false, "allowed": false, "reason": "", "error": ""}
	var error: String = _candidate_error(candidate)
	if not error.is_empty():
		result["error"] = error
		return result
	var id: String = candidate["body_id"]
	var member: Dictionary = _members[id]
	var family: String = JSON.stringify([member["origin"]["origin_cast_id"], member["family"]])
	var targets: Variant = _families.get(family, null)
	if not candidate["alive"] or not targets is Dictionary or not targets.has(candidate["target_id"]) or targets[candidate["target_id"]] != id:
		result["error"] = "Hit requires a live, admitted candidate"
		return result
	result["ok"] = true
	if member["independent"] and not member["allowed"]:
		var hit_key: String = _shot_key(member, candidate["target_id"])
		var judgment_key: String = _shot_judgment_key(member, candidate["target_id"])
		var hit_blocked: bool = _shot_hits.has(hit_key) and _shot_hits[hit_key] != id
		var judgment_blocked: bool = _shot_judgments.has(judgment_key) and _shot_judgments[judgment_key] != id
		if hit_blocked or judgment_blocked:
			result["reason"] = "shotgun"
			return result
	result["allowed"] = true
	return result


## The host calls this only after every part of this target contact has settled,
## including all-evaded contacts. Registration is idempotent for the same body;
## another body cannot replace the owner of the exact cast/family/shot/target key.
func record_judgment(candidate: Dictionary) -> bool:
	var error: String = _candidate_error(candidate)
	if not error.is_empty():
		return _fail(error)
	var id: String = candidate["body_id"]
	var key: String = _shot_judgment_key(_members[id], candidate["target_id"])
	if _shot_judgments.has(key) and _shot_judgments[key] != id:
		return _fail("Shotgun judgment already recorded by another body")
	_shot_judgments[key] = id
	last_error = ""
	return true


func record_hit(candidate: Dictionary) -> bool:
	var gate: Dictionary = may_hit(candidate)
	if not gate["ok"] or not gate["allowed"]:
		return _fail(gate["error"] if not gate["error"].is_empty() else "Shotgun hit denied")
	var member: Dictionary = _members[candidate["body_id"]]
	if member["independent"]:
		_shot_hits[_shot_key(member, candidate["target_id"])] = candidate["body_id"]
	last_error = ""
	return true


func _shot_judgment_key(member: Dictionary, target: String) -> String:
	return JSON.stringify([member["origin"]["origin_cast_id"], member["family"], member["shot"], target])


func _shot_key(member: Dictionary, target: String) -> String:
	return JSON.stringify([member["origin"]["origin_cast_id"], member["shot"], target])


## Submit all candidates of a tick together. seq then target_id then part_index
## stabilizes the order; input permutations never choose a different winner.
func admit_batch(candidates: Array) -> Dictionary:
	var result: Dictionary = {"ok": false, "admitted": [], "suppressed": [], "error": ""}
	var ordered: Array = []
	for candidate in candidates:
		if not candidate is Dictionary:
			return _error(result, "Invalid batch candidate")
		var error: String = _candidate_error(candidate)
		if not error.is_empty():
			return _error(result, error)
		var part: Variant = candidate.get("part_index", 0)
		if typeof(part) != TYPE_INT or part < 0:
			return _error(result, "Invalid candidate part index")
		ordered.append(candidate.duplicate(true))
	ordered.sort_custom(_before)
	for candidate in ordered:
		var outcome: Dictionary = admit(candidate)
		if not outcome["ok"]:
			return _error(result, outcome["error"])
		if outcome["admitted"]:
			result["admitted"].append(candidate.duplicate(true))
		else:
			result["suppressed"].append({"candidate": candidate.duplicate(true), "reason": outcome["reason"]})
	result["ok"] = true
	return result


func _before(left: Dictionary, right: Dictionary) -> bool:
	var a: int = _members[left["body_id"]]["seq"]
	var b: int = _members[right["body_id"]]["seq"]
	if a != b:
		return a < b
	if left["target_id"] != right["target_id"]:
		return left["target_id"] < right["target_id"]
	return left.get("part_index", 0) < right.get("part_index", 0)


## Purge is a silent ledger cleanup, never a hit/vanish event or a derivation.
func purge(body_id: Variant) -> bool:
	if not _ready or not _id(body_id) or not _members.has(body_id):
		return _fail("Unknown family body")
	_members[body_id]["purged"] = true
	for family in _families.keys():
		var active: bool = false
		for member in _members.values():
			if not member["purged"] and JSON.stringify([member["origin"]["origin_cast_id"], member["family"]]) == family:
				active = true
				break
		if not active:
			_families.erase(family)
	var any_alive: bool = false
	for member in _members.values():
		if not member["purged"]:
			any_alive = true
			break
	if not any_alive:
		_shot_hits.clear()
		_shot_judgments.clear()
		_members.clear()
	last_error = ""
	return true


func snapshot_state() -> Dictionary:
	return {"members": _members.duplicate(true), "families": _families.duplicate(true),
		"shot_hits": _shot_hits.duplicate(true), "shot_judgments": _shot_judgments.duplicate(true),
		"last_tick": _last_tick}


func _error(result: Dictionary, message: String) -> Dictionary:
	last_error = message
	result["error"] = message
	return result


func _fail(message: String) -> bool:
	last_error = message
	return false
