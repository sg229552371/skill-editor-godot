# -*- coding: utf-8 -*-
"""离线素材抽取（审核方 WorkBuddy 执行，非运行时）。

从 schema_v0_1.yaml 的 $defs 抽取 presentation 七段 + runtime_hints 的字段描述，
合并审核方裁定（段启用判据 / 拖尾关系 / 数字合并 / 订阅禁值 / 逻辑回写），
产出 res://data/presentation_meta.json（给 T-013 r_present.gd 消费）。

运行时禁止解析 yaml/md（D-21）；本脚本只在素材准备阶段离线跑一次。
"""
import json
import os
import yaml

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
SCHEMA = os.path.join(ROOT, "S_docs", "collab", "assets", "schema_v0_1.yaml")
PARAMS = os.path.join(ROOT, "data", "params_meta.json")
OUT = os.path.join(ROOT, "data", "presentation_meta.json")

SECTIONS = ["fx", "sfx", "anim", "trail", "camera", "damage_number", "status_icon"]
PREFIX = "presentation"

with open(SCHEMA, "r", encoding="utf-8") as fh:
    schema = yaml.safe_load(fh)
with open(PARAMS, "r", encoding="utf-8") as fh:
    params_meta = json.load(fh)

defs = schema.get("$defs", {})


def resolve(spec):
    """把 $ref 解析为 object 描述。"""
    if not isinstance(spec, dict):
        return {}
    if "$ref" in spec and isinstance(spec["$ref"], str):
        name = spec["$ref"].split("/")[-1]
        return {"type": "object", "_ref": name}
    return spec


def leaf_entry(path, spec):
    if "type" not in spec and "const" in spec:
        ftype = "const"
    elif "type" not in spec and "$ref" in spec:
        ftype = "object"
    else:
        ftype = spec.get("type", "object")
    entry = {"path": path, "type": ftype}
    for key in ("enum", "const", "minimum", "maximum", "exclusiveMinimum",
                "exclusiveMaximum", "minLength", "minItems", "maxItems"):
        if key in spec:
            entry[key] = spec[key]
    if "default" in spec:
        entry["default"] = spec["default"]
    if "_ref" in spec:
        entry["ref"] = spec["_ref"]
    return entry


leaves, arrays, objects = [], [], []
section_field_index = {}

for section in SECTIONS:
    block = defs.get(section, {})
    props = block.get("properties", {}) or {}
    required = block.get("required", []) or []
    objects.append({
        "path": "%s.%s" % (PREFIX, section),
        "required": ["%s.%s.%s" % (PREFIX, section, r) for r in required],
        "additional_properties": bool(block.get("additionalProperties", False) is not False),
    })
    names = []
    for field, raw in props.items():
        spec = resolve(raw)
        path = "%s.%s.%s" % (PREFIX, section, field)
        names.append(field)
        ftype = spec.get("type", "object")
        if ftype == "array":
            item_raw = spec.get("items", {}) or {}
            item = resolve(item_raw)
            arrays.append({
                "path": path,
                "item_kind": item.get("type", "object"),
                "item": {k: v for k, v in item.items() if k in ("enum", "minimum", "maximum", "minLength")},
            })
        elif "_ref" in spec:
            objects.append({"path": path, "ref": spec["_ref"]})
        elif ftype == "object" and not any(k in spec for k in ("enum", "const")):
            objects.append({
                "path": path,
                "required": [],
                "additional_properties": spec.get("additionalProperties", None) is False,
            })
        else:
            leaves.append(leaf_entry(path, spec))
    section_field_index[section] = names

# runtime_hints
rh = defs.get("runtime_hints", {})
rh_props = rh.get("properties", {}) or {}
rh_leaves, rh_arrays = [], []
for field, raw in rh_props.items():
    spec = resolve(raw)
    path = "%s.%s" % ("runtime_hints", field)
    if spec.get("type") == "array":
        item = resolve(spec.get("items", {}) or {})
        rh_arrays.append({"path": path, "item_kind": item.get("type", "object"), "item": {}})
    else:
        rh_leaves.append(leaf_entry(path, spec))

# 自然原因码（V-071 的 fx.vanish_by_reason 合法键）
reasons = params_meta.get("enums", {}).get("vanish_reason")
if not reasons:
    reasons = params_meta.get("enums", {}).get("derivation_reason")
if not reasons:
    reasons = ["hit_end", "range_end", "landed", "expired", "returned", "interrupted", "instant_end"]

records = params_meta.get("enums", {}).get("record", [])

meta = {
    "schema_version": "0.1",
    "_source": "schema_v0_1.yaml $defs presentation(587-598) + fx/sfx/anim/trail/camera/damage_number/status_icon(469-586) + runtime_hints(599-608) + 书稿 14.5 表（V-070…084）",
    "_extracted_by": "WorkBuddy（审核方）",
    "_extracted_on": "2026-10-18",
    "_note": "T-013 专用表现段素材。字段类型/范围/枚举来自 Schema；语义约束（启用判据、拖尾关系、合并边界、订阅禁值、回写禁区）为审核方裁定，供表驱动消费。",

    "required_sections": SECTIONS,
    "_required_sections_note": "V-070：七类必备槽位 = Schema required；缺任一或出现第八个段 → 阻止保存，定位到实际槽位（如 presentation.fx）。",

    "additional_properties": False,
    "_additional_note": "presentation 与各子段均为 additionalProperties:false —— 未登记段/未登记键不得静默忽略。",

    "leaves": leaves,
    "arrays": arrays,
    "objects": objects,
    "_shape_note": "leaves/arrays/objects 的 path 均已带 presentation. 前缀，可直接作为诊断路径；类型、枚举、const、范围、默认值一律以此为准，不得硬编码。",

    "section_field_index": section_field_index,

    "section_enable": {
        "_note": "V-073/V-074/V-075 的『启用』判据。camera 段有 enabled 布尔开关；其余段无开关，按 activity_slots 是否有实际内容判定。",
        "_nonempty_rule": "Array：size>0；Dictionary：非空；String：strip 后非空；null/缺省：空。其它非 null 视为非空。",
        "fx": {"enabled_field": None, "activity_slots": ["spawn", "tick", "vanish", "on_hit", "on_settled"]},
        "sfx": {"enabled_field": None, "activity_slots": ["spawn", "tick_loop", "on_hit", "on_settled", "vanish"]},
        "anim": {"enabled_field": None, "activity_slots": ["cast_clip", "on_hit", "on_settled"]},
        "trail": {"enabled_field": None, "activity_slots": ["resource_ref"]},
        "camera": {"enabled_field": "enabled", "enabled_default": True, "activity_slots": []},
        "damage_number": {"enabled_field": None, "activity_slots": ["number_style_ref"]},
        "status_icon": {"enabled_field": None, "activity_slots": ["resource_ref"]},
    },
    "enabled_requires": {
        "_note": "段被判定为启用时，这些字段必须显式存在且合法；未启用（占位/禁用）时不作此要求。",
        "sfx": ["max_concurrency"],
        "anim": ["logic_release_tick", "release_frame"],
        "trail": ["carrier"],
        "camera": [],
        "fx": [],
        "damage_number": [],
        "status_icon": [],
    },
    "enabled_minimum_overrides": {
        "_note": "V-073 裁定：Schema 的 minimum 0 是类型范围；段启用时并发上限必须是正整数，故启用态下界抬升为 1。类型错与启用态越界分开定位，不互相顶替。",
        "presentation.sfx.max_concurrency": 1,
    },

    "trail_carrier_policy": {
        "carrier_field": "presentation.trail.carrier",
        "carrier_enum": ["independent", "self", "attached", "none"],
        "_instant_note": "C04-01 裁决：instant 已从载体枚举移除；瞬时外观方式用 carrier=none + instant_end_policy 表达。",
        "required_end_policy": {"independent": "presentation.trail.independent_end_policy", "none": "presentation.trail.instant_end_policy"},
        "forbidden_end_policy": {
            "self": ["presentation.trail.independent_end_policy", "presentation.trail.instant_end_policy"],
            "attached": ["presentation.trail.independent_end_policy", "presentation.trail.instant_end_policy"],
        },
        "_forbidden_note": "self/attached 拖尾随宿主消亡，结束策略不适用；仅当作者显式填写时才报错，不得因 Schema 默认值而误报。",
        "distinctness_required": True,
        "_distinctness_note": "V-075：必须区分 independent 与瞬时外观方式 —— carrier 缺失 / 未登记值 / 未显式给出对应结束策略 → 阻止保存，定位 presentation.trail.carrier 与实际结束策略字段。",
    },

    "damage_number_policy": {
        "source_enum": ["hit", "hit_settled"],
        "merge_policy_enum": ["per_hit", "per_target_tick", "per_cast", "none"],
        "fallback_total_const": True,
        "merge_scope": {"per_hit": "per_target", "per_target_tick": "per_target", "per_cast": "per_target", "none": "none"},
        "_merge_scope_note": "V-076：合并不得跨目标、不得跨份类型；per_cast 的合法分组边界仍是同一目标，不得把不同目标或不同 part type 的份并成一个数字。",
        "cross_target_forbidden": True,
        "cross_type_forbidden": True,
        "logic_writeback_forbidden": True,
        "optional_context_key": "damage_number_semantics",
        "_optional_note": "跨目标/跨类型/回写的事实由 context.damage_number_semantics（可选）提供；缺失登记 notice 并跳过，不算通过证据（D-25 failure_policy.optional_missing）。",
    },

    "subscription_fields": {
        "_note": "V-071：正式表现不得订阅 debug_record 或结算之外的调试数据；定位到实际订阅路径。",
        "fx": ["vanish_by_reason"],
        "sfx": [],
        "anim": [],
        "trail": [],
        "camera": ["trigger"],
        "damage_number": ["source"],
        "status_icon": ["source"],
    },
    "forbidden_subscription_values": ["debug_record", "budget_drop", "debug"],
    "natural_reason_keys": reasons,
    "_reason_note": "fx.vanish_by_reason 的键必须是自然原因码（purge 不是原因码，不入枚举）；出现 debug 类键 → V-071。",

    "logic_writeback": {
        "_note": "V-072：表现不得逻辑回写；动画回调不得驱动出手。定位到实际非法键。",
        "const_fields": {"presentation.camera.logic_effect": "none"},
        "enum_fields": {"presentation.anim.callback_mode": ["none", "presentation_only"]},
    },
    "logic_writeback_forbidden": True,

    "runtime_hints": {
        "_note": "V-080：runtime_hints 是非功能提示；未登记叶、或违反 const/枚举/类型 → 阻止保存，定位到实际叶路径 runtime_hints.<key>。",
        "additional_properties": False,
        "leaves": rh_leaves,
        "arrays": rh_arrays,
        "const_fields": {"runtime_hints.deterministic": True},
        "enum_fields": {"runtime_hints.rng_stream": ["logic", "presentation"]},
    },

    "debug_record": {
        "subscribable": False,
        "_note": "真源 7135 + D-24：debug_record 非事件、非结算记录，任何层不得订阅它触发逻辑；正式表现订阅它 → V-071 阻止保存。",
    },
    "settlement_records": records,
    "_settlement_records_note": "D-24：四种结算记录 = params_meta.enums.record；表现可订阅的正式结算记录以此为准。hit / vanish 不是结算记录，damage_number.source 等字段各有自己的枚举，不得互相替换。",

    "rule_field_aliases": {
        "damage_number.sources": "damage_number.source",
        "damage_number.group_by": "damage_number.merge_policy",
        "trail.carrier_mode": "trail.carrier",
        "sfx.concurrency_limit": "sfx.max_concurrency",
        "anim.alignments.shot_tick": "anim.logic_release_tick",
        "anim.alignments.frame": "anim.release_frame",
        "_aliases_note": "D-23 通则：14.5 表的定位字段是统称，实际 Schema 落点见此映射。查表前先剥离 presentation 前缀与 [i] 下标；CSV 真源原文不动，有别名以别名为准。",
    },
}

with open(OUT, "w", encoding="utf-8") as fh:
    json.dump(meta, fh, ensure_ascii=False, indent=2)
    fh.write("\n")

print("written:", OUT)
print("leaves=%d arrays=%d objects=%d runtime_hints_leaves=%d" % (len(leaves), len(arrays), len(objects), len(rh_leaves)))
print("camera.logic_effect:", [l for l in leaves if l["path"].endswith("camera.logic_effect")])
print("fallback_total:", [l for l in leaves if l["path"].endswith("fallback_total")])
print("max_concurrency:", [l for l in leaves if l["path"].endswith("max_concurrency")])
