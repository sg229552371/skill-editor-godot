# T-078 20.1.1 填卡材料（静态设计卡，不是运行凭据）

> 本文件在引擎执行权归审核方的前提下落盘。它记录第 2 轮实现的真实卡输入，**不是** `CfgCodec` 或编辑器运行输出；内容指纹、schema-clean 结论与路径运行结果必须由审核方门禁补写。CFG 运行时目标与 handler 不写入此文件，按 U-34 仅经 `create_sim_with_hosts` 的 `hosts` 参数传入。

## 目标落盘位置

```text
user://t078/t078_case.skillcfg
```

禁止在 `res://` 新建 CFG。

## CFG 原文（计划输入）

```yaml
schema_version: "0.1"
skill_id: mage_active_t078
meta:
  role: mage
  category: active
  short_name: t078
  name: T078
  version: "1"
  author: test
bricks:
  - brick_id: projectile_bolt
    name: 直线飞弹
    tagline: T078
    carrier: independent
    summary: M6 host input card
    default_cfg:
      template_id: t078_root
      shot_id: t078_shot
    author_params: []
    locked_params: {}
    relic_params: {}
    presentation: []
    player_text:
      - M6 host input card
    status: 已登记
  - brick_id: projectile_bolt
    name: 直线飞弹
    tagline: T078
    carrier: independent
    summary: M6 host input card
    default_cfg:
      template_id: t078_root
      shot_id: t078_shot
    author_params: []
    locked_params: {}
    relic_params: {}
    presentation: []
    player_text:
      - M6 host input card
    status: 已登记
params:
  carrier: independent
  lifetime_ticks: 4
  templates:
    - template_id: t078_root
      carrier: independent
      lifetime_ticks: 4
      targeting:
        target_group: enemy
      motion:
        mode: straight
        speed: 1.25
      geometry:
        shape: circle
        radius: 0.125
      hit_policy:
        per_target_limit: 1
        max_hits: 1
      parts:
        - part_index: 0
          type: physical
          amount: 2.5
      derivations: []
  max_generation: 1
  cast_budget: 1
  safety:
    max_chain_depth: 3
presentation:
  fx: {}
  sfx:
    max_concurrency: 0
  anim: {}
  trail:
    carrier: independent
  camera: {}
  damage_number: {}
  status_icon: {}
runtime_hints: {}
```

`part_type` is `physical`, read from `data/params_meta.json`; all other values above are the concrete input used by `tests/test_m6_end_to_end.gd`.

## 路径表

| 路径 | 作用 | 登记/暴露/锁定 |
|---|---|---|
| `bricks[0].brick_id` | 已登记积木身份 | 登记；锁定身份 |
| `bricks[1].brick_id` | 第二个根的已登记积木身份 | 登记；锁定身份 |
| `bricks[0].carrier` | 独立体运行载体 | 登记；锁定 |
| `bricks[0].default_cfg.template_id` | 根模板路由 | 登记；锁定 |
| `bricks[0].default_cfg.shot_id` | 根出手路由 | 登记；锁定 |
| `params.templates[0].parts[0].type` | 结算份类型 | 登记；锁定为素材枚举 |
| `params.templates[0].parts[0].amount` | 结算数值 | 登记；测试破坏对照改动 |
| `params.templates[0].motion.speed` | 运动速度 | 登记；测试破坏对照可改 |
| `params.templates[0].geometry.radius` | 接触半径 | 登记；锁定规则由 schema/validator 判定 |
| `params.templates[0].hit_policy.per_target_limit` | 单目标命中上限 | 登记；锁定规则由 schema/validator 判定 |
| `params.templates[0].hit_policy.max_hits` | 总命中上限 | 登记；锁定规则由 schema/validator 判定 |
| `presentation.anim` | 表现段 | 未启用；本卡不消费、不断言 V-074 |
| `runtime_hints` | 运行提示 | 登记；不承载运行态 |

## 宿主输入（不属于 CFG）

- `targets`: 一个 `enemy_one`，位置 `Vector2(1.25, 0)`，初始 `hp=100.0`、存活、无敌关闭、该卡 part_type 的 evade=0、immune=false。
- `handlers`: 按 `data/params_meta.json` 的 `enums.part_type` 全量建表；实际使用的 part_type 绑定 `_settle_part`，其余类型绑定显式返回 `false` 的 `_unsupported_part`。
- `seed`: `17`。
- 同一 `cfg`、`targets`、`handlers`、`seed` 同时供正式入口与直接 PreviewRunner 对照；运行态不会回写 CFG。

## 当前状态

尚未由 Godot/GUT 执行，未认证 schema-clean、指纹或实际路径表输出。审核方串行门禁后应将实际 CFG 原文、诊断数组和内容指纹追加到本目录的运行凭据中。
