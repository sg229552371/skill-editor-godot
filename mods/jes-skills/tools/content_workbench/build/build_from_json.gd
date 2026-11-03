## W3 正向生成 · 交付物 B：中间 JSON → Godot 资源（ResourceSaver.save）。
##
## 只读：_tmp/build_input.json（A 的产物）。只写：_tmp/dryrun/ 及其暂存/备份目录。
## 绝不写 content/gems/（真实落盘由 W5 上级 AI 统一执行）。
##
## 事务式：先在暂存目录全部生成并逐条 load() 回读自查成功，再整体替换 dryrun；
##         任一失败则保留旧的 dryrun、删除半成品，以非零退出码退出。
## 幂等：显式设置每个 sub-resource 的 scene_unique_id（Godot 默认随机生成，会破坏字节一致），
##       不写时间戳、字典键排序、数组保序；同一份输入跑两次产物逐字节一致。
##
## 跑法（-- 之后为用户参数，可覆盖默认路径）：
##   godot --headless --path . -s res://.../build/build_from_json.gd
##   godot --headless --path . -s res://.../build/build_from_json.gd -- --input <res://.../x.json> --output <res://.../dryrun>
extends SceneTree

const DEFAULT_INPUT := "res://mods/jes-skills/tools/content_workbench/_tmp/build_input.json"
const DEFAULT_OUTPUT := "res://mods/jes-skills/tools/content_workbench/_tmp/dryrun"

## 语义为整数的字段 / 参数键，必须与 read_workbook.py 的 INT_VALUE_KEYS 一致。
## 原因：Godot 的 JSON.parse_string 把所有数字（含 1）解析成 float，需按本表显式 int() 还原。
const INT_VALUE_KEYS := {
    "cast_mode": true, "cost_type": true, "damage_channel": true, "max_charges": true,
    "knee_level": true, "channel_mask": true, "op": true,
    "hit_count": true, "point_count": true, "max_count": true, "per_cast": true,
    "pierce": true, "fork_count": true, "chain_count": true, "_index": true,
}

var _input_path := DEFAULT_INPUT
var _output_dir := DEFAULT_OUTPUT
var _failures: Array[String] = []
var _id_re: RegEx


func _init() -> void:
    _id_re = RegEx.new()
    _id_re.compile("^[a-z][a-z0-9_]*$")
    _parse_args()

    var staging := _output_dir + "_staging"
    var backup := _output_dir + "_backup"
    print("W3 B：输入 = %s" % _input_path)
    print("W3 B：输出 = %s（暂存 = %s）" % [_output_dir, staging])

    if not FileAccess.file_exists(_input_path):
        _fail("找不到中间 JSON：" + _input_path)
        return
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(_input_path))
    if not (parsed is Dictionary):
        _fail("中间 JSON 解析失败，或顶层不是对象")
        return
    var data: Dictionary = parsed

    var skills: Array = []
    if data.get("skills") is Array:
        skills = data["skills"]
    var supports: Array = []
    if data.get("supports") is Array:
        supports = data["supports"]

    # 准备暂存目录；失败即退出，旧 dryrun 保持原样
    if _ensure_empty_dir(staging) != OK:
        _fail("无法准备暂存目录：" + staging)
        return

    var generated: Array[String] = []
    for i in skills.size():
        if not _build_skill(skills[i], staging, generated, i):
            _rollback(staging, backup)
            _fail("生成技能时失败，已保留旧产物、清理半成品")
            return
    for i in supports.size():
        if not _build_support(supports[i], staging, generated, i):
            _rollback(staging, backup)
            _fail("生成辅助石时失败，已保留旧产物、清理半成品")
            return

    # 全部生成 + 自查通过 → 整体替换
    if not _commit(staging, _output_dir, backup):
        _rollback(staging, backup)
        _fail("事务提交失败，已保留旧产物、清理半成品")
        return

    print("W3 B 完成：共生成 %d 个 .tres，逐条 load() 回读自查全部通过" % generated.size())
    for g in generated:
        print("  产物：" + _output_dir + "/" + g.get_file())
    quit(0)


# ---------------------------------------------------------------- 参数 ----
func _parse_args() -> void:
    var args := OS.get_cmdline_user_args()
    var i := 0
    while i < args.size():
        var a := String(args[i])
        if a == "--input" and i + 1 < args.size():
            _input_path = String(args[i + 1])
            i += 2
        elif a == "--output" and i + 1 < args.size():
            _output_dir = String(args[i + 1])
            i += 2
        else:
            i += 1


# ------------------------------------------------------------ 事务目录 ----
func _ensure_empty_dir(path: String) -> int:
    if not DirAccess.dir_exists_absolute(path):
        return DirAccess.make_dir_recursive_absolute(path)
    for f in DirAccess.get_files_at(path):
        DirAccess.remove_absolute(path + "/" + f)
    return OK


func _remove_dir(path: String) -> void:
    if not DirAccess.dir_exists_absolute(path):
        return
    for f in DirAccess.get_files_at(path):
        DirAccess.remove_absolute(path + "/" + f)
    DirAccess.remove_absolute(path)


func _commit(staging: String, output: String, backup: String) -> bool:
    _remove_dir(backup)
    if DirAccess.dir_exists_absolute(output):
        var e := DirAccess.rename_absolute(output, backup)
        if e != OK:
            _failures.append("无法备份旧产物目录（错误码 %d）" % e)
            return false
    var e2 := DirAccess.rename_absolute(staging, output)
    if e2 != OK:
        _failures.append("无法把暂存目录替换为正式产物（错误码 %d）" % e2)
        return false
    _remove_dir(backup)
    return true


func _rollback(staging: String, backup: String) -> void:
    _remove_dir(staging)
    if DirAccess.dir_exists_absolute(backup) and not DirAccess.dir_exists_absolute(_output_dir):
        DirAccess.rename_absolute(backup, _output_dir)


func _fail(msg: String) -> void:
    print("W3 B：失败 —— " + msg)
    for f in _failures:
        print("  · " + f)
    push_error("W3 B 失败：" + msg)
    quit(1)


# ------------------------------------------------------------ 类型还原 ----
func _sn(v: Variant) -> StringName:
    return StringName(str(v))


func _sn_array(v: Variant) -> Array[StringName]:
    var out: Array[StringName] = []
    if v is Array:
        for e in v:
            out.append(_sn(e))
    return out


func _i(v: Variant) -> int:
    return 0 if v == null else int(v)


func _f(v: Variant) -> float:
    return 0.0 if v == null else float(v)


## JSON 的 Variant → .tres 需要的精确类型。
## 字典键与字符串值一律 StringName（与现有 .tres 一致）；整数键按 INT_VALUE_KEYS 还原成 int；
## 其余数字为 float；字典键排序、数组保序；嵌套 buff_mods / path_damage / behavior_overrides 递归处理。
func _coerce(v: Variant, key: String) -> Variant:
    if v == null:
        return null
    if v is bool:
        return v
    if v is String:
        return StringName(v)
    if v is Dictionary:
        var out := {}
        var ks: Array = (v as Dictionary).keys()
        ks.sort()
        for k in ks:
            out[StringName(str(k))] = _coerce((v as Dictionary)[k], str(k))
        return out
    if v is Array:
        var arr: Array = []
        for e in v:
            arr.append(_coerce(e, key))
        return arr
    if INT_VALUE_KEYS.has(key):
        return int(v)
    return float(v)


func _valid_id(id: String) -> bool:
    return _id_re.search(id) != null


# ------------------------------------------------------------ 构造资源 ----
func _build_skill(d: Variant, staging: String, generated: Array[String], idx: int) -> bool:
    if not (d is Dictionary):
        _failures.append("skills 第 %d 条不是对象" % idx)
        return false
    var j: Dictionary = d
    var gem_id := str(j.get("gem_id", ""))
    if not _valid_id(gem_id):
        _failures.append("技能代号『%s』不是合法资源文件名" % gem_id)
        return false
    var path := staging + "/" + gem_id + ".tres"

    # 仅当输入含该字段时才赋值；缺省字段保留 SkillData 自身的 @export 默认值
    var s := SkillData.new()
    s.gem_id = _sn(gem_id)
    if j.has("display_name"): s.display_name = str(j["display_name"])
    if j.has("cast_mode"): s.cast_mode = _i(j["cast_mode"])
    if j.has("cost_type"): s.cost_type = _i(j["cost_type"])
    if j.has("base_cost"): s.base_cost = _f(j["base_cost"])
    if j.has("base_cooldown"): s.base_cooldown = _f(j["base_cooldown"])
    if j.has("base_cast_time"): s.base_cast_time = _f(j["base_cast_time"])
    if j.has("max_charges"): s.max_charges = _i(j["max_charges"])
    if j.has("charge_recharge_time"): s.charge_recharge_time = _f(j["charge_recharge_time"])
    if j.has("tags"): s.tags = _sn_array(j["tags"])
    if j.has("allowed_support_tags"): s.allowed_support_tags = _sn_array(j["allowed_support_tags"])

    # sub-resource 的 id 必须显式固定，否则 ResourceSaver 每次随机生成，破坏幂等
    var scale := GemLevelScaling.new()
    scale.set_scene_unique_id("Resource_%s_scale" % gem_id)
    var ls: Dictionary = {}
    if j.get("level_scaling") is Dictionary:
        ls = j["level_scaling"]
    if ls.has("per_level"): scale.per_level = _f(ls["per_level"])
    if ls.has("knee_level"): scale.knee_level = _i(ls["knee_level"])
    if ls.has("per_level_late"): scale.per_level_late = _f(ls["per_level_late"])
    s.level_scaling = scale

    var parts: Array[SkillPart] = []
    var jparts: Array = []
    if j.get("parts") is Array:
        jparts = j["parts"]
    for pi in jparts.size():
        var pj: Dictionary = {}
        if jparts[pi] is Dictionary:
            pj = jparts[pi]
        var p := SkillPart.new()
        p.set_scene_unique_id("Resource_%s_part%d" % [gem_id, pi])
        if pj.has("damage_channel"): p.damage_channel = _i(pj["damage_channel"])
        if pj.has("damage_effectiveness"): p.damage_effectiveness = _f(pj["damage_effectiveness"])
        if pj.has("behavior_id"): p.behavior_id = _sn(pj["behavior_id"])
        if pj.has("base_damage"): p.base_damage = _coerce(pj["base_damage"], "base_damage")
        if pj.has("behavior_params"): p.behavior_params = _coerce(pj["behavior_params"], "behavior_params")
        parts.append(p)
    s.parts = parts

    var err := ResourceSaver.save(s, path)
    if err != OK:
        _failures.append("保存 %s 失败（错误码 %d）" % [path, err])
        return false
    var back := load(path) as SkillData
    if back == null:
        _failures.append("技能 %s 回读失败（load 返回的不是 SkillData）" % gem_id)
        return false
    if not _verify(j, back, "技能 %s" % gem_id):
        return false
    generated.append(path)
    return true


func _build_support(d: Variant, staging: String, generated: Array[String], idx: int) -> bool:
    if not (d is Dictionary):
        _failures.append("supports 第 %d 条不是对象" % idx)
        return false
    var j: Dictionary = d
    var support_id := str(j.get("support_id", ""))
    if not _valid_id(support_id):
        _failures.append("辅助石代号『%s』不是合法资源文件名" % support_id)
        return false
    var path := staging + "/" + support_id + ".tres"

    # 仅当输入含该字段时才赋值；缺省字段保留 SupportGemData 自身的 @export 默认值
    var g := SupportGemData.new()
    g.support_id = _sn(support_id)
    if j.has("display_name"): g.display_name = str(j["display_name"])
    if j.has("require_tags"): g.require_tags = _sn_array(j["require_tags"])
    if j.has("require_any_tags"): g.require_any_tags = _sn_array(j["require_any_tags"])
    if j.has("add_tags"): g.add_tags = _sn_array(j["add_tags"])
    if j.has("exclude_tags"): g.exclude_tags = _sn_array(j["exclude_tags"])
    if j.has("cost_multiplier"): g.cost_multiplier = _f(j["cost_multiplier"])
    if j.has("behavior_overrides"): g.behavior_overrides = _coerce(j["behavior_overrides"], "behavior_overrides")
    if j.has("flags"): g.flags = _sn_array(j["flags"])
    if j.has("conflicts_with"): g.conflicts_with = _sn_array(j["conflicts_with"])

    var mods: Array[ModifierSpec] = []
    var jmods: Array = []
    if j.get("stat_modifiers") is Array:
        jmods = j["stat_modifiers"]
    for mi in jmods.size():
        var mj: Dictionary = {}
        if jmods[mi] is Dictionary:
            mj = jmods[mi]
        var m := ModifierSpec.new()
        m.set_scene_unique_id("Resource_%s_mod%d" % [support_id, mi])
        if mj.has("stat"): m.stat = _sn(mj["stat"])
        if mj.has("op"): m.op = _i(mj["op"])
        if mj.has("value"): m.value = _f(mj["value"])
        if mj.has("channel_mask"): m.channel_mask = _i(mj["channel_mask"])
        if mj.has("require_tags"): m.require_tags = _sn_array(mj["require_tags"])
        if mj.has("exclude_tags"): m.exclude_tags = _sn_array(mj["exclude_tags"])
        mods.append(m)
    g.stat_modifiers = mods

    var err := ResourceSaver.save(g, path)
    if err != OK:
        _failures.append("保存 %s 失败（错误码 %d）" % [path, err])
        return false
    var back := load(path) as SupportGemData
    if back == null:
        _failures.append("辅助石 %s 回读失败（load 返回的不是 SupportGemData）" % support_id)
        return false
    if not _verify(j, back, "辅助石 %s" % support_id):
        return false
    generated.append(path)
    return true


# ------------------------------------------------------------ 回读自查 ----
func _verify(j: Dictionary, back: Resource, label: String) -> bool:
    var ok := true
    for k in j.keys():
        # 回读侧按输入侧的键/结构「投影」，保证两边键集合一致后再比较
        var expected := JSON.stringify(_norm(j[k]))
        var actual := JSON.stringify(_norm(_project(back.get(k), j[k])))
        if expected != actual:
            _failures.append("%s.%s 期望 %s，回读 %s" % [label, k, expected, actual])
            ok = false
    return ok


## 把回读的 Resource / Array[Resource] 按输入 JSON 的结构投影成普通字典/数组。
func _project(v: Variant, template: Variant) -> Variant:
    if v is Resource and template is Dictionary:
        var out := {}
        for k in (template as Dictionary).keys():
            out[k] = _project(v.get(k), (template as Dictionary)[k])
        return out
    if v is Array and template is Array:
        var arr: Array = []
        var tpl: Array = template
        for i in (v as Array).size():
            var t: Variant = tpl[i] if i < tpl.size() else null
            arr.append(_project((v as Array)[i], t))
        return arr
    return v


## 规范化：StringName→String、int→float、字典键排序并转成 String、数组保序。
## 这样输入 JSON 与 load() 回来的 Variant 可以逐字节比较字符串。
func _norm(v: Variant) -> Variant:
    if v == null:
        return null
    if v is bool:
        return v
    if v is StringName:
        return String(v)
    if v is String:
        return String(v)
    if v is int or v is float:
        return float(v)
    if v is Dictionary:
        var out := {}
        var ks: Array = (v as Dictionary).keys()
        ks.sort()
        for k in ks:
            out[String(k)] = _norm((v as Dictionary)[k])
        return out
    if v is Array:
        var arr: Array = []
        for e in v:
            arr.append(_norm(e))
        return arr
    return v
