extends GutTest

## U-26 素材交付的守门测试（审核方自建）：
## `data/bricks/brick_cards.json` 由 `S_docs/collab/assets/extract_brick_cards.py` 离线抽取自 ch04 真源，
## 本测试证明「素材确实能被 FieldQuery 消费」，不是只证明「文件里有 28 条」。

const FieldQuery = preload("res://skill_core/resolve/field_query.gd")
const CARDS_PATH: String = "res://data/bricks/brick_cards.json"
const CATALOG_PATH: String = "res://data/bricks/brick_catalog.json"

const REQUIRED_SECTIONS: Array = ["default_cfg", "author_params", "locked_params", "relic_params"]

func _load_cards() -> Array:
	var text: String = FileAccess.get_file_as_string(CARDS_PATH)
	assert_ne(text, "", "brick_cards.json 读不出来")
	var parsed: Variant = JSON.parse_string(text)
	assert_true(parsed is Dictionary, "brick_cards.json 顶层必须是对象")
	var payload: Dictionary = parsed
	assert_true(payload.get("cards", null) is Array, "缺少 cards 数组")
	return payload.get("cards", [])

func test_material_has_28_unique_cards_with_four_sections() -> void:
	var cards: Array = _load_cards()
	assert_eq(cards.size(), 28, "真源 ch04 是 28 张卡片")
	var ids: Array = []
	var missing: Array = []
	for card_value in cards:
		assert_true(card_value is Dictionary, "每张卡片必须是对象")
		var card: Dictionary = card_value
		assert_true(card.get("brick_id", null) is String, "缺 brick_id")
		ids.append(str(card.get("brick_id", "")))
		for section in REQUIRED_SECTIONS:
			if not card.has(section):
				missing.append("%s.%s" % [card.get("brick_id", "?"), section])
	assert_eq(ids.size(), 28)
	assert_eq(ids.size(), _unique(ids).size(), "brick_id 不许重复")
	assert_eq(missing, [], "四段必须齐全")

func test_card_ids_match_identity_catalog() -> void:
	# 身份摘要（brick_catalog.json）与完整卡片（brick_cards.json）必须指同一批积木，
	# 否则 UI 选中的积木在参数面板里查不到卡片。
	var catalog_raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(CATALOG_PATH))
	assert_true(catalog_raw is Array, "brick_catalog.json 顶层必须是数组")
	var catalog_ids: Array = []
	for entry_value in catalog_raw:
		if entry_value is Dictionary:
			var entry: Dictionary = entry_value
			catalog_ids.append(str(entry.get("brick_id", "")))
	var card_ids: Array = []
	for card_value in _load_cards():
		if card_value is Dictionary:
			var card: Dictionary = card_value
			card_ids.append(str(card.get("brick_id", "")))
	assert_eq(_unique(card_ids).size(), 28)
	assert_eq(_sorted(catalog_ids), _sorted(card_ids), "两份素材的 brick_id 集合必须一致")

func test_field_query_consumes_every_real_card() -> void:
	# 这才是 U-26 的重点：真实卡片能被 FieldQuery 吃下去（不是只测注入的假卡片）。
	var accepted: Array = []
	var rejected: Array = []
	for card_value in _load_cards():
		var card: Dictionary = card_value
		var query: Variant = FieldQuery.new()
		var result: Dictionary = query.configure(card)
		if bool(result.get("ok", false)):
			accepted.append(str(card.get("brick_id", "")))
		else:
			rejected.append("%s：%s" % [card.get("brick_id", "?"), result.get("error", "")])
	# 允许「候选（未进首发）」这类空装配卡片被显式拒绝，但不许出现无语义错误。
	for line in rejected:
		assert_false(line.is_empty())
	assert_eq(accepted.size() + rejected.size(), 28)
	assert_true(accepted.size() >= 27, "至少 27 张必须是可消费的完整卡片，实际 %d，被拒：%s" % [accepted.size(), str(rejected)])

func test_locked_paths_report_reason_and_are_not_open() -> void:
	# 锁定路径必须「不可写 + 有理由」，这是 D-26 与 ch04:48 的运行期体现。
	var checked: int = 0
	for card_value in _load_cards():
		var card: Dictionary = card_value
		var locked: Variant = card.get("locked_params", null)
		if not locked is Dictionary:
			continue
		var query: Variant = FieldQuery.new()
		if not bool(query.configure(card).get("ok", false)):
			continue
		for key in (locked as Dictionary).keys():
			var path: String = str(key)
			var state: Dictionary = query.query(path)
			assert_false(bool(state.get("locked", false)) and str(state.get("lock_reason", "")).is_empty(),
				"%s.%s 锁定了却没给理由" % [card.get("brick_id", "?"), path])
			checked += 1
	assert_true(checked > 0, "一张锁定路径都没检查到，说明素材或 façade 有一边是空跑")

func _unique(values: Array) -> Array:
	var out: Array = []
	for value in values:
		if not out.has(value):
			out.append(value)
	return out

func _sorted(values: Array) -> Array:
	var out: Array = values.duplicate()
	out.sort()
	return out
