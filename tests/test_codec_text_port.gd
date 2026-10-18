extends GutTest

## U-25 守门：CfgCodec 的实例文本编解码层（parse_text / encode）。
## save_flow.configure() 只认文本方法名（parse_text… / encode…），
## 而 CfgCodec 此前只有文件入口 load_cfg/save_cfg，导致 UI 接线无法通过其探测。

const CfgCodecPort = preload("res://skill_core/schema/cfg_codec.gd")


func _valid_cfg() -> Dictionary:
	return {
		"schema_version": "0.1",
		"skill_id": "mage_projectile_bolt",
		"meta": {"name": "测试技能", "tags": []},
		"bricks": [{
			"brick_id": "projectile_bolt",
			"name": "弹道",
			"tagline": "向前发射",
			"carrier": "independent",
			"summary": "发射一个弹体",
			"default_cfg": {},
			"author_params": [],
			"locked_params": {},
			"relic_params": {},
			"presentation": [],
			"player_text": ["发射弹体"],
			"status": "已登记",
		}],
		"params": {"empty_list": [], "enabled": true, "speed": 2.5},
		"presentation": {
			"fx": {}, "sfx": {}, "anim": {}, "trail": {},
			"camera": {}, "damage_number": {}, "status_icon": {},
		},
		"runtime_hints": {},
	}


func test_port_exposes_the_two_method_names_save_flow_probes() -> void:
	var codec: RefCounted = CfgCodecPort.new()
	assert_true(codec.has_method("parse_text"), "save_flow 的解析探测首要候选是 parse_text")
	assert_true(codec.has_method("encode"), "save_flow 的序列化探测候选含 encode")


func test_encode_then_parse_text_round_trips_deep_equal() -> void:
	var codec: RefCounted = CfgCodecPort.new()
	var cfg: Dictionary = _valid_cfg()
	var text: String = codec.encode(cfg)
	assert_false(text.is_empty(), "encode 必须在合法 CFG 上产出文本: " + codec.last_error)
	var decoded: Dictionary = codec.parse_text(text)
	assert_true(bool(decoded.get("ok", false)), String(decoded.get("error", "")))
	var returned: Variant = decoded.get("cfg", null)
	assert_true(returned is Dictionary, "parse_text 必须把结果放在 cfg 键")
	if returned is Dictionary:
		assert_eq(returned, cfg, "往返必须保留完整 CFG")
	var structure_errors: Array = CfgCodecPort.validate_structure(returned)
	assert_eq(structure_errors.size(), 0, "往返后结构仍然合法")


func test_encode_does_not_mutate_input_and_is_deterministic() -> void:
	var codec: RefCounted = CfgCodecPort.new()
	var cfg: Dictionary = _valid_cfg()
	var before: String = JSON.stringify(cfg)
	var first: String = codec.encode(cfg)
	var second: String = codec.encode(cfg)
	assert_eq(JSON.stringify(cfg), before, "encode 不得修改入参")
	assert_eq(first, second, "同一输入的编码结果必须稳定")


func test_parse_text_rejects_malformed_text_and_clears_on_success() -> void:
	var codec: RefCounted = CfgCodecPort.new()
	var good: String = codec.encode(_valid_cfg())
	assert_false(good.is_empty(), "前置：需要一份合法文本")
	var bad: Dictionary = codec.parse_text("\t- :\n : :")
	assert_false(bool(bad.get("ok", true)), "非法文本必须 ok=false")
	assert_false(String(bad.get("error", "")).is_empty(), "必须给出错误原因")
	assert_null(bad.get("cfg", null), "失败时不得返回半成品 CFG")
	assert_false(codec.last_error.is_empty(), "失败原因必须留在 last_error")
	var recovered: Dictionary = codec.parse_text(good)
	assert_true(bool(recovered.get("ok", false)), "失败后仍能解析合法文本")
	assert_eq(codec.last_error, "", "成功一次必须清空上次的错误，不许残留")


func test_parse_text_rejects_non_map_top_level() -> void:
	var codec: RefCounted = CfgCodecPort.new()
	var decoded: Dictionary = codec.parse_text("- 1\n- 2")
	assert_false(bool(decoded.get("ok", true)), "顶层是序列时必须失败")
	assert_true(String(decoded.get("error", "")).contains("map"), "错误要点名期望的顶层类型")


func test_encode_refuses_structurally_invalid_cfg_with_named_error() -> void:
	var codec: RefCounted = CfgCodecPort.new()
	var broken: Dictionary = _valid_cfg()
	broken.erase("schema_version")
	var text: String = codec.encode(broken)
	assert_eq(text, "", "结构非法时必须返回空串，不许产出半合法文本")
	assert_false(codec.last_error.is_empty(), "必须点名失败原因，而不是静默返回空")
	var recovered: String = codec.encode(_valid_cfg())
	assert_false(recovered.is_empty(), "失败后仍能编码合法 CFG: " + codec.last_error)
	assert_eq(codec.last_error, "", "成功一次必须清空上次的错误")
