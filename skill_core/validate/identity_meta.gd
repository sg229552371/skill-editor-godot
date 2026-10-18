class_name IdentityMeta
extends RefCounted

## 身份校验元数据的唯一入口（V-001…V-018 用）。
## 元数据从 res://data/identity_meta.json 抽取，运行期不解析 Schema YAML，也不读设计文档（D-21）。
## 抽取源与口径见 JSON 内 _source 字段；改口径改素材，不改本文件。

const META_PATH: String = "res://data/identity_meta.json"

static var _loaded: bool = false
static var _valid: bool = false
static var _meta: Dictionary = {}

var last_error: String = ""

static func load_metadata(path: String = META_PATH) -> Dictionary:
	if _loaded and path == META_PATH:
		return _meta.duplicate(true) if _valid else {}
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		_loaded = path == META_PATH
		_valid = false
		_meta = {}
		return {}
	var text: String = file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		_loaded = path == META_PATH
		_valid = false
		_meta = {}
		return {}
	var meta: Dictionary = parsed
	if path == META_PATH:
		_meta = meta.duplicate(true)
		_valid = true
		_loaded = true
	return meta.duplicate(true)

## 供宿主显式判空：元数据缺失必须显式失败，不能拿空表当作“没有约束”。
static func is_available(path: String = META_PATH) -> bool:
	return not load_metadata(path).is_empty()

func last_error_message(path: String = META_PATH) -> String:
	if not load_metadata(path).is_empty():
		last_error = ""
		return ""
	last_error = "身份校验元数据未载入: %s" % path
	return last_error
