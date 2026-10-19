extends GutTest

## T-081：SkillApi.save_cfg 填桩验收。
## 契约口径（U-37）：签名不动，返回包 {"ok","diagnostics"} 只增不减。
## 真源：20.1.4 保存重载 —— 保存必须先校验后落盘，且落盘内容能被重新读回。

const ApiScript = preload("res://skill_core/api/skill_api.gd")
const CodecScript = preload("res://skill_core/schema/cfg_codec.gd")
const BodyScript = preload("res://skill_core/runtime/effect_body.gd")

const TMP_DIR := "user://t081"


func before_each() -> void:
	DirAccess.make_dir_recursive_absolute(TMP_DIR)


func after_all() -> void:
	var dir := DirAccess.open(TMP_DIR)
	if dir == null:
		return
	for name in dir.get_files():
		dir.remove(name)


func _json(path: String) -> Variant:
	return JSON.parse_string(FileAccess.get_file_as_string(path))


func _cfg() -> Dictionary:
	var catalog: Array = _json("res://data/bricks/brick_catalog.json")
	var entry: Dictionary = {}
	for candidate in catalog:
		if candidate["carrier"] == BodyScript.CARRIER_INDEPENDENT:
			entry = candidate
			break
	var meta: Dictionary = _json("res://data/params_meta.json")
	var template: Dictionary = {"template_id": "t081_root", "carrier": entry["carrier"],
		"lifetime_ticks": 4, "targeting": {"target_group": "enemy"},
		"motion": {"mode": "straight", "speed": 1.25},
		"geometry": {"shape": "circle", "radius": 0.125},
		"hit_policy": {"per_target_limit": 1, "max_hits": 1},
		"parts": [{"part_index": 0, "type": meta["enums"]["part_type"][0], "amount": 2.5}],
		"derivations": []}
	return {"schema_version": "0.1", "skill_id": "mage_active_t081",
		"meta": {"role": "mage", "category": "active", "short_name": "t081",
			"name": "T081", "version": "1", "author": "test"},
		"bricks": [{"brick_id": entry["brick_id"], "name": entry["name"], "tagline": "T081",
			"carrier": entry["carrier"], "summary": "Persistence fixture",
			"default_cfg": {"template_id": "t081_root", "shot_id": "t081_shot"},
			"author_params": [], "locked_params": {}, "relic_params": {},
			"presentation": [], "player_text": ["Persistence fixture"], "status": entry["status"]}],
		"params": {"carrier": entry["carrier"], "lifetime_ticks": 4, "templates": [template],
			"max_generation": 1, "cast_budget": 4, "safety": {"max_chain_depth": 3}},
		"presentation": {"fx": {}, "sfx": {"max_concurrency": 0}, "anim": {},
			"trail": {"carrier": entry["carrier"]}, "camera": {}, "damage_number": {}, "status_icon": {}},
		"runtime_hints": {}}


# 验收 1：合法 CFG 保存成功，返回包保留 ok/diagnostics 且新增指纹与字节数。
func test_save_valid_cfg_returns_fingerprint_and_writes_file() -> void:
	var api: RefCounted = ApiScript.new()
	var path: String = TMP_DIR + "/ok.yaml"
	var result: Dictionary = api.save_cfg(path, _cfg())
	assert_true(result["ok"], str(result))
	assert_true(result.has("diagnostics"))
	assert_eq(result["diagnostics"].size(), 0)
	assert_true(FileAccess.file_exists(path), "合法 CFG 必须落盘")
	assert_false(String(result.get("fingerprint", "")).is_empty(), "必须返回内容指纹")
	assert_gt(int(result.get("bytes", 0)), 0, "必须返回字节数")
	assert_eq(String(result.get("path", "")), path)


# 验收 2：落盘文本可被 codec 重新读回，**七个顶层键名逐个对齐**（20.1.4 七键结构一致）。
func test_saved_text_reloads_with_same_identity() -> void:
	var api: RefCounted = ApiScript.new()
	var path: String = TMP_DIR + "/reload.yaml"
	var cfg: Dictionary = _cfg()
	assert_true(api.save_cfg(path, cfg)["ok"])
	var reloaded: Dictionary = CodecScript.load_cfg(path)
	assert_true(reloaded["ok"], str(reloaded))
	var data: Dictionary = reloaded["data"]
	assert_eq(data["skill_id"], cfg["skill_id"])
	var expected_keys: Array = cfg.keys()
	var actual_keys: Array = data.keys()
	expected_keys.sort()
	actual_keys.sort()
	assert_eq(actual_keys, expected_keys, "顶层七键必须逐个一致，不允许「丢一个换一个」")
	assert_eq(data["bricks"].size(), 1)


# 验收 3：结构非法 → 拒绝且**不创建文件**（证明校验在落盘之前）。
func test_structural_failure_does_not_create_file() -> void:
	var api: RefCounted = ApiScript.new()
	var path: String = TMP_DIR + "/structural.yaml"
	var broken: Dictionary = _cfg()
	broken.erase("skill_id")
	var result: Dictionary = api.save_cfg(path, broken)
	assert_false(result["ok"])
	assert_gt(result["diagnostics"].size(), 0, "必须给出诊断")
	assert_false(FileAccess.file_exists(path), "校验失败绝不能先落盘")


# 验收 4：结构合法但 Schema 非法（meta.version 类型错）→ 拒绝。
func test_schema_failure_rejects_before_write() -> void:
	var api: RefCounted = ApiScript.new()
	var path: String = TMP_DIR + "/schema.yaml"
	var broken: Dictionary = _cfg()
	broken["meta"]["version"] = 1.5
	var result: Dictionary = api.save_cfg(path, broken)
	assert_false(result["ok"], "Schema 非法必须拒绝: " + str(result))
	assert_gt(result["diagnostics"].size(), 0)
	assert_false(FileAccess.file_exists(path))


# 验收 5：既有文件在拒绝时保持原样（不允许截断/覆盖）。
func test_rejected_save_preserves_existing_file() -> void:
	var api: RefCounted = ApiScript.new()
	var path: String = TMP_DIR + "/preserve.yaml"
	assert_true(api.save_cfg(path, _cfg())["ok"])
	var before: String = FileAccess.get_file_as_string(path)
	var broken: Dictionary = _cfg()
	broken.erase("bricks")
	var rejected: Dictionary = api.save_cfg(path, broken)
	assert_false(rejected["ok"])
	assert_eq(FileAccess.get_file_as_string(path), before, "拒绝保存时不得改动既有文件")


# 验收 6：空路径显式失败，不抛异常。
func test_empty_path_fails_explicitly() -> void:
	var api: RefCounted = ApiScript.new()
	var result: Dictionary = api.save_cfg("   ", _cfg())
	assert_false(result["ok"])
	assert_gt(result["diagnostics"].size(), 0)
	assert_false(String(result.get("error", "")).is_empty())


# 验收 7：不可写路径显式失败（有诊断、无异常），且 ok/diagnostics 键仍在。
func test_unwritable_path_fails_without_throwing() -> void:
	var api: RefCounted = ApiScript.new()
	var result: Dictionary = api.save_cfg("res://__no_such_dir__/x.yaml", _cfg())
	assert_false(result["ok"])
	assert_true(result.has("ok"))
	assert_true(result.has("diagnostics"))
	assert_gt(result["diagnostics"].size(), 0)


# === T-082：load_cfg 填桩 ===

# 验收 8：合法文件加载成功，返回配置、版本判定与空诊断。
func test_load_valid_cfg_returns_identity_and_version_state() -> void:
	var api: RefCounted = ApiScript.new()
	var path: String = TMP_DIR + "/load_ok.yaml"
	assert_true(api.save_cfg(path, _cfg())["ok"])
	var loaded: Dictionary = api.load_cfg(path)
	assert_true(loaded["ok"], str(loaded))
	assert_eq(loaded["cfg"]["skill_id"], "mage_active_t081")
	assert_eq(loaded["diagnostics"].size(), 0, "合法文件不应带诊断: " + str(loaded["diagnostics"]))
	assert_eq(String(loaded["schema_version"]), "0.1")
	assert_true(bool(loaded["version_supported"]), "0.1 必须是已支持版本")
	assert_false(bool(loaded["read_only"]))
	assert_eq(String(loaded["path"]), path)
	assert_eq(loaded["data"], loaded["cfg"], "data 是 cfg 的增量别名（既有 UI 读 data）")


# 验收 9（20.1.4 保存重载凭据）：值无损 —— 深比较 + 指纹对内容敏感。
func test_save_then_load_round_trip_preserves_values() -> void:
	var api: RefCounted = ApiScript.new()
	var path: String = TMP_DIR + "/roundtrip.yaml"
	var cfg: Dictionary = _cfg()
	var saved: Dictionary = api.save_cfg(path, cfg)
	assert_true(saved["ok"], str(saved))
	var loaded: Dictionary = api.load_cfg(path)
	assert_true(loaded["ok"])
	assert_eq(_canonical(loaded["cfg"]), _canonical(cfg), "往返后逐字段值必须无损")
	assert_eq(String(loaded["fingerprint"]), String(saved["fingerprint"]), "落盘与读回必须是同一份字节")
	assert_eq(int(loaded["bytes"]), int(saved["bytes"]))
	# 反向对照：改一个叶子值，指纹必须变 —— 证伪「指纹恒等」的可能。
	var mutated: Dictionary = cfg.duplicate(true)
	mutated["params"]["lifetime_ticks"] = 5
	var other: Dictionary = api.save_cfg(TMP_DIR + "/roundtrip_mut.yaml", mutated)
	assert_true(other["ok"], str(other))
	assert_ne(String(other["fingerprint"]), String(saved["fingerprint"]), "叶子值变化必须反映到指纹")


# 验收 10：不存在的路径 → 显式失败。
func test_load_missing_file_fails_explicitly() -> void:
	var api: RefCounted = ApiScript.new()
	var result: Dictionary = api.load_cfg(TMP_DIR + "/__absent__.yaml")
	assert_false(result["ok"])
	assert_gt(result["diagnostics"].size(), 0)
	assert_true(result["cfg"] == null)


# 验收 11：顶层不是 map（语法可解析但形态非法）→ 显式失败，不返回半成品配置。
func test_load_non_mapping_root_fails_explicitly() -> void:
	var api: RefCounted = ApiScript.new()
	var path: String = TMP_DIR + "/scalar.yaml"
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string("just a plain string\n")
	file.close()
	var result: Dictionary = api.load_cfg(path)
	assert_false(result["ok"])
	assert_gt(result["diagnostics"].size(), 0)


# 验收 12（V-083）：未知 schema_version → 可打开但只读，原样返回，绝不降级/改写。
func test_unknown_schema_version_is_read_only_without_downgrade() -> void:
	var api: RefCounted = ApiScript.new()
	var path: String = TMP_DIR + "/future.yaml"
	var future: Dictionary = _cfg()
	future["schema_version"] = "9.9"
	# 用 codec 直接落盘：伪造一份「外部来源」的文件。api.save_cfg 会按 Schema 拒绝未知版本，
	# 那是保存侧的正确行为；本用例考的是加载侧面对既存未知版本文件的态度（V-083）。
	var seeded: Dictionary = CodecScript.save_cfg(path, future)
	assert_true(bool(seeded.get("ok", false)), "夹具必须真的落盘: " + str(seeded))
	var loaded: Dictionary = api.load_cfg(path)
	assert_true(loaded["ok"], "未知版本仍必须可打开（只读）")
	assert_eq(String(loaded["schema_version"]), "9.9", "不得把版本改写成当前版本")
	assert_false(bool(loaded["version_supported"]))
	assert_true(bool(loaded["read_only"]), "未知版本必须标只读")
	assert_eq(String(loaded["cfg"]["schema_version"]), "9.9", "返回内容必须与文件一致")
	# 保存侧同样受 V-083 约束：不得把未知版本「降级保存」成当前版本。
	var target: String = TMP_DIR + "/future_save.yaml"
	var rejected: Dictionary = api.save_cfg(target, future)
	assert_false(rejected["ok"], "保存侧必须拒绝未知 schema_version")
	assert_gt(rejected["diagnostics"].size(), 0)
	assert_false(FileAccess.file_exists(target), "拒绝保存时不得落盘")


# 验收 13：结构有问题但可解析 → ok:false（已知版本带 block 诊断），但仍带回内容供修复。
func test_load_structural_problem_reports_not_ok_but_returns_content() -> void:
	var api: RefCounted = ApiScript.new()
	var path: String = TMP_DIR + "/broken.yaml"
	var codec: RefCounted = CodecScript.new()
	var text: String = codec.encode(_cfg())
	assert_false(text.is_empty(), "夹具必须先是一份可序列化的合法 CFG")
	var without_id: String = text.replace("skill_id: mage_active_t081\n", "")
	assert_ne(without_id, text, "夹具必须真的删掉了 skill_id 行")
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(without_id)
	file.close()
	var loaded: Dictionary = api.load_cfg(path)
	assert_false(loaded["ok"], "已知版本带 block 诊断时 ok 必须为 false（与 CfgCodec 同口径）")
	assert_gt(loaded["diagnostics"].size(), 0, "残缺文件必须带诊断")
	assert_false(String(loaded["error"]).is_empty())
	assert_true(loaded["cfg"] is Dictionary, "失败仍须带回内容，否则编辑器无法打开修复")
	assert_eq(loaded["data"], loaded["cfg"], "data 为 cfg 的增量别名，供既有 UI 消费")



## 值比较用规范化串：字典按 key 排序、整值浮点收敛为整数（YAML 解析可能给出 float）。
func _canonical(value: Variant) -> String:
	if value is Dictionary:
		var keys: Array = value.keys()
		keys.sort()
		var parts: PackedStringArray = []
		for key in keys:
			parts.append("%s=%s" % [str(key), _canonical(value[key])])
		return "{" + ",".join(parts) + "}"
	if value is Array:
		var items: PackedStringArray = []
		for item in value:
			items.append(_canonical(item))
		return "[" + ",".join(items) + "]"
	if value is float and float(value) == floor(float(value)):
		return str(int(value))
	return str(value)
