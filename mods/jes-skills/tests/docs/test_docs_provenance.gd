# 文档来源门禁（《信息来源与真源清单》R1 / R3、决策 D-16）。
#
# 目的：阻止「文档里写项目外绝对路径」这种断链引用再次出现。
#
# 为什么必须自动化：2026-10-20 的事故不是笔误，而是整份文档引用了项目外的文件
# （换机器 / 换 AI 就不存在）。这类文字读起来完全合理，人工 review 抓不住；
# 只有机器能稳定拦住。
#
# 白名单说明：「信息来源与真源清单」本身要记录 E-01~E-05 的原位置用于审计，
# 因此单独豁免——那是唯一的合法例外，新增豁免必须在这里写明理由。
extends GutTest

const DOCS_DIR := "res://mods/jes-skills/docs"

## 唯一豁免：清单自身必须能写出「哪些外部来源已作废」。
const ALLOW_EXTERNAL_PATH: Array[String] = ["信息来源与真源清单.md"]

## 缺任何一个，都说明「单一真源」被拆散了。
const REQUIRED_DOCS: Array[String] = [
	"施工规格_Godot技能系统_AI执行版_v1.0.md",
	"踩坑与决策台账.md",
	"开工提示词.md",
	"信息来源与真源清单.md",
	"reference/README.md",
]

## 项目外路径特征：盘符 + 分隔符，或已知的姊妹项目目录名。
## 注意：`res://` / `user://` / `uid://` 会被 `s:/` 这种形式误伤，判定前先剥掉协议前缀。
const EXTERNAL_PATH_PATTERN := "[A-Za-z]:[/\\\\]"
const EXTERNAL_DIR_MARKERS: Array[String] = ["S_docs"]
const RES_PROTOCOLS: Array[String] = ["res://", "user://", "uid://"]


func _md_files() -> PackedStringArray:
	var out := PackedStringArray()
	var dir := DirAccess.open(DOCS_DIR)
	if dir == null:
		return out
	for f in dir.get_files():
		if f.ends_with(".md"):
			out.append(f)
	return out


func test_docs_dir_is_readable() -> void:
	assert_not_null(DirAccess.open(DOCS_DIR), "docs 目录必须存在")
	assert_gt(_md_files().size(), 0, "docs 下至少要有一份 markdown 文档")


func test_required_docs_present() -> void:
	for name in REQUIRED_DOCS:
		var path := "%s/%s" % [DOCS_DIR, name]
		assert_true(FileAccess.file_exists(path), "必需的真源文档缺失：%s" % name)


func test_no_external_path_in_docs() -> void:
	var re := RegEx.new()
	assert_eq(re.compile(EXTERNAL_PATH_PATTERN), OK, "正则必须可编译")

	var bad: Array[String] = []
	for f in _md_files():
		if ALLOW_EXTERNAL_PATH.has(f):
			continue
		var text := FileAccess.get_file_as_string("%s/%s" % [DOCS_DIR, f])
		var lines := text.split("\n")
		for i in lines.size():
			var line: String = lines[i]
			var probe := line
			for protocol in RES_PROTOCOLS:
				probe = probe.replace(protocol, "")
			var hit := re.search(probe) != null
			if not hit:
				for marker in EXTERNAL_DIR_MARKERS:
					if line.contains(marker):
						hit = true
						break
			if hit:
				bad.append("%s:%d  %s" % [f, i + 1, line.strip_edges().substr(0, 80)])

	assert_eq(
		bad.size(), 0,
		"文档不得引用项目外路径（R3）。需要外部依据：请人类投放至 docs/reference/ 并登记。\n"
		+ "\n".join(bad)
	)


func test_every_doc_is_registered_in_provenance() -> void:
	# 「新增文档但不登记」会让下个 AI 不知道该读谁、谁优先。
	var register_path := "%s/信息来源与真源清单.md" % DOCS_DIR
	var register := FileAccess.get_file_as_string(register_path)
	assert_ne(register.length(), 0, "来源清单必须可读且非空")

	var missing: Array[String] = []
	for f in _md_files():
		if f == "信息来源与真源清单.md":
			continue
		if not register.contains(f):
			missing.append(f)

	assert_eq(missing.size(), 0, "下列文档未在来源清单 §四 登记：\n" + "\n".join(missing))
