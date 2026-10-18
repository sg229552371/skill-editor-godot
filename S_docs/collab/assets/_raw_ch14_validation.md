# 第 14 章　校验规则表

〔2026-10-18 第1轮〕校验不是给表单涂红，而是阻止作者把运行时不能解释或违反契约的定义保存成可执行 CFG。运行时仍保留防御性检查，编辑器通过不等于运行时可以删除保护。

## 14.1 校验入口、定位与严重度

校验分为填写中、整卡、装配组合、保存前、加载前和预览契约探针六个入口。填写中只检查已提交控件值，避免输入负号的中间态刷屏；保存前必须对规范化后的完整定义和全部依赖再校验一次。装配组合检查不能只看单个修饰器，因为多个合法覆盖合并后仍可能越界或互相冲突。

| 严重度 | 对保存的影响 | 对预览的影响 | 作者可做什么 |
|---|---|---|---|
| 阻止保存 | 不生成可执行 CFG，不覆盖上一份有效定义 | 仅允许浏览字段和旧版预览，不能运行坏草稿 | 修改字段、取消本次提交、保留内存草稿 |
| 警告 | 可保存，必须在提交摘要可见 | 可以运行，但提示相关风险 | 修正或留下设计说明，不隐藏规则 |
| 提示 | 不阻止 | 不阻止 | 了解默认值和实际生效口径 |

每条诊断携带规则 ID、文案 ID、实际字段路径、当前值、预期约束和相关字段。路径缺失时定位到应存在的槽位；数组项错误定位到具体项。并发重新校验时诊断绑定草稿修订号，旧结果不得覆盖新结果。相同字段有类型错误时先报告类型错误，依赖该值的范围检查暂缓，避免一个字符串造成几十条伪错误。

本表路径均以第 16 章字段落点为准。`bricks[i].default_cfg` 中出现相同逻辑字段时，应用同一规则并报告该处的真实路径；若错误由 `params` 覆盖引起则定位覆盖值，同时关联默认值。禁止只报规范化内存里的地址，作者必须能回到保存文件中的原因位置。

## 14.2 身份、结构和引用规则

| 规则 ID | 触发条件 | 严重度 | 定位字段 | 报错文案 |
|---|---|---|---|---|
| V-001 | 版本缺失、非字符串或不是受支持版本 | 阻止保存 | `schema_version` | E-0001 |
| V-002 | ID 不符合角色、类别、短名、可选变体格式 | 阻止保存 | `skill_id` | E-0002 |
| V-003 | ID 与其他定义冲突 | 阻止保存 | `skill_id` | E-0003 |
| V-004 | 角色未登记，或与 ID 组成不符 | 阻止保存 | `meta.role` | E-0004 |
| V-005 | 类别不在四种枚举内，或与 ID 不符 | 阻止保存 | `meta.category` | E-0004 |
| V-006 | 短名或变体组成不能还原完整 ID | 阻止保存 | `meta.short_name`、`meta.variant` | E-0004 |
| V-007 | 技能版本不符合约定格式或覆盖同版不同内容 | 阻止保存 | `meta.version` | E-0005 |
| V-008 | 显示名为空 | 阻止保存 | `meta.name` | E-0006 |
| V-009 | 池引用不存在或同一成员重复 | 阻止保存 | `meta.pools[i]` | E-0007 |
| V-010 | 标签不存在或重复 | 阻止保存 | `meta.tags[i]` | E-0007 |
| V-011 | 积木目录不存在对应定义或版本不可解析 | 阻止保存 | `bricks[i].brick_id` | E-0007 |
| V-012 | 保存了未登记或预留积木并要求参与运行 | 阻止保存 | `bricks[i].status` | E-0008 |
| V-013 | 登记卡缺少任一冻结字段 | 阻止保存 | `bricks[i].author_params` 等实际缺失槽位 | E-0006 |
| V-014 | 作者覆盖了积木锁定字段 | 阻止保存 | `params.brick_overrides[i].values` 中实际叶路径 | E-0009 |
| V-015 | 同一积木覆盖索引不存在或重复赋值不明确 | 阻止保存 | `params.brick_overrides[i].brick_index` | E-0007 |
| V-016 | 派生或触发产出引用未解析到有效定义 | 阻止保存 | `params.derivations[i].produces`、`params.triggers[i].produces` | E-0007 |
| V-017 | 玩家文字含内部事件、原因码或权限术语 | 警告 | `bricks[i].player_text` | E-0010 |
| V-018 | 玩家文字超过三句或动词无对应行为 | 警告 | `bricks[i].player_text` | E-0010 |

V-013 的“等”不是最终诊断路径：规则展开为十二个必填槽位分别检查，缺 `summary` 就定位 `bricks[2].summary`。V-014 同理必须解析到实际叶字段，例如 `params.brick_overrides[0].values.lifetime_ticks`，不能停在整个参数对象。顶层额外键或未知子字段属于 V-019，定位到原始文件实际键，如 `params.tick_order`；该路径用于拒收非法输入，并不代表 Schema 允许这个字段。

## 14.3 类型、时间、命中和事件规则

| 规则 ID | 触发条件 | 严重度 | 定位字段 | 报错文案 |
|---|---|---|---|---|
| V-019 | 出现未登记字段、非法顶层键或重复映射键 | 阻止保存 | 原始键的完整路径，如 `params.tick_order` | E-0011 |
| V-020 | 登记字段类型不符、数值非有限或不在声明范围 | 阻止保存 | 实际叶路径，如 `params.projectile_speed` | E-0012 |
| V-021 | tick 字段为负数、分数或附带秒字符串 | 阻止保存 | `params.windup_ticks`、`params.cooldown_ticks`、`params.lifetime_ticks` | E-0013 |
| V-022 | 开始延迟或出手时间点不是非负整数 tick | 阻止保存 | `params.start_delay_ticks`、`params.shot_ticks[i]` | E-0013 |
| V-023 | 出手时间表不是非递减序列或为空却声明主动出手 | 阻止保存 | `params.shot_ticks[i]` | E-0014 |
| V-024 | 载体不是主书稿四类载体之一 | 阻止保存 | `params.carrier`、`bricks[i].carrier` | E-0015 |
| V-025 | 瞬时无载体实例声明非零寿命 | 阻止保存 | `params.lifetime_ticks` | E-0016 |
| V-026 | 持续效果体缺少合法寿命或契约允许的上限声明 | 阻止保存 | `params.lifetime_ticks` | E-0006 |
| V-027 | 命中限额不是正整数 | 阻止保存 | `params.hit_policy.per_target_limit`、`params.hit_policy.max_hits` | E-0012 |
| V-028 | 重复接触间隔存在但不是正整数 tick | 阻止保存 | `params.hit_policy.rehit_interval_ticks` | E-0013 |
| V-029 | 重复跳伤的区域或环绕积木缺重复间隔 | 阻止保存 | `params.hit_policy.rehit_interval_ticks` | E-0017 |
| V-030 | 同时配置限额与间隔，却把二者标成择一生效 | 阻止保存 | `params.hit_policy` 中非法策略叶路径 | E-0011 |
| V-031 | 目标丢失策略超出 continue、terminate | 阻止保存 | `params.on_target_lost` | E-0012 |
| V-032 | 事件派生订阅不是 hit 或 vanish | 阻止保存 | `params.derivations[i].on` | E-0018 |
| V-033 | vanish 原因包含 purge 或非冻结原因码 | 阻止保存 | `params.derivations[i].reasons[j]` | E-0019 |
| V-034 | range_end 或 interrupted 派生未显式授权 | 阻止保存 | `params.derivations[i].allow_restricted_reason` | E-0020 |
| V-035 | 非抛射积木要求 landed 原因派生 | 阻止保存 | `params.derivations[i].reasons[j]` | E-0021 |
| V-036 | 配置要求瞬时实例以其他自然结束原因终止 | 阻止保存 | `params.derivations[i].reasons[j]` | E-0021 |
| V-037 | 派生规则试图按每份重复派生或订阅状态到期 | 阻止保存 | `params.derivations[i].on` 及实际非法键 | E-0018 |
| V-038 | 份类型未登记或固定索引重复 | 阻止保存 | `params.parts[i].type`、`params.parts[i].part_index` | E-0012 |

对于表中未列完的 tick 字段，参数登记中单位为 tick 且类型为整数的每个实际字段都生成 V-021 的检查实例。不能把规则实现成只检查前摇、冷却、寿命三个名字。数值零是否允许由字段语义决定：前摇可以为零，瞬时寿命必须为零，重复间隔不能为零，内置冷却的零值另走显式例外检查。

没有可写参数的固定规则，不应为校验方便发明开关。例如不能给作者一个“全闪避是否发 hit”的布尔值，再要求它一直为 false。导入时发现这种字段按 V-019 拒绝；加载前则对对应积木的行为声明和契约探针作一致性校验，防止合法字段背后绑定了错误行为。参数合法与行为符合契约是两项独立结论。

## 14.4 修饰器、派生安全和被动触发规则

| 规则 ID | 触发条件 | 严重度 | 定位字段 | 报错文案 |
|---|---|---|---|---|
| V-039 | 修饰器标识缺失或重复 | 阻止保存 | `params.modifiers[i].modifier_id` | E-0003 |
| V-040 | 单个修饰器声明多个权限或未知权限 | 阻止保存 | `params.modifiers[i].permission` | E-0022 |
| V-041 | 水晶申请非 mutate_number 权限 | 阻止保存 | `params.modifiers[i].permission` | E-0022 |
| V-042 | scope 不合法或 tagged 缺少合法匹配标签 | 阻止保存 | `params.modifiers[i].scope`、`meta.tags[i]` | E-0023 |
| V-043 | 修改目标未暴露、名称不明确或不是字段引用 | 阻止保存 | `params.modifiers[i].targets[j]` | E-0024 |
| V-044 | mutate_number 目标不存在，试图凭空添加行为 | 阻止保存 | `params.modifiers[i].targets[j]` | E-0024 |
| V-045 | live 权限没有物品申请与目标 live 暴露双向许可 | 阻止保存 | `params.modifiers[i].permission`、`params.exposed_fields[j].live` | E-0025 |
| V-046 | 任一权限试图修改来源链、实例身份、快照或历史结果 | 阻止保存 | `params.modifiers[i].targets[j]` | E-0009 |
| V-047 | 修饰器试图修改 max_generation、max_chain_depth、allow_self_chain | 阻止保存 | `params.modifiers[i].targets[j]` | E-0009 |
| V-048 | 暴露字段未声明上下限或上下限倒置 | 阻止保存 | `params.exposed_fields[i].min`、`params.exposed_fields[i].max` | E-0026 |
| V-049 | 数值叠加类别不是 set、add、mul、clamp | 阻止保存 | `params.modifiers[i].stack_rule` | E-0012 |
| V-050 | 同字段多个 set 未说明最后挂载者覆盖 | 警告 | `params.exposed_fields[i].set_conflict_note` | E-0027 |
| V-051 | 合并后值违反类型或积木硬范围，不能合法夹取 | 阻止保存 | `params.modifiers[i].targets[j]` | E-0026 |
| V-052 | inheritable 非布尔或隐式要求全部修饰继承 | 阻止保存 | `params.modifiers[i].inheritable` | E-0012 |
| V-053 | 派生上限非非负整数或超过项目硬上限 | 阻止保存 | `params.max_generation` | E-0012 |
| V-054 | 已配置派生路径必然被代数上限截断 | 警告 | `params.derivations[i].produces` | E-0028 |
| V-055 | cast_budget 非正整数或缺少可解析项目默认 | 阻止保存 | `params.cast_budget` | E-0006 |
| V-056 | 预计路径可能超过合法施放预算 | 警告 | `params.cast_budget` | E-0028 |
| V-057 | 分裂配置允许分裂体重置 split_budget | 阻止保存 | `params.split_budget` | E-0029 |
| V-058 | 连锁配置要求每代重置 chain_remaining 或 visited | 阻止保存 | `params.chain_remaining` 及实际非法键 | E-0029 |
| V-059 | 触发点标识缺失、重复或不能稳定进入来源标记 | 阻止保存 | `params.triggers[i].trigger_id`、`params.derivations[i].trigger_id` | E-0003 |
| V-060 | 被动订阅非四种结算记录，含 hit、vanish、debug_record | 阻止保存 | `params.triggers[i].on` | E-0030 |
| V-061 | 触发产出不是效果体模板或修饰器引用 | 阻止保存 | `params.triggers[i].produces` | E-0031 |
| V-062 | 条件访问该记录没有的字段或未成立份 | 阻止保存 | `params.triggers[i].condition` | E-0032 |
| V-063 | 触发概率不是零到一的有限数 | 阻止保存 | `params.triggers[i].chance` | E-0012 |
| V-064 | 内置冷却缺失、负数或不是整数 tick | 阻止保存 | `params.triggers[i].internal_cooldown_ticks` | E-0013 |
| V-065 | 零内置冷却缺显式说明或有效预算保障 | 阻止保存 | `params.triggers[i].zero_cooldown_note` | E-0033 |
| V-066 | 因果深度上限缺失、非法或越过项目硬上限 | 阻止保存 | `params.triggers[i].max_chain_depth` | E-0012 |
| V-067 | 允许自链但最坏情况说明不完整 | 阻止保存 | `params.triggers[i].self_chain_note` | E-0033 |
| V-068 | 召唤积木缺正整数 summon_cap | 阻止保存 | `params.summon_cap` | E-0006 |
| V-069 | 依附、绑定、霰弹和自链布尔字段类型错误 | 阻止保存 | `params.attach_to_caster`、`params.bind_owner`、`params.shotgun_allowed`、`params.triggers[i].allow_self_chain` | E-0012 |

V-056 是警告而非阻止保存：契约允许合法预算在运行中截断，编辑器不能把所有截断都改称非法配置。相反，缺预算、预算为负、修饰器越权放大代数属于结构性缺陷，必须阻止保存。试算应区分理论生成请求数、实际创建数和被拒绝数，不能用截断后的数量掩盖配置的增长趋势。

对 `tagged` 的本稿推荐匹配约定见第 16 章：物品自身 `meta.tags` 用于表达作用域标签时，界面必须明确展示这一用途；若上游参数章已登记独立标签选择器，应由评审统一替换，不可在两个地方各维持一份互相不校验的标签集合。未匹配当前任何技能可给警告，但标签键不存在仍是错误。

## 14.5 表现、保存和契约探针规则

| 规则 ID | 触发条件 | 严重度 | 定位字段 | 报错文案 |
|---|---|---|---|---|
| V-070 | 表现段缺七类必备槽位或出现其他未登记段 | 阻止保存 | `presentation.fx` 等实际槽位 | E-0006 |
| V-071 | 正式表现订阅 debug_record 或结算之外的调试数据 | 阻止保存 | `presentation.damage_number.sources[i]` 等实际订阅路径 | E-0034 |
| V-072 | 表现配置存在逻辑回写或动画回调驱动出手 | 阻止保存 | `presentation.anim.alignments[i]` 中实际非法键 | E-0035 |
| V-073 | 音效启用但并发上限缺失或不是正整数 | 阻止保存 | `presentation.sfx.concurrency_limit` | E-0006 |
| V-074 | 动画启用却缺逻辑 tick 与动画帧对齐 | 阻止保存 | `presentation.anim.alignments[i].shot_tick`、`presentation.anim.alignments[i].frame` | E-0036 |
| V-075 | 拖尾未区分 independent 与瞬时外观方式 | 阻止保存 | `presentation.trail.carrier_mode` | E-0015 |
| V-076 | 数字合并跨目标、跨类型或回写合并后的逻辑伤害 | 阻止保存 | `presentation.damage_number.group_by` | E-0037 |
| V-077 | 玩家数字手填值与当前生效参数脱离 | 警告 | `meta.player_attributes` | E-0010 |
| V-078 | 资源缺失但有合法禁用占位方式 | 警告 | `presentation.fx.resources[i]` 等实际资源路径 | E-0007 |
| V-079 | 装载前行为契约探针失败 | 阻止保存 | 对应 `bricks[i].brick_id` 或 `params.triggers[i].produces` | E-0038 |
| V-080 | 非功能提示试图改变事件、来源链、排序或预算丢弃语义 | 阻止保存 | `runtime_hints` 中实际非法叶路径 | E-0009 |
| V-081 | 保存时底层定义已被其他操作更新 | 阻止保存 | `meta.version` | E-0039 |
| V-082 | 已合法应用默认值但作者尚未显式填写 | 提示 | 实际默认槽位，如 `params.shotgun_allowed` | E-0040 |
| V-083 | 迁移没有完整路径、目标版本未知或语义不能无损解释 | 阻止保存 | `schema_version` | E-0041 |
| V-084 | 预览使用内容与待保存内容指纹不同 | 阻止保存 | `meta.version` | E-0042 |

V-084 只阻止把旧预览结果认证为当前定义的“已验证保存”；普通合法 CFG 可以保存但标记“未预览”。界面必须区分保存与通过验收的发布状态，不能要求每次改一行备注都运行全部战斗，也不能把未经新预览的定义显示为已经验证。

## 14.6 从契约反推的完整性账本

固定行为不允许作者配置，仍必须在保存前得到正向证据。〔推荐默认〕积木目录登记时执行契约探针，保存时按积木内容指纹、运行时版本和启用能力检查对应探针凭据；新积木、修改过的积木或新增组合没有凭据时执行预览沙盒探针。探针失败使用 V-079 定位到引入该能力的积木卡，而不是要求作者去修改引擎内部顺序。

| 契约约束 | 前置静态校验 | 不可配置行为的探针断言 |
|---|---|---|
| 只有两个事件；结算记录只读 | V-019、032、060 | 不产生第三种事件，不修改已写记录 |
| 全份闪避、免疫、无敌的份级区别 | V-038、062、079 | 对齐 AC-36-01…04、AC-33A-02、AC-33B-05 |
| 候选接触与成功 hit 分别计数 | V-027…030 | 全闪避消耗目标额度、不耗 max_hits，不逐 tick 重掷 |
| 稳定排序、FIFO、死亡目标跳过 | V-019、079 | seq、target_id、part_index 稳定；同目标只记一次击杀 |
| 出手瞬时与派生瞬时边界 | V-022…026、079 | 出手当 tick；派生下一可判定 tick；命中先于结束 |
| 延迟与到期不补跳伤 | V-021、022、079 | 等待期不判定；到期与脉冲同 tick 不多打一跳 |
| purge 静默；自然结束至多一条 vanish | V-033…036、079 | 不补 hit、不派生，阵亡与打断并存先清理 |
| 防霰弹与家族登记分离 | V-057、069、079 | 同次出手独立实例抑制；分裂全家族记候选接触 |
| 代数、因果深度、来源标记和预算 | V-053…067 | 不重建根来源，chain_depth 不小于 generation |
| 三权限互不包含，叠加顺序固定 | V-040…052 | 从基准值重算；set→add→mul→clamp，不反向撤销 |
| snapshot 与 live 权限分离 | V-045、046、079 | 旧实例快照不变，live 不改历史、不增加行为 |
| 换装在 tick 起始原子应用 | V-079 | 新旧实例分离；公共冷却拒绝整批非法操作 |
| 位移施放门、控制锁与输入缓冲 | V-079 | 请求拒绝不开始前摇；缓冲到期丢弃，不用被动绕门 |
| 召唤独立闭环、上限和归属清理 | V-068、069、079 | 超限清理最旧；绑定主人死亡时 purge |
| 预算优先级、根实例保护 | V-055、056、080 | 先丢纯表现；拒绝新根不挤已有根，记录原因 |
| 固定步长、时间缩放、种子 RNG | V-021、079、080 | 暂停不推进；独立表现 RNG；相同输入逐次一致 |
| 正式 UI 与 debug_record 隔离 | V-070…076、079 | 关调试面板不影响战斗及正式合计数字 |

这些探针是编辑器装载前置门禁，不是本次文档已执行的测试。契约新增约束时，必须同时补静态规则或探针映射、文案和验收例子；只补正文不补覆盖账本不能宣称校验完整。

## 与运行时契约的引用关系

| 本章条款 | 主书稿章节／决策号 | 对应前置能力 |
|---|---|---|
| 类型、事件与原因码 | 5.4、6章、36.2—36.5、附录 B | 精确路径、枚举和只读校验 |
| 命中与调度 | 14章、36.7、D-09、R2、R12 | 静态参数加固定行为探针 |
| 权限与装配 | 16—18章、D-40—D-45、D-91、D-92、D-105 | 白名单、双向声明、原子替换 |
| 组合安全与触发 | 20—21章、D-48—D-57 | 预算、代数、来源链及冷却检查 |
| 非伤害与控制 | 36.9、AC-33A、AC-33B、D-90、D-104 | 份级条件与无敌边界探针 |
| 表现与规模行为 | 15.4—15.7、D-94 | 不定义性能门槛，只验证行为 |