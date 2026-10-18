"""离线抽取：把 ch04 真源里的 28 张积木卡片（YAML 代码块）抽成运行期素材 JSON。

运行期禁解析 md/yaml（D-22），所以这里离线转一次，落 `data/bricks/brick_cards.json`。
不改 `data/bricks/brick_catalog.json`（身份摘要，既有测试依赖它的键集）。
"""
import io
import json
import os
import re

import yaml

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
SRC = os.path.join(ROOT, "S_docs", "collab", "assets", "_raw_ch04_bricks.md")
OUT = os.path.join(ROOT, "data", "bricks", "brick_cards.json")

REQUIRED = ("default_cfg", "author_params", "locked_params", "relic_params")


def main() -> None:
    text = io.open(SRC, encoding="utf-8").read()
    blocks = re.findall(r"```yaml\n(.*?)```", text, re.S)
    cards = []
    problems = []
    for block in blocks:
        if "brick_id:" not in block:
            continue
        try:
            data = yaml.safe_load(block)
        except yaml.YAMLError as error:
            # 真源里有未加引号的裸反引号（如 `self` 写在 flow mapping 的值里），YAML 扫描器直接拒。
            # 反引号只是排版标记，去掉不损语义；去掉后仍解析失败就必须报错，不许静默跳过。
            cleaned = block.replace("`", "")
            try:
                data = yaml.safe_load(cleaned)
            except yaml.YAMLError:
                raise SystemExit("YAML 解析失败，修正抽取器而不是跳过：\n%s" % error)
            problems.append({"brick_id": "unknown", "note": "backtick-cleaned"})
        if not isinstance(data, dict) or "brick_id" not in data:
            continue
        missing = [key for key in REQUIRED if key not in data]
        if missing:
            problems.append({"brick_id": data.get("brick_id"), "missing": missing})
        cards.append(data)
    ids = [card["brick_id"] for card in cards]
    dup = sorted({i for i in ids if ids.count(i) > 1})
    payload = {
        "_note": "离线抽取自技能系统书 ch04 的 YAML 卡片块；运行期只读本 JSON，不解析 md/yaml（D-22）。",
        "_source": "S_docs/collab/assets/_raw_ch04_bricks.md",
        "card_count": len(cards),
        "cards": cards,
    }
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with io.open(OUT, "w", encoding="utf-8", newline="\n") as handle:
        json.dump(payload, handle, ensure_ascii=False, indent=1, sort_keys=False)
        handle.write("\n")
    print("cards:", len(cards), "dups:", dup)
    for item in problems:
        print("MISSING", item)


if __name__ == "__main__":
    main()
