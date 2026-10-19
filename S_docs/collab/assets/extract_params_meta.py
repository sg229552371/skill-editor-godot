"""从 schema_v0_1.yaml 抽取参数登记元数据 -> params_meta.json（供 V-019…V-038 表驱动消费）。

只做机械展开，不做设计判断：类型/枚举/上下限/默认值/必填全部照抄 Schema；
单位为 tick 的判定只认字段名的 _ticks 后缀（真源 14.3 末段要求「单位为 tick 且类型为整数的每个实际字段」）。
"""
import json
import os
import sys

ROOT = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(ROOT, "schema_v0_1.yaml")
OUT = os.path.join(ROOT, "params_meta.json")

import yaml  # noqa: E402


def deref(node, defs, depth=0):
    if depth > 12 or not isinstance(node, dict):
        return node
    ref = node.get("$ref")
    if isinstance(ref, str) and ref.startswith("#/$defs/"):
        target = defs.get(ref.split("/")[-1])
        if target is None:
            raise SystemExit("未解析的 $ref: %s" % ref)
        merged = dict(target)
        merged.update({k: v for k, v in node.items() if k != "$ref"})
        return deref(merged, defs, depth + 1)
    return node


def primitive(node):
    """返回 (kind, info)；kind ∈ number/integer/string/boolean/array/object/unknown"""
    if not isinstance(node, dict):
        return "unknown", {}
    t = node.get("type")
    info = {}
    for key in ("minimum", "maximum", "exclusiveMinimum", "exclusiveMaximum", "minLength", "maxLength", "default"):
        if key in node:
            info[key] = node[key]
    if "const" in node:
        info["const"] = node["const"]
    if "enum" in node:
        info["enum"] = list(node["enum"])
    if t in ("integer", "number", "string", "boolean"):
        return t, info
    if t == "array":
        return "array", info
    if t == "object":
        return "object", info
    if "enum" in node:
        return "string", info
    if "const" in node:
        return "string", info
    return "unknown", info


def walk(node, path, defs, out, depth=0):
    node = deref(node, defs)
    if not isinstance(node, dict):
        return
    kind, info = primitive(node)
    if kind in ("object", "unknown") and "properties" not in node and kind != "unknown":
        pass
    if kind == "object" or "properties" in node:
        props = node.get("properties", {}) or {}
        required = set(node.get("required", []) or [])
        for key, sub in props.items():
            walk(sub, "%s.%s" % (path, key) if path else key, defs, out, depth + 1)
        # 对象自身的 additionalProperties 约束（用于 V-019 未登记字段）
        out.append({
            "path": path or "params",
            "kind": "object",
            "required": sorted(required),
            "additional_properties": node.get("additionalProperties", None),
        })
        return
    if kind == "array":
        items = deref(node.get("items"), defs)
        item_kind, item_info = primitive(items if isinstance(items, dict) else {})
        entry = {
            "path": path,
            "kind": "array",
            "item_kind": item_kind,
        }
        entry.update(info)
        if item_info:
            entry["item"] = item_info
        out.append(entry)
        if isinstance(items, dict) and "properties" in items:
            required_items = sorted(set(items.get("required", []) or []))
            out.append({
                "path": path + "[i]",
                "kind": "object",
                "required": required_items,
                "additional_properties": items.get("additionalProperties", None),
            })
            for key, sub in items["properties"].items():
                walk(sub, "%s[i].%s" % (path, key), defs, out, depth + 1)
        return
    entry = {"path": path, "kind": kind}
    entry.update(info)
    out.append(entry)


def main():
    with open(SRC, "r", encoding="utf-8") as handle:
        schema = yaml.safe_load(handle)
    defs = schema.get("$defs", {})
    params = defs.get("params")
    if params is None:
        raise SystemExit("schema 缺少 $defs.params")
    out = []
    walk(params, "", defs, out)
    leaves = []
    for entry in out:
        path = entry["path"]
        if not path:
            continue
        kind = entry.get("kind")
        if kind in ("object", "array"):
            continue
        item = {
            "path": path,
            "type": kind,
            "unit": "tick" if (kind == "integer" and path.endswith("_ticks")) else ("second" if path.endswith("_seconds") else ""),
        }
        for key in ("minimum", "maximum", "exclusiveMinimum", "exclusiveMaximum", "minLength", "maxLength", "default", "enum", "const"):
            if key in entry:
                item[key] = entry[key]
        leaves.append(item)
    tick_fields = sorted(x["path"] for x in leaves if x["unit"] == "tick")
    arrays = [{"path": e["path"], "item_kind": e.get("item_kind"), "item": e.get("item", {})} for e in out if e.get("kind") == "array"]
    objects = [{"path": e["path"], "required": e["required"], "additional_properties": e.get("additional_properties")} for e in out if e.get("kind") == "object"]
    enums = {}
    for name, node in defs.items():
        if isinstance(node, dict) and "enum" in node and isinstance(node["enum"], list):
            enums[name] = list(node["enum"])
    payload = {
        "schema_version": "0.1",
        "leaves": leaves,
        "arrays": arrays,
        "objects": objects,
        "tick_fields": tick_fields,
        "enums": enums,
        # V 规则统称 → Schema 实际落点（D-23 通则：14.1 明示路径以第 16 章／Schema 落点为准）
        "rule_field_aliases": {
            "derivations[i].produces": ["child_template"],
            "derivations[i].on": ["event"],
            "triggers[i].produces": ["action_profile", "produces"],
            "triggers[i].on": ["record"]
        },
        "restricted_reasons": ["range_end", "interrupted"],
        "_source": "schema_v0_1.yaml $defs 机械展开；unit=tick 仅按 _ticks 后缀判定；"
                   "rule_field_aliases 为 V 规则统称到 Schema 落点的显式映射（D-23 通则，别名即权威）",
    }
    with open(OUT, "w", encoding="utf-8") as handle:
        json.dump(payload, handle, ensure_ascii=False, indent=2)
    print("leaves=%d arrays=%d objects=%d tick=%d" % (len(leaves), len(arrays), len(objects), len(tick_fields)))
    print("tick fields:", tick_fields)


if __name__ == "__main__":
    sys.exit(main())
