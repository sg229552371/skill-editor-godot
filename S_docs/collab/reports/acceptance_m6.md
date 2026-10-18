# 第 20 章 M6 验收审计清单

## 审计口径与范围

- 任务：T-063；结论：**M6 尚不能收口**。仅审计代码、测试与既有回执，不运行引擎、不补实现、不补测试、不认证新的运行结果。
- 唯一条目真源：`S_docs/技能系统书-v1.md:4314–4482`，已逐字读取第 20 章（编辑器自身验收），不是后文运行时卷同号的“组合安全”章。
- 共 **93 行**：20.1 八步骤 + 两段约束 10 行；20.2 八例 8 行；20.3 十例 + 一段约束 11 行；20.4 二十四例 + 夹具约束 25 行；20.5 原有复选框 37 行；20.6 两段分界 2 行。没有把若干原始条目并成一行。
- 原书 ED 编号原样保留；八步骤、未编号复选框与约束段原本没有逐项数字，其 `20.x.n` 为本审计按原文顺序添加的定位号，不宣称原书自带这些编号。20.5 的编号跨五组连续排列。
- ✅ 表示按本派单口径审计到完整对应的具体测试与断言；**不表示本会话运行过测试**，也不表示测试证据已按版本及指纹认证。⚠️ 表示实现/测试只覆盖原条目的一部分；❌ 表示存在明确反证；⬜ 表示未验证或未实现。失败/缺能力探针测试即使通过，也不能把需求判为通过。
- 下列测试路径相对 `res://`；函数名均已在源文件中核对，括号说明具体断言而非引用文件总断言数。未取得逐函数运行断言数，故不杜撰“运行 N 断言”。一行列出多个函数时，各自只证明括号内部分。
- 插件接线共同限制：`addons/skill_editor/plugin.gd:1–15` 只挂载面板，`addons/skill_editor/ui/editor_panel.tscn` 仅实例化列表与积木选择器；`skill_core/api/skill_api.gd:9–66` 仍为失败桩。下文凡需实际编辑器操作均不判 ✅。不得将 T-070 等并行卡的计划当成已交付事实。
- 历史门禁仅作旁证：已读 T-050、T-051、T-053、T-054、T-060、T-061、T-062、T-027 的交付/审核内容；例如 `reports/T-053.md:142–167` 与 `T-061.md:100–125` 记载审核方 PASS，但不替代本表逐函数核验。读取的 `T-052.md:1–125` 尚为作者未运行声明，没有审核追加；因此不把派单提供的全量数字或“七条可跑”当作本轮实测输出。
- 决策编号以 `02-决策台账.md` 为准；原书运行时 D-xx 与协作台账 D-xx 不是同一命名空间（例如原书确定性 D-09 不等于台账 purge 的 D-09）。表中“台账 D-xx”专指协作台账。

## 20.1 端到端流程与交付证据

| # | 验收条目（规格书原文摘要） | 规格书位置 | 判定 | 证据 | 缺口 |
|---|---|---|---|---|---|
| 20.1.1 | 填卡：登记积木创建技能，填归属、参数、暴露、文字；单位清楚、锁定不可改；交完整卡与路径表 | 20.1，4322 | ⚠️ | `tests/test_ui_param_form.gd::test_only_opened_paths_are_rendered_and_locked_rows_are_not_editable`（拒改锁定值）；`tests/test_ui_param_form.gd::test_seconds_and_ticks_use_injected_project_rate_and_persist_integer_ticks`（60/30 Hz 得 7/4 tick）；台账 D-04、D-05 | 缺“从已登记积木创建技能”至完整设计卡的编辑器接线；归属、暴露、文字与路径表未形成一份实交证据 |
| 20.1.2 | 即时校验：非法值再修复，准确指向字段、旧诊断消失；交 V/E 与路径 | 20.1，4323 | ⚠️ | `tests/test_ui_diagnostic_panel.gd::test_empty_then_clear_returns_to_empty_state_without_stale_rows`（有诊断后清空两视图）；`tests/test_validate_identity.gd::test_v014_locked_override_reports_actual_leaf_not_parameter_object`；台账 D-06 | 缺控件提交非法值→真实 validator→修复后自动更新面板的一体流程，不把手动清空面板当修复 |
| 20.1.3 | 整卡校验：解析积木、引用、修饰器、表现，无阻止项、警告可解释，交摘要和依赖指纹 | 20.1，4324 | ⚠️ | `tests/test_validate_integration.gd::test_each_real_rule_card_is_configured_and_triggered_through_validator`（四区间新增规则）；`test_all_six_stages_run_all_real_cards_with_contracts`（六入口）；台账 D-25 | 六入口测试只断言返回诊断数组和修订号，未证明实际装配整卡无阻止项；依赖事实由测试注入，缺摘要及依赖指纹实交 |
| 20.1.4 | 保存：提交重载，七键、版本、值无损；交持久化内容与规范化差异 | 20.1，4325 | ⚠️ | `tests/test_schema_codec.gd::test_cfg_round_trip_is_deep_equal`（内存 YAML 往返）；`tests/test_ui_save_flow.gd::test_normal_save_increments_revision_and_writes_once`（假 writer 调用一次）；台账 D-02 | 缺真实保存后关闭重开、meta.version 与规范化差异报告；FakeCodec/Writer 不是落盘整链 |
| 20.1.5 | 预览：固定初态、输入、种子，符合契约，交事件/结算/调试三栏轨迹 | 20.1，4326 | ⚠️ | `tests/test_preview_runner.gd::test_complete_flight_settlement_split_and_budget_chain`；`tests/test_ui_preview_panel.gd::test_mixed_records_populate_three_distinct_columns_without_cross_routing`（2/4/2 条分类）；台账 D-00-1、D-24 | runner 与面板尚未在编辑器接线；ED-17 的 17 条 blocked 未齐，不满足“对应契约例子”全集 |
| 20.1.6 | 正式复现：持久化 CFG 在正式入口运行同夹具，逻辑与预览一致，交首差异检查 | 20.1，4327 | ⬜ | `skill_core/api/skill_api.gd::create_sim` 仍返回 NOT_IMPLEMENTED；`tests/test_preview_runner.gd::test_codec_yaml_roundtrip_and_arbitrary_ids_use_the_same_cfg_structure` 仅测试同一个沙盒 | 缺正式入口、真实持久化加载及正式/预览双入口差分；两次沙盒运行不能替代正式复现 |
| 20.1.7 | 重跑：同输入同种子逐次一致，交两次凭据与比较报告 | 20.1，4328 | ⚠️ | `tests/test_determinism.gd::test_real_diff_runs_same_seed_fresh_identity_and_cfg_not_written_back`（两条各 10 样本、末样本 hit/record 各 1、未截断）；台账 D-00-1 | 已有真实 runner 差分，缺绑定依赖、运行时、夹具版本的两份凭据与端到端交付包，不等于 T-064 完成 |
| 20.1.8 | 人审核：WorkBuddy 核对覆盖，用户拍板主观取舍，未决不冒充确认；交审核结论与未通过项 | 20.1，4329 | ⬜ | `S_docs/collab/reports/T-061.md:113–125` 保留 U-23 与接线义务；台账 D-14、未决 U-05 | 已有单卡审核，但没有本清单及 M6 整体证据的 WorkBuddy 结论、用户取舍确认；本回执不能自审 |
| 20.1.9 | 例子输入非空且到目标分支；无非法事件须有正常 hit/清理；标签比较预计主键集合；失败证明拒绝原因 | 20.1，4331 | ⚠️ | `tests/test_ed17_repro.gd::test_ed17_08_purge_cancels_real_termination_derivation`（真实活根清场与不清场对照）；`test_ed17_05_blocked_instant_carrier_adapter` 经 `_blocked/_rejection` 核对拒绝路径/原因 | 运行时有非空及拒绝原因对照；缺标签检索预计/实际主键集合用例，不能泛化到全部验收 |
| 20.1.10 | 证据绑定版本和内容指纹；旧证据不贴新版本；无变化不假修订，内容变化同版本阻止；绿色可展开用例 | 20.1，4333 | ⚠️ | `tests/test_preview_fingerprint.gd::test_save_and_certify_verdicts_are_separate_and_certification_is_fingerprint_bound`；`tests/test_validate_identity.gd::test_v007_version_format_and_same_version_content_conflict`；`tests/test_ui_save_flow.gd::test_same_fingerprint_does_not_write_or_advance_revision`；台账 D-30 | 缺完整凭据版本绑定与历史证据 UI；缺绿色状态展开具体用例；三模块未在真实保存/认证链统一接线 |

## 20.2 组织与检索验收例子

| # | 验收条目（规格书原文摘要） | 规格书位置 | 判定 | 证据 | 缺口 |
|---|---|---|---|---|---|
| ED-13-01 | 十二角色各至少两技能，逐角色返回完整集合且不串入；覆盖分页全集 | 20.2，4339 | ⬜ | `addons/skill_editor/ui/skill_list_panel.gd:13–22` 明示索引未提供；台账 D-00-2 | 缺十二角色非空集合夹具、角色检索、分页全集及精确集合断言 |
| ED-13-02 | 共享水晶池与角色限制池组合检索，去重且适配原因清楚 | 20.2，4340 | ⬜ | `skill_list_panel.gd:22` 仅列本次成功打开项 | 缺多角色/多技能/多池交叉索引、去重和限制原因测试 |
| ED-13-03 | 新增角色、第三技能、新池，不改界面分支即可查询 | 20.2，4341 | ⬜ | `skill_list_panel.gd:69–71` 新建接口未提供；台账 D-04 | 没有新增登记后动态索引与查询用例；积木载体筛选不是技能组织检索 |
| ED-13-04 | 两技能同名不同 ID 都可找，精确 ID 只命中一个 | 20.2，4342 | ⚠️ | `tests/test_editor_ui.gd::test_open_displays_ids_and_names_without_merging_same_names`（两条同名、两份不同 metadata） | 仅假 API 打开并展示，缺精确 ID 查询与搜索；编辑器真实加载 API 仍桩 |
| ED-13-05 | 复制保留旧 ID，阻止保存并定位 skill_id（V-003/E-0003） | 20.2，4343 | ⚠️ | `tests/test_validate_identity.gd::test_v003_duplicate_id_excludes_current_source_only`（异源重复拒绝、定位 skill_id）；台账 D-06、D-07 | 校验模块有反例；缺真实复制→保存拒绝与 UI 字段定位整链，不能判编辑器通过 |
| ED-13-06 | 仅改显示名，旧 ID 仍定位同一技能，新名可搜索 | 20.2，4344 | ⬜ | `skill_list_panel.gd:20,69–71` Rename 降级为不可用 | 缺重命名与按旧 ID/新名称检索行为测试 |
| ED-13-07 | 标签修改改变 tagged 匹配，显示受影响修饰器并重新验收 | 20.2，4345 | ⚠️ | `tests/test_modifier_engine.gd::test_tagged_requires_legal_matching_tags_and_real_tag_slot`（合法 fire 通过、错标签/未知标签拒绝）；台账 D-00-3 | 缺编辑器改标签后的受影响清单与自动重新验收；静态 scope 授权不等于变更流程 |
| ED-13-08 | 删除强引用定义阻止；取消池成员不删除定义 | 20.2，4346 | ⬜ | `skill_list_panel.gd:19,69–71` 删除不可用 | 缺删除引用保护、取消池成员操作及两者分离的断言 |

## 20.3 保存、迁移与诊断验收例子

| # | 验收条目（规格书原文摘要） | 规格书位置 | 判定 | 证据 | 缺口 |
|---|---|---|---|---|---|
| ED-16-01 | 完整定义保存关闭重开；七键、十二字段、七表现段与数组顺序保留 | 20.3，4352 | ⚠️ | `tests/test_schema_codec.gd::test_cfg_round_trip_is_deep_equal`（完整树内存往返相等）；台账 D-02 | 没有真实关闭重开；与 SaveFlow 组合后的引用、单位及缺省语义未整链验证 |
| ED-16-02 | 未知顶层键、重复键、结果载荷字段各拒收，定位原始实际路径 | 20.3，4353 | ⚠️ | `tests/test_schema_codec.gd::test_structure_rejects_extra_top_level_key_with_path`；`test_yaml_rejects_duplicate_keys_with_location`（line 3/name）；台账 D-02 | 缺三类非法文件经统一编辑器导入入口拒收且不丢字段的整链；重复键现为行号/键，未证明统一叶路径映射 |
| ED-16-03 | 完整旧版本迁移链，先预览差异、确认后提交、保留身份 | 20.3，4354 | ⬜ | `save_flow.gd:45–76` 仅解析与校验；台账 D-02 | 没有可执行迁移链、差异预览及确认事务测试；migration_state 是消费事实而非迁移器 |
| ED-16-04 | 未来版本或缺迁移链只读，禁降级覆盖，原文件不变（V-083/E-0041） | 20.3，4355 | ⚠️ | `tests/test_ui_save_flow.gd::test_unknown_higher_version_loads_read_only_and_save_is_rejected`（9.0 只读且草稿未改）；`tests/test_validate_present.gd::test_v083_incomplete_migration_blocks_current_version_passes` | 未来版本测试用 FakeValidator/FakeCodec；缺真实 YAML + V-001/V-083 联调和原文件字节不变证据，缺迁移链只读 UI |
| ED-16-05 | 缺 schema_version 不自动补当前版本，等明确适配 | 20.3，4356 | ⚠️ | `tests/test_validate_identity.gd::test_v001_schema_version_missing_type_and_supported_boundary`（缺省 actual 为未填写、拒绝）；`save_flow.gd:59–61` 显式失败 | 缺实际导入后原档保留与不自动补写的整链断言 |
| ED-16-06 | 保存时基线更新不覆盖，显示打开时与当前版本（V-081/E-0039） | 20.3，4357 | ⚠️ | `tests/test_ui_save_flow.gd::test_advanced_baseline_rejects_without_overwriting_and_exposes_actions`（writer 不增、原文本不变、save_as/reload）；台账 D-30 | 缺编辑器显示“打开时与当前版本”以及真实文件并发更新用例 |
| ED-16-07 | 第四积木覆盖数组错误，导航实际叶路径，不停在总面板 | 20.3，4358 | ⚠️ | `tests/test_ui_diagnostic_panel.gd::test_override_source_is_not_misidentified_as_default`（params.brick_overrides[2].values.ratio）；`test_click_expands_and_locates_once_even_after_switching_views`（字段信号）；台账 D-10 | 当前用例非第四卡覆盖数组；只有面板信号，缺连接到实际控件/折叠区的导航 |
| ED-16-08 | 过期预览不能认证新定义；合法 CFG 仍可普通保存 | 20.3，4359 | ⚠️ | `tests/test_validate_present.gd::test_v084_certify_blocks_save_notices_invalid_operation_fails`（certify 阻止、save 成功并 notice）；`tests/test_preview_fingerprint.gd::test_save_and_certify_verdicts_are_separate_and_certification_is_fingerprint_bound`；台账 D-30 | 缺真实保存/认证按钮与指纹状态接线，不能把规则级通过替代编辑器验收 |
| ED-16-09 | 重复迁移、未改内容重复保存，规范化一致且无重复转换 | 20.3，4360 | ⚠️ | `tests/test_ui_save_flow.gd::test_same_fingerprint_does_not_write_or_advance_revision`（第二次 changed=false、revision 不变、writer 仍一次） | 缺重复迁移幂等与转换次数证据；保存测试只验证假 codec 流程 |
| ED-16-10 | 默认卡更新影响锁定字段/引用，先差异再整体校验，不自动改旧档 | 20.3，4361 | ⬜ | `tests/test_ui_diagnostic_panel.gd::test_default_card_path_and_injected_source_warn_without_writing_overrides` 仅证明诊断不回写 | 缺目录更新快照、差异确认、版本递增与整体重校验流程；诊断只读不等于默认更新稳定性 |
| 20.3.1 | 每条 V 有反例及相邻边界；通用类型覆盖零/边界/缺省/null/字符串数字/非有限/超范围；关联规则引用存在仍非法 | 20.3，4363 | ⚠️ | `tests/test_validate_rules.gd::test_every_rule_fixture_triggers_and_adjacent_boundary_is_clean`（遍历 CSV、非空匹配、合法边界无 BLOCK）；`tests/test_modifier_engine.gd::test_each_protected_category_rejects_every_permission_even_when_exposed`（81 组合已暴露仍拒绝） | 总账未逐条断言路径；未形成“每条通用类型 × 七类输入”及全部关联语义的完整覆盖矩阵，不能仅按84条总数勾全 |

## 20.4 运行时复现验收例子

本节 ✅ 只对应独立 runner 的具体 ED 行，不提升为编辑器端到端通过。17 条 blocked 分别保留；“测试断言能力不存在”为反证，不是需求通过。

| # | 验收条目（规格书原文摘要） | 规格书位置 | 判定 | 证据 | 缺口 |
|---|---|---|---|---|---|
| ED-17-01 | 一接触三份仅一闪避：一 hit、三份记录、派生仅一次 | 20.4，4369 | ✅ | `tests/test_ed17_repro.gd::test_ed17_01_three_parts_one_hit_one_derivation`（hit=1、summary=1、parts=3、evaded=[false,true,false]、children=1、HP=80；全闪避对照无派生）；台账 D-28 | — |
| ED-17-02 | 三份全闪避持续重叠：无 hit、有 evaded_all、占候选额度、不耗 max_hits | 20.4，4370 | ✅ | `tests/test_ed17_repro.gd::test_ed17_02_all_evade_overlap_and_max_hits`（重叠 evaded_all=1，后方另一目标仍 hit=1/HP=70；不闪避对照使后方 HP=100） | — |
| ED-17-03 | 无敌目标伤害闪避、治疗正常、控制按对应免疫 | 20.4，4371 | ✅ | `tests/test_ed17_repro.gd::test_ed17_03_invulnerable_damage_heal_control`（伤害 evaded、治疗10/HP60、控制不闪避且 immune；取消免疫应用数1→2）；台账 D-28 | — |
| ED-17-04 | 免疫份减到零仍 hit，零值标记正确 | 20.4，4372 | ✅ | `tests/test_ed17_repro.gd::test_ed17_04_immunity_zero_is_still_hit`（hit=1、evaded_all=0、value=0、immune/zero=true、evaded=false；去免疫 HP90 对照） | — |
| ED-17-05 | 出手瞬时当 tick、hit 派生瞬时下一可判 tick，各先命中后结束 | 20.4，4373 | ❌ | `tests/test_ed17_repro.gd::test_ed17_05_blocked_instant_carrier_adapter` 经 `_blocked(5)` 证明 none 入口拒绝；`preview_runner.gd:151–156` | **runner 缺适配器**：非 independent 载体显式拒绝，无法创建出手/派生瞬时实例 |
| ED-17-06 | 同 tick 两实例，首条杀死目标后第二条无 hit/evaded_all，仅一次击杀 | 20.4，4374 | ✅ | `tests/test_ed17_repro.gd::test_ed17_06_death_rechecked_between_instances`（两根、hit=1、records=1、evaded_all=0、killed=1、HP0；存活对照 hit=2） | — |
| ED-17-07 | 火区脉冲与到期同 tick：仅 expired、不额外跳伤 | 20.4，4375 | ❌ | `tests/test_ed17_repro.gd::test_ed17_07_blocked_area_pulse_expiry_scheduler` 经 `_blocked(7)` 验证 timing 拒绝 | **runner 缺适配器**：持续火区脉冲/自然到期同 tick 调度未实现 |
| ED-17-08 | 带结束派生实例清场，无 vanish/补 hit/派生 | 20.4，4376 | ✅ | `tests/test_ed17_repro.gd::test_ed17_08_purge_cancels_real_termination_derivation`（活根清场 active=0、events/records/children=0；不清场有 hit/vanish/child 各1）；台账 D-09 | — |
| ED-17-09 | 位移施放先拒绝，窗口内恢复执行、过期丢弃 | 20.4，4377 | ❌ | `tests/test_ed17_repro.gd::test_ed17_09_blocked_displacement_request_window` 经 `_blocked(9)` 验证 cast 拒绝 | **runner 缺适配器**：位移/施放请求窗口与过期调度 |
| ED-17-10 | 控制不打断则暂停前摇恢复；打断则取消未出手点 | 20.4，4378 | ❌ | `tests/test_ed17_repro.gd::test_ed17_10_blocked_cast_pause_or_interrupt` 经 `_blocked(10)` 验证 cast 拒绝 | **runner 缺适配器**：前摇控制暂停/恢复与取消出手点 |
| ED-17-11 | 阵亡与打断同 tick：位移体 purge，不派生结束冲击 | 20.4，4379 | ❌ | `tests/test_ed17_repro.gd::test_ed17_11_blocked_owner_death_interrupt_priority` 经 `_blocked(11)` 验证 self 拒绝；台账 D-09 | **runner 缺适配器**：self 位移体、主人死亡和打断优先级 |
| ED-17-12 | 三动作各两出手，X=6，与实例/hit/份数分开 | 20.4，4380 | ❌ | `tests/test_ed17_repro.gd::test_ed17_12_blocked_actual_shot_counter_x` 经 `_blocked(12)` 验证 cast 拒绝 | **runner 缺适配器**：动作、实际出手及 X 账本；不能用 root 数或 shot_id 去重冒充 |
| ED-17-13 | 同次出手多独立实例同 tick 接触，同批默认抑制，首全闪避也抑制后续 | 20.4，4381 | ❌ | `tests/test_ed17_repro.gd::test_ed17_13_blocked_all_evade_shotgun_contact_registration`（明确缺口断言 evaded_all=2；规格应为1；不闪避同 shot hit=1、不同 shot hit=2） | **已接入模块语义缺陷**，非素材缺字段：霰弹登记只记成功 hit，全闪避未登记同批抑制；不能笼统写成“等接线” |
| ED-17-14 | 建立合法分裂来源，家族成员全闪避后兄弟再次经过按候选登记跳过、不重掷 | 20.4，4382、4394 | ✅ | `tests/test_ed17_repro.gd::test_ed17_14_legal_split_then_evade_consumes_family_contact`（split_source tick1 hit→真实2子体、tick2 evaded_all=1、parent_ref 与出生 tick、evader HP100；去闪避对照 HP90） | — |
| ED-17-15 | 分裂/穿透/连锁固定碰撞优先级，母体 hit_end，子体不重置额度 | 20.4，4383 | ❌ | `tests/test_ed17_repro.gd::test_ed17_15_blocked_split_pierce_chain_collision_policy` 经完整公开 API `_api_probe` 核对无入口 | **runner 缺适配器/策略调度**：固定碰撞优先级和母体 hit_end 未接入；已有派生预算不补足碰撞策略 |
| ED-17-16 | 持续实例后提高施法者属性并改目标减免：旧快照不变、后续目标侧读当前 | 20.4，4384 | ❌ | `tests/test_ed17_repro.gd::test_ed17_16_blocked_current_target_state_update` 经 `_blocked(16)` 证明无宿主状态更新接口 | **runner 缺适配器**：运行中更新当前施法者与目标状态入口；输入深拷贝不能证明动态减免 |
| ED-17-17 | 超缺血治疗实际量截断，护盾按名义治疗量 | 20.4，4385 | ❌ | `tests/test_ed17_repro.gd::test_ed17_17_blocked_nominal_heal_shield_link`（amount_profile 明确 Unresolved settlement profile adapter） | **runner/结算宿主缺适配器**：名义治疗→护盾跨份量值链接，不能测试 handler 私补完整业务 |
| ED-17-18 | 护盾同 tick 按 seq 承两伤害，吸收/实伤正确，末尾唯一 hit_end | 20.4，4386 | ❌ | `tests/test_ed17_repro.gd::test_ed17_18_blocked_shield_seq_and_single_hit_end` 经 `_blocked(18)` 验证 attached 拒绝 | **runner 缺适配器**：attached 护盾额度、seq 承伤与结束生命周期 |
| ED-17-19 | 换装同 tick 出手读完整新装配、旧实例保留、公共冷却拒后续操作 | 20.4，4387 | ❌ | `tests/test_ed17_repro.gd::test_ed17_19_blocked_equipment_atomicity_and_global_cooldown` 经 `_blocked(19)` 验证 cast 拒绝 | **runner 缺适配器**：原子换装/公共冷却/出手时序；stop→start 不等于换装 |
| ED-17-20 | live 单向拒绝，双向只改允许数字、不改历史 | 20.4，4388 | ⚠️ | `tests/test_modifier_engine.gd::test_live_missing_item_application_and_target_exposure_have_distinct_slots`；`test_live_changes_current_value_but_preserves_every_snapshot_and_history_leaf`（damage 真改25、快照仍10/历史不变）；`tests/test_ed17_repro.gd::test_ed17_20_blocked_live_permission_runner_integration`；台账 D-26 | **模块未接入**：ModifierEngine 局部能力已有，但 runner 无 live 提交入口，不能对运行中的实际实例完成本例 |
| ED-17-21 | 被动回灌、超深度、冷却内重复分别被拦，保留来源链、不直接扣血 | 20.4，4389 | ❌ | `tests/test_ed17_repro.gd::test_ed17_21_blocked_passive_feedback_subscription`（真实 hit_settled=1、公开 API 无订阅调度）；台账 D-24 | **runner 缺适配器/调度**：被动记录订阅、反馈保护与冷却触发未实现；不是仅缺素材 |
| ED-17-22 | 召唤超限最旧 purge，主人死清绑定，独立实例继续 | 20.4，4390 | ⚠️ | `tests/test_ed17_repro.gd::test_ed17_22_blocked_summon_owner_lifecycle_adapter`；`skill_core/runtime/summon.gd` 已有独立模块；台账 D-09 | **模块未接入**：Summon 未接 runner，上限/死亡生命周期在该真实入口不能跑；独立模块存在不等于该 ED 通过 |
| ED-17-23 | 纯表现预算紧逻辑不变；判定体拒绝保留真实截断差异 | 20.4，4391 | ⚠️ | `tests/test_ed17_repro.gd::test_ed17_23_blocked_presentation_budget_with_real_body_drop`（紧预算 entities/drop/hit=1、无 vanish；正常预算 hit=2）；`tests/test_runtime_budget.gd::test_exhaustion_discards_presentation_layer_before_logic_and_records_each_drop`；台账 D-13 | **模块未接入**：runner 只有 runtime_body 准入，纯表现预算半例未接入；已覆盖真实判定拒绝，不能伪称全轨迹一致 |
| ED-17-24 | 暂停/慢动作/不同渲染频率/关闭表现，tick 可复现且表现 RNG 不污染逻辑 | 20.4，4392 | ⚠️ | `tests/test_ed17_repro.gd::test_ed17_24_blocked_pause_scale_but_replay_and_visual_rng_probed`（6快照、表现多抽17次/步、逻辑一致、两 RNG 确有变化、批推进终态相等） | **模块未接入**：Clock 的暂停/缩放未由 runner 暴露；批推进不是实际不同渲染频率与关闭表现完整试验 |
| 20.4.1 | ED-17-14 必须有真实合法分裂来源，不能假定全闪避会 hit 派生；记录具体入口 | 20.4，4394 | ✅ | `tests/test_ed17_repro.gd::test_ed17_14_legal_split_then_evade_consumes_family_contact`（legal_split_entry 非空、真实源命中与父子身份/出生tick、非闪避到达性对照）；`data/fixtures/ed17.json` 由该函数读取核对 | — |

## 20.5 可勾选验收清单（按原文逐框排列）

### 组织与格式

| # | 验收条目（规格书原文摘要） | 规格书位置 | 判定 | 证据 | 缺口 |
|---|---|---|---|---|---|
| 20.5.1 | 十二登记角色多技能检索，预计/实际集合逐一相等 | 20.5，4400 | ⬜ | 同 ED-13-01；技能索引 API 未提供 | 缺十二角色全集夹具、检索与精确集合断言 |
| 20.5.2 | 共享/限制池、多标签交集、精确 ID 全覆盖，不重复不漏页 | 20.5，4401 | ⬜ | 同 ED-13-02/04；`skill_list_panel.gd:22` | 缺交叉索引、交集、分页、精确 ID 的一整套查询验收 |
| 20.5.3 | 增角色/技能/池只改登记数据，无新增数量分支 | 20.5，4402 | ⬜ | 同 ED-13-03；台账 D-04 | 缺动态技能组织检索；不能以积木枚举动态化替代 |
| 20.5.4 | 完整 ID 格式，显示名不改身份，变体不作版本 | 20.5，4403 | ⚠️ | `tests/test_validate_identity.gd::test_v002_identity_format`；`test_v006_short_name_and_variant_reconstruct_without_guessing`；`test_v007_version_format_and_same_version_content_conflict` | 缺显示名修改前后身份/搜索不变与“变体不当版本”的显式验收；Rename 仍未接线 |
| 20.5.5 | schema_version、meta.version、文档版本分别展示、不混写 | 20.5，4404 | ⬜ | 两种数据版本字段已有校验；没有三种版本展示测试 | 缺三版本 UI、文档版本来源和分别显示断言 |
| 20.5.6 | 保存文件七顶层键、十二字段卡、表现七段符合冻结约定 | 20.5，4405 | ⚠️ | `tests/test_schema_structure.gd::test_baseline_and_frozen_top_level_keys`；`test_twelve_card_fields_are_reported_at_third_slot`；`test_seven_presentation_segments_missing_extra_and_nested_extra`；台账 D-02、D-11 | 结构层覆盖，但尚无真实保存文件经编辑器重载的整链证据；子字段合并问题见下一行 |
| 20.5.7 | 第5/9章登记与推荐子字段经评审合并同一 CFG Schema，未合并不得勾 | 20.5，4406 | ⬜ | `reports/T-061.md:113–119` 明确 U-23 未收口；台账 D-31 | 缺逐字段合并/评审确认；anim 数组对齐与素材标量别名仍冲突，不能用已有 Schema 文件替代评审 |
| 20.5.8 | 控件、校验、保存、加载用同一登记源，无各自默认值 | 20.5，4407 | ⚠️ | `tests/test_ui_param_form.gd::test_enum_options_follow_the_injected_enumeration`；`tests/test_schema_structure.gd::test_enum_values_follow_injected_metadata_not_code_literals`；台账 D-21、D-22、D-31 | 各模块可注入不等于共享同一来源的集成；U-23 存在真实落点冲突，四路径未统一接线 |

### 校验与诊断

| # | 验收条目（规格书原文摘要） | 规格书位置 | 判定 | 证据 | 缺口 |
|---|---|---|---|---|---|
| 20.5.9 | V-001…084 各有反例、边界、准确定位，按启用能力执行 | 20.5，4411 | ⚠️ | `tests/test_validate_rules.gd::test_every_rule_fixture_triggers_and_adjacent_boundary_is_clean`（规则全数与干净边界）；台账 D-25、D-27 | 总账未逐条核对 path；缺84条逐路径和条件能力矩阵的审计证据，不能把规则号命中等同准确定位 |
| 20.5.10 | E-0001…0042 占位全是真值，缺值不空白/undefined | 20.5，4412 | ⚠️ | `tests/test_validate_identity.gd::test_v001_schema_version_missing_type_and_supported_boundary`（未填写）；`test_unknown_message_code_has_fallback_and_notice_not_silent_drop`；台账 D-06 | 部分文案/缺值有断言，但未找到遍历42条所有占位逐一替换真实值、缺值均非空的测试 |
| 20.5.11 | 数组错误定位实际下标/叶，默认与覆盖来源可区分 | 20.5，4413 | ⚠️ | `tests/test_ui_diagnostic_panel.gd::test_default_card_path_and_injected_source_warn_without_writing_overrides`；`test_override_source_is_not_misidentified_as_default`；台账 D-06、D-10 | 面板级来源及路径已覆盖，缺真实解析来源→诊断→实际控件定位的编辑器接线 |
| 20.5.12 | 错误/警告/提示对保存/认证影响一致，无导出旁路 | 20.5，4414 | ⚠️ | `tests/test_validate_stages.gd::test_severity_is_aggregated_without_downgrade`；`tests/test_validate_present.gd::test_v084_certify_blocks_save_notices_invalid_operation_fails`；台账 D-07、D-27、D-30 | 缺所有真实保存/导出路径汇入 validator 的集成负例；不能以正常路径经过校验证明不存在旁路 |
| 20.5.13 | 固定运行策略不可写，未知策略键导入拒收 | 20.5，4415 | ⚠️ | `tests/test_validate_present.gd::test_v080_nested_illegal_leaf_and_registered_boundary`（unknown.nested[1].bad、deterministic=false 拒绝）；台账 D-04 | 缺未知策略键经真实 YAML 导入入口的联调，以及全部固定策略不可写的覆盖清单 |
| 20.5.14 | 所有启用积木有契约探针，未过/过期凭据不能认证 | 20.5，4416 | ⚠️ | `tests/test_validate_present.gd::test_v079_probe_requires_bound_coverage_and_pass`（注入 fail 阻止、pass 允许、缺指纹失败）；台账 D-25、D-31 | 缺全部启用积木的真实探针集合与逐项版本/有效期核验；context 中伪造的 pass 不是实跑凭据 |
| 20.5.15 | 合法预算截断与非法配置分报，不一律阻止保存 | 20.5，4417 | ⚠️ | `tests/test_ed17_repro.gd::test_ed17_23_blocked_presentation_budget_with_real_body_drop`（真实差异）；`tests/test_runtime_budget.gd::test_priority_table_missing_empty_duplicate_and_unknown_category_are_explicit_failures`；台账 D-13 | 运行账本和配置拒绝是分离的，但未有“合法截断 CFG 仍可保存”的真实保存链与 UI 分类报告 |
| 20.5.16 | 权限、tagged、继承、live 双向和保护字段均有负例 | 20.5，4418 | ✅ | `tests/test_modifier_engine.gd::test_three_permissions_are_independent_without_implicit_lower_tiers`（9组合）；`test_tagged_requires_legal_matching_tags_and_real_tag_slot`；`test_inheritable_requires_boolean_and_never_implicitly_copies_everything`；`test_live_missing_item_application_and_target_exposure_have_distinct_slots`；`test_each_protected_category_rejects_every_permission_even_when_exposed`（81组合）；台账 D-26 | — |

### 保存与迁移

| # | 验收条目（规格书原文摘要） | 规格书位置 | 判定 | 证据 | 缺口 |
|---|---|---|---|---|---|
| 20.5.17 | 正常保存重开规范值相同，顺序/引用/单位/缺省无损 | 20.5，4422 | ⚠️ | `tests/test_schema_codec.gd::test_cfg_round_trip_is_deep_equal`；`test_empty_array_is_valid_but_missing_field_is_not`；台账 D-02、D-05 | 缺真实保存重开、复杂数组/引用/默认值夹具贯穿四路径，不以纯编解码代替 |
| 20.5.18 | 未知字段/重复键/未来版本/缺迁移链/未识别版本保护原内容 | 20.5，4423 | ⚠️ | `tests/test_schema_codec.gd::test_yaml_rejects_duplicate_keys_with_location`；`tests/test_ui_save_flow.gd::test_unknown_higher_version_loads_read_only_and_save_is_rejected`；`tests/test_validate_present.gd::test_v083_incomplete_migration_blocks_current_version_passes` | 缺组合后的真实原文件不变、未识别版本保护以及缺链只读整链；不能凭假 codec 认证 |
| 20.5.19 | 迁移差异可查、重复迁移幂等，不只改版本字符串 | 20.5，4424 | ⬜ | `save_flow.gd` 消费 migration_state，没有迁移执行器 | 缺迁移链、转换前后差异、身份保留、重复执行断言 |
| 20.5.20 | 保存冲突不覆盖，保留草稿，旧有效定义仍可加载 | 20.5，4425 | ⚠️ | `tests/test_ui_save_flow.gd::test_advanced_baseline_rejects_without_overwriting_and_exposes_actions`；`test_save_does_not_mutate_input_cfg` | 缺同一失败事务下作者草稿保留、旧有效文件继续加载的整体验证和 UI |
| 20.5.21 | 过期预览不沿用旧标记，普通保存/认证分开 | 20.5，4426 | ⚠️ | `tests/test_preview_fingerprint.gd::test_save_and_certify_verdicts_are_separate_and_certification_is_fingerprint_bound`；台账 D-30 | 状态判定模块存在；缺编辑器实际保存/认证及 UI 标记接线 |
| 20.5.22 | 新默认卡不自动改旧定义，更新须比较并增技能版本 | 20.5，4427 | ⬜ | 同 ED-16-10；台账 D-25 的 default_applications 仅事实消费 | 缺目录更新版本快照、显式比较确认和更新后完整重校验 |

### 预览与复现

| # | 验收条目（规格书原文摘要） | 规格书位置 | 判定 | 证据 | 缺口 |
|---|---|---|---|---|---|
| 20.5.23 | 填卡/保存/重读/沙盒/正式复现/重跑完整走通 | 20.5，4431 | ⚠️ | `tests/test_preview_runner.gd::test_codec_yaml_roundtrip_and_arbitrary_ids_use_the_same_cfg_structure`；`tests/test_determinism.gd::test_real_diff_runs_same_seed_fresh_identity_and_cfg_not_written_back`；台账 D-00-1、D-00-2 | 仅编解码→沙盒与重跑局部；缺编辑器接线、真实落盘与正式入口，以及 T-064 证据包 |
| 20.5.24 | 凭据含定义/依赖/运行时/夹具/种子/输入，比较先核条件 | 20.5，4432 | ⚠️ | `tests/test_preview_fingerprint.gd::test_fingerprint_is_canonical_and_includes_cfg_seed_tick_rate_and_extra`（CFG/seed/tick_rate/extra 改动指纹变）；台账 D-30 | extra 可容纳不代表强制具备全部凭据字段；缺完整条件结构与比较前逐项拒绝不匹配 |
| 20.5.25 | snapshot/实例 params/当前施法者属性/目标当前状态分列，不都称实时 | 20.5，4433 | ⚠️ | `tests/test_modifier_engine.gd::test_live_changes_current_value_but_preserves_every_snapshot_and_history_leaf`（快照与当前值分离）；ED-17-16 的 API 缺口探针 | 缺四层分列 UI；runner 缺当前状态更新适配器，不能验证动态目标减免 |
| 20.5.26 | 出手/实例/候选接触/hit/份/派生分别计数，时间轴无新增技能事件 | 20.5，4434 | ⚠️ | `tests/test_ed17_repro.gd::test_ed17_01_three_parts_one_hit_one_derivation`；`test_ed17_12_blocked_actual_shot_counter_x`；`tests/test_ui_preview_panel.gd::test_mixed_records_populate_three_distinct_columns_without_cross_routing`；台账 D-08 | 缺实际出手 X 账本、六计数统一展示；现有 root 不等于出手 |
| 20.5.27 | 全闪避/免疫/无敌/治疗/护盾/控制/击退与主书稿一致 | 20.5，4435 | ⚠️ | `tests/test_ed17_repro.gd::test_ed17_03_invulnerable_damage_heal_control`；`test_ed17_04_immunity_zero_is_still_hit`；`test_ed17_17_blocked_nominal_heal_shield_link`；`test_ed17_18_blocked_shield_seq_and_single_hit_end`；台账 D-28 | 缺治疗名义量→护盾、seq盾生命周期与运行态击退整例；不能因基础份结算通过勾全分支 |
| 20.5.28 | 同 tick 排序/派生下 tick/死亡跳过/到期不补跳/purge 静默有证据 | 20.5，4436 | ⚠️ | `tests/test_ed17_repro.gd::test_ed17_06_death_rechecked_between_instances`；`test_ed17_08_purge_cancels_real_termination_derivation`；`test_ed17_14_legal_split_then_evade_consumes_family_contact`；台账 D-09 | ED-17-05 瞬时与07脉冲到期、11死亡优先级仍 blocked；已有局部排序不能覆盖所有同 tick 契约 |
| 20.5.29 | 换装原子/公共冷却/旧实例不变/live 受限修改全通过 | 20.5，4437 | ⚠️ | `tests/test_modifier_engine.gd::test_live_changes_current_value_but_preserves_every_snapshot_and_history_leaf`；`tests/test_ed17_repro.gd::test_ed17_19_blocked_equipment_atomicity_and_global_cooldown`；`test_ed17_20_blocked_live_permission_runner_integration`；台账 D-26 | 缺换装与冷却宿主适配器；ModifierEngine 未接 runner；只有 live 模块局部证据 |
| 20.5.30 | 关表现/换动画/隐藏调试逻辑一致，判定截断差异如实保留 | 20.5，4438 | ⚠️ | `tests/test_determinism.gd::test_real_runner_presentation_rng_does_not_pollute_logic_trace`（真实110次表现抽样）；`tests/test_runtime_budget.gd::test_turning_off_debug_leaves_each_battle_outcome_and_formal_record_unchanged`；`tests/test_ed17_repro.gd::test_ed17_23_blocked_presentation_budget_with_real_body_drop`；台账 D-12、D-13 | 缺真实关表现/换动画/隐藏面板的集成对照；**素材缺字段**：presentation_meta 缺 event_bindings/forbidden_logic_keys，另有U-23；binder/renderer 未接线 |
| 20.5.31 | 种子回放逐次一致，差分保留原顺序，不忽略关键字段伪造成功 | 20.5，4439 | ⚠️ | `tests/test_determinism.gd::test_real_diff_runs_same_seed_fresh_identity_and_cfg_not_written_back`；`test_changed_logic_seed_is_not_filtered_out`（定位logic_rng.seed差异）；`test_first_difference_tick_seven_names_leaf_without_mutating_runner`（精确下标7） | 真实非空短回放覆盖，但未有事件/记录数组重排的负例及“关键字段白名单不可裁去”的认证保护；run_diff允许调用方选择trace_fields，不能把局部差分等同不可伪造认证 |

### 后续能力与人工审核

| # | 验收条目（规格书原文摘要） | 规格书位置 | 判定 | 证据 | 缺口 |
|---|---|---|---|---|---|
| 20.5.32 | 模板实例化不携运行态，锁定/占位符合18章；未实现标未验收 | 20.5，4443 | ⬜ | 未找到编辑模板实例化/占位验收测试；运行时 templates 不是编辑器模板复用流程 | 缺模板编辑/实例化/占位协议与测试；明确**未验收**，不把 EffectBody 创建当模板系统 |
| 20.5.33 | 批量目标冻结、失败不半提交、外部冲突可停止；未实现不宣称支持 | 20.5，4444 | ⬜ | 未找到技能批量编辑事务实现与对应测试 | 缺目标集冻结、原子提交/回滚和外部版本冲突停止；明确不宣称支持 |
| 20.5.34 | debug_record 三种 kind 独立展示，不进正式 UI/逻辑触发 | 20.5，4445 | ⚠️ | `tests/test_ui_preview_panel.gd::test_mixed_records_populate_three_distinct_columns_without_cross_routing`（仅预算kind的2条debug）；`tests/test_runtime_budget.gd::test_debug_record_is_only_in_debug_ledger_and_formal_types_are_checked_from_params`；台账 D-24 | 缺三种kind逐种独立展示与真实面板接线；被动调度未实现，不能以无订阅表证明不触发 |
| 20.5.35 | 日志缺失/截断/条件不全不能认证通过 | 20.5，4446 | ⚠️ | `tests/test_determinism.gd::test_unequal_trace_lengths_report_both_not_shorter_prefix`；`test_leaf_structure_and_dictionary_order_are_deterministic`（空trace拒绝）；`test_ticks_positive_limits_required_and_huge_request_truncated`（截断仍equal=true但显式truncated=true） | 缺认证层强制阻止truncated/条件不全凭据；T-053审核仅限定equal为前缀一致，没有完成认证闸门 |
| 20.5.36 | WorkBuddy 审规格/证据，争议入未决、不擅改确认决策 | 20.5，4447 | ⬜ | `reports/T-061.md:113–125` 保留U-23、T-053审核有采纳口径；台账 D-14 | 仅有单卡结论；M6整体验收尚无人审核，本审计不能自勾 |
| 20.5.37 | 性能/联网同步/代码映射/最终数值不混入完成判定 | 20.5，4448 | ⬜ | 台账 D-00-1、D-13 明确排除性能；本报告未用这些作门槛 | 属范围/人工验收，无对应测试函数，按派单不得判✅；待审核方确认范围，不以统计测试数代替 |

## 20.6 交付与实现验收分界

| # | 验收条目（规格书原文摘要） | 规格书位置 | 判定 | 证据 | 缺口 |
|---|---|---|---|---|---|
| 20.6.1 | 章节草案/静态检查不能证明编辑器已运行或推荐子字段已纳入全书 Schema | 20.6，4452 | ⬜ | 本文仅审计；`plugin.gd`、`skill_api.gd` 桩及U-23保留；台账 D-01、D-17 | 没有新的编辑器实现运行/全书Schema评审证据；遵守分界不等于该能力已验证 |
| 20.6.2 | 规格先行逐例TDD，先确认失败再最小实现回归；人工审期望/真触发/范围，不只看数量 | 20.6，4454 | ⬜ | 单卡回执有静态复核及审核方门禁记录；本卡无代码实现 | 无全项目逐例红→绿履历可核验；人工审核职责不能由本审计或测试总量代签 |

## 汇总统计与 M6 收口依赖

| 范围 | 条数 | ✅ | ⚠️ | ❌ | ⬜ |
|---|---|---|---|---|---|
| 20.1 八步骤及两段约束 | 10 | 0 | 8 | 0 | 2 |
| 20.2 组织检索八例 | 8 | 0 | 3 | 0 | 5 |
| 20.3 保存迁移十例及约束 | 11 | 0 | 9 | 0 | 2 |
| 20.4 运行时二十四例及约束 | 25 | 8 | 4 | 13 | 0 |
| 20.5 原始37项复选框 | 37 | 1 | 25 | 0 | 11 |
| 20.6 两段分界 | 2 | 0 | 0 | 0 | 2 |
| **合计** | **93** | **9** | **49** | **13** | **22** |

- **20.5 本体仅1/37满足本次✅口径**，尚余36项（25部分、11未验证）；全审计剩84行不是✅。原书复选框未改写，本文判定是独立证据表，不是替真源打勾。
- ED-17总账：7条✅、4条⚠️、13条❌，恰好17条不是通过；加上20.4.1的同一合法分裂约束才是本节8个✅。这是覆盖关系计数，不是重复多跑出一个验收例子。
- 17个blocked**不是同一根因**：05/07/09/10/11/12/15/16/17/18/19/21主要是runner或结算宿主缺适配器/调度；20/22/23/24主要是已有模块未接入；13是已接入霰弹登记语义缺陷。表现接线另有素材缺字段/U-23，不能把这些统统称为“等素材”。

### 按依赖排序的剩余工作（不是擅自扩任务/改规格）

1. **审核冻结素材与接线契约**：处理U-23数组对齐与标量别名冲突，补正式event_bindings/forbidden_logic_keys，确认凭据完整字段与认证拒绝规则，补20.5.7/8/14/24/35的依据；依据台账D-21/22/25/31，不能让UI自行猜。模板/批量未实现的交付边界也需审核确认，不能因列为“后续能力”直接勾过。
2. **可用入口与编辑器接线**：T-070职责所指的API桥接和模块挂载先真正落地，补技能创建/检索/标签/池/导航、保存/加载、认证/预览链；然后才能复验ED-13、ED-16、20.1.1–5与20.5组织/保存项。接线不是把桩ok改true，所有写入仍须校验。
3. **修ED-17-13并补运行时宿主能力**：先修可独立定位的全闪避同批登记反证；按基础载体/时钟→cast/timing与死亡控制→护盾/profile/换装/被动→live、summon、纯表现预算、暂停缩放的依赖顺序接入；逐条将缺口探针转为真源正向验收，不能维持evaded_all=2作为通过依据。
4. **保存保护和版本迁移实链**：真实YAML磁盘往返、未来/缺失版本、缺链只读、冲突后草稿与旧档保留；再加迁移差异/确认/重复幂等、默认卡更新快照与版本递增，补ED-16-01…10及20.5.17–22。
5. **补齐覆盖矩阵与负例**：84条路径/启用条件、通用类型七类输入、42文案所有占位，所有启用积木的真实契约探针；差分数组顺序/关键字段保护、缺日志/截断/条件不全拒认证；补20.3.1及20.5.9–15/31/34/35。
6. **正式入口与端到端证据包**：从真实保存CFG到正式/沙盒双入口及同条件重跑，把全部输入、版本和指纹绑定；绿色状态可展开具体用例，提交20.1八步骤证据（T-064），不以两次PreviewRunner替代正式入口。
7. **人工收口**：由WorkBuddy复核本表与新证据，用户确认主观取舍及范围；最终更新判定。未实现模板/批量仍应未验收，除非人明确变更交付范围并留决策，不自行豁免。性能/联网等继续排除，不为凑“全勾”扩范围。

### 当前无法判定的条目

22条⬜：20.1.6、20.1.8；ED-13-01/02/03/06/08；ED-16-03/10；20.5.1/2/3/5/7/19/22/32/33/36/37；20.6.1/2。各行已写缺少入口、可执行迁移/模板/批量、全书评审或人工确认的具体原因。⬜不等于反证为真；13条❌才是明确拒绝或错误结果的反证。

### 最应先补的三条缺口

1. **20.5.7/8：Schema与正式素材收口**。U-23和缺正式表现路由会让合法非空动画直接失败；先统一权威来源，才能避免接线层制造第二套默认值与规则。
2. **20.5.23：真实可用入口与端到端接线**。当前UI与core仍隔着失败桩；即使模块测试继续增加，用户仍无法完成填卡→保存→预览，这是最多验收条目的共同前置。
3. **ED-17-13：全闪避霰弹登记反证**。这是已触发分支的确定语义错误而不是测试适配不足；先修首候选接触登记，避免后续运行时集成沿错误结果建立基线。

以上优先级不代表审批实现方案；本卡没有修改上述任何代码或素材。待WorkBuddy审核。
