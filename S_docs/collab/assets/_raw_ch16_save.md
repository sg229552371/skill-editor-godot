# 第 16 章　保存与版本

〔2026-10-18 第1轮〕完成判定不是“导出了一段 YAML”，而是导出的 CFG 与编辑器校验使用同一结构定义，能被相同版本运行时加载，重开后参数、权限和引用含义不丢失。本章冻结七键骨架，子字段作为本稿明确提案交给 Schema 合并方，不声称仓库已有完整 Schema 实现。

## 16.1 七个顶层键与三层数据

| 顶层键 | 保存类型 | 保存内容 | 不允许混入 |
|---|---|---|---|
| `schema_version` | string | 当前结构版本 `"0.1"` | 数值 0.1、技能版本、文档版本 |
| `skill_id` | string | 第13章完整主键 | 运行时实例编号 |
| `meta` | object | 归属、标签、版本、作者及设计说明 | 施放时的实时战斗状态 |
| `bricks` | array | 每项严格为十二字段积木登记卡实例 | 临时第十三个卡字段 |
| `params` | object | 逻辑参数、覆盖、暴露和触发定义 | 不可配置的内部工序 |
| `presentation` | object | fx、sfx、anim、trail、camera、damage_number、status_icon 七段 | 反向修改逻辑的回调 |
| `runtime_hints` | object | 已登记非功能性提示 | 掩藏逻辑参数和安全上限 |

编辑态有选择、光标、折叠、撤销栈；定义态有七键 CFG；运行态有 `instance_id`、`seq`、`origin`、`snapshot`、`state` 和日志。三者分离。编辑器的脏标记不写进技能，运行时结果不回灌 `params`，导出时也不能把整个调试面板序列化成第八个键。

〔推荐默认〕单文件采用 UTF-8 YAML，禁止重复键、自定义执行标签和不能展开为普通值的引用结构。布尔必须是真布尔，空集合明确写空集合；缺省与 null 不等价，未登记允许 null 的字段拒收 null。所有数字必须有限，逻辑时间以整数 tick 保存。编辑器可以提供秒数输入，但换算后只提交 tick 值，并在界面展示采用的项目频率与向上取整结果。

## 16.2 本稿子字段落点与上下游归属

以下子字段落点均为〔推荐默认〕，其字段语义优先采用主书稿已有词表；仅目录组织和编辑支撑字段为新增提案。参数章如果已登记同一语义不同路径，评审必须选定唯一落点再合书，不能让保存器写一种、校验器读另一种。本稿内部一律按此表，不用未登记的路径简称替代。

| 路径 | 内容与类型 | 约束及默认 |
|---|---|---|
| `meta.role`、`meta.category` | string、enum | 与 skill_id 一致，必填 |
| `meta.short_name`、`meta.variant` | string、string | 短名必填，变体可空；不从最后下划线猜测 |
| `meta.name`、`meta.author`、`meta.version` | string | 显示名、执笔信息、技能自身版本 |
| `meta.tags[]`、`meta.pools[]` | string 引用集合 | 去重，引用登记目录 |
| `meta.design_notes`、`meta.copied_from` | string、可选技能引用 | 设计说明、复制来源，非运行时父引用 |
| `meta.player_attributes` | 已登记参数路径集合 | 只声明展示哪些参数，不手填最终数字 |
| `params.carrier`、`params.lifetime_ticks` | enum、int | 对齐运行时载体和寿命词表 |
| `params.windup_ticks`、`params.cooldown_ticks` | int | 非负；由登记卡确定默认 |
| `params.shot_ticks[]`、`params.start_delay_ticks` | int 数组、int | 相对闭环出手时间表与实例开始延迟，不混用 |
| `params.projectile_speed`、`params.hit_radius` | float | 单位、范围和默认由参数登记提供 |
| `params.hit_policy` | object | per_target_limit、rehit_interval_ticks、max_hits 三子字段 |
| `params.shotgun_allowed`、`params.on_target_lost` | bool、enum | 默认 false、continue |
| `params.attach_to_caster`、`params.bind_owner`、`params.summon_cap` | bool、bool、int | 默认 false、true；召唤必须有上限 |
| `params.max_generation`、`params.cast_budget` | int | 派生上限默认一代；预算由项目配置解析，不写死示例值 |
| `params.split_budget`、`params.chain_remaining` | int | 只有相应积木启用时出现，不允许子体重置额度 |
| `params.parts[]` | 份定义数组 | 保留 part_index、type；数值内容由对应份类型登记 |
| `params.brick_overrides[]` | 覆盖数组 | 每项 brick_index、values；索引指向本文件 bricks |
| `params.derivations[]` | 派生规则数组 | trigger_id、on、reasons、allow_restricted_reason、produces |
| `params.triggers[]` | 被动规则数组 | trigger_id、on、condition、chance、internal_cooldown_ticks、max_chain_depth、allow_self_chain、produces、可选 strength_coeff |
| `params.triggers[i].zero_cooldown_note`、`params.triggers[i].self_chain_note` | string | 仅显式例外时要求，说明不会替代预算字段 |
| `params.modifiers[]` | 修饰器数组 | 每项保持 modifier_id、permission、scope、inheritable、targets、stack_rule 六字段 |
| `params.exposed_fields[]` | 字段暴露数组 | name、permission、min、max、live、inheritable、set_conflict_note |
| `runtime_hints.budget_profile`、`runtime_hints.bucket_profile` | 可选登记引用 | 只引用项目策略，不在技能内改优先级与排序 |

修饰器接口六个字段之外不暗加 `value` 等孤立字段。〔推荐默认〕`stack_rule` 保存结构化运算登记，包含运算种类和操作数；具体表示需参数章与 Schema 共同收口。校验时先检查其运算种类，再核对操作数单位和目标类型。未登记运算不能以字符串表达式执行；多个 set 的挂载次序来自运行时装配输入，不由文件键排序决定。

〔推荐默认〕本阶段 `scope=tagged` 使用该物品定义的 `meta.tags[]` 作为匹配集合，至少命中一个登记标签；界面显式标为“作用域标签”。这是为冻结六字段接口提供的临时明确落点，不宣称主书稿已规定标签选择器。若一个物品的多个修饰器需要不同标签集合，本稿不假装已支持，应交评审选择登记表达方式；不能往六字段接口偷偷增加自定义字段。

份定义与事件载荷不是同一结构。配置 `params.parts[i]` 定义产生何种份及输入数值；`evaded`、`final_amount`、`any_reduced_to_zero`、`killed` 是运行结果，不作为策划预填值保存。若导入文件把这些结果写在份定义中，按未知字段拒收。条件可以按 `hit_settled.parts[].type` 过滤，但不能访问其中不存在的 `final_amount`。

## 16.3 积木默认值、覆盖与确定性展开

每项 `bricks[i]` 仍严格包含 brick_id、name、tagline、carrier、summary、default_cfg、author_params、locked_params、relic_params、presentation、player_text、status。`default_cfg` 是可被运行时读取的 CFG 片段，不把中文概述当执行内容。所有默认片段展开后须经过同一 Schema，不允许“登记卡默认值绕过校验”。

〔推荐默认〕通用 `params` 字段提供设计卡级配置，`brick_overrides` 提供具体卡覆盖；一个逻辑叶字段只能有一个最终权威赋值来源。按“登记默认→通用适用覆盖→指定卡覆盖”展开，覆盖前先检查锁定声明。两张卡映射到同一个能力槽而没有组合规则时拒绝装载，不以数组后者悄悄覆盖前者。不同效果体的半径不能因为字段同名被合并成一个数值。

数组默认整体替换，不隐式拼接；引用列表是否可并集合并必须在参数登记显式声明。深层对象按登记叶字段覆盖，不能递归接受任意键。默认值来源、覆盖来源和最终值均在界面可查；保存的是作者定义，预览加载的是规范化展开结果，两者之间保留路径来源表，用于把错误定位回真实输入。

积木目录更新不得自动改变已保存定义。本稿保存完整登记卡实例，故旧存档继续保留当时 default_cfg。作者选择更新目录卡后先看差异，包括默认参数、锁定字段、暴露字段和表现引用，再整体校验并递增技能版本。不能只更新中文说明却在背后换掉逻辑默认值，也不能凭同一个 brick_id 宣称内容完全相同。

## 16.4 与附录 B 的逐项对齐

| 附录 B 项 | 技能 CFG 落点或处理 | 不可误用 |
|---|---|---|
| doc | 文档元信息，不写入技能顶层 | 文档版本不等于 schema_version |
| events、vanish_reasons | derivations 的枚举校验源 | 不把事件集合做成作者可扩展列表 |
| carriers | params.carrier 与卡 carrier 的校验源 | 使用 none、self、independent、attached |
| instance_fields、instance_states | 运行时检查器的只读显示词表 | 不保存场上实例到定义 |
| hit_policy | params.hit_policy | 候选接触与成立 hit 的计次不得互换 |
| hit_payload、vanish_payload | 预览与回放读取结构 | 不预填运行结果 |
| settlement_records、debug_record | 订阅与调试面板的白名单 | debug_record 不进入触发或正式 UI |
| defense_semantics、invulnerable_extension | 固定结算语义与契约探针 | 不制造技能级“无敌忽略治疗”开关 |
| snapshot_layers、snapshot_fields | 快照观察器读取结构及参数登记依据 | L3 修改技能字段，不混进属性快照 |
| input_buffer | 项目级输入策略与预览夹具引用 | 不在单技能重复发明窗口语义 |
| modifier | params.modifiers | 三权限、作用域、继承和固定运算顺序 |
| card_extra_fields | params 同名字段及 triggers 对应字段 | 不丢弃召唤上限、冷却和触发标识 |
| collision_priority_reference | 积木契约校验依据 | 不开放内部碰撞工序排序器 |
| budget_rule、runtime | 固定行为探针及项目配置引用 | 非功能提示不改逻辑顺序和清理语义 |

附录 B 的 `same_tick_spawn_hits_next_tick` 不能机械解释成所有生成物都延后一 tick。第 36 章和第 14 章区分出手创建与派生创建，本稿按该区别验收。载体冻结约定中的 `instant` 也不能不经说明直接写入运行时；本稿使用 `none` 表示瞬时载体，并保留 `self` 位移跟随判定体。两处冲突列入末尾，不改共享文件。

## 16.5 保存事务与失败保护

保存按钮先检查身份，再解析依赖，展开默认及覆盖，执行结构和语义校验，最后提交单份定义。提交期间使用打开时的版本与内容指纹作为基线，基线已变化就停止，不覆盖外部更新。成功后更新目录索引、当前文件版本和脏标记；任何一步失败，旧持久化内容仍可加载，界面保留作者输入并指出失败阶段。

〔推荐默认〕正式实现使用具备原子替换语义的存储服务，具体落盘机制由后续实现任务确定；本次规格撰写不创建任何辅助文件。保存后以实际持久化内容重新解析并比对规范化值，不能只相信按钮回调返回成功。写入成功但重读失败时标为“保存完整性失败”，不得自动清除草稿或显示通过验收。

编辑器可保留未通过校验的内存草稿，但草稿不是可执行 CFG。若未来提供草稿持久化，应由项目编辑态存储规格定义，与技能目录隔离；本章不增加草稿文件格式。导出、另存和批量操作都必须调用同一校验入口，不能出现普通保存拒绝而导出按钮放行的旁路。

## 16.6 版本不匹配与迁移策略

| 输入版本状态 | 打开方式 | 保存方式 | 原文件保护 |
|---|---|---|---|
| 当前支持版本 | 正常编辑 | 全量校验后保存 | 基线冲突检测 |
| 已知旧版且有完整迁移链 | 先只读展示，生成内存迁移预览 | 确认迁移差异后以新版本提交 | 迁移提交前原内容不变 |
| 已知旧版但链缺一段 | 只读，展示缺失边 | 阻止保存为当前版 | 不做猜测性补键 |
| 比当前更新的版本 | 只读查看可解析原文 | 阻止降级覆盖 | 不删除未知字段 |
| 版本缺失 | 标为未识别结构 | 仅在明确导入适配器识别后迁移 | 不直接填当前版本 |
| 版本合法但语义冲突 | 只读并列差异 | 阻止认证与迁移提交 | 不以类型正确掩盖行为变化 |

迁移按版本边逐步执行，每条边声明前置条件、字段变换、默认补入、丢失信息和行为影响。没有跨越某版本的登记边，就不能把版本字符串直接改成当前值。迁移预览必须给出源路径、目标路径、旧值、新值和理由；自动补入默认值也要可见。对于载体名称、计数单位、输入缓冲语义等会影响行为的差异，迁移必须要求对应契约测试重新通过。

〔推荐默认〕同一源内容重复迁移得到相同规范化结果；已经是目标版本时再次迁移不再改动。保留技能身份，递增技能自身版本，并在设计说明追加迁移来源和原因。迁移不重置修饰器权限、不扩大标签作用域、不把未知事件改成 hit、不把非法时间截断为零。无法无损解释的字段必须阻止提交，不能删掉它以后称迁移成功。

对于未带版本但形似附录 B 的 YAML，编辑器识别为“契约摘要而非技能定义”，不执行技能导入。对于旧载体 `instant` 的输入，仅当导入适配器明确证明它表示瞬时无载体且不存在需要 `self` 的位移语义时，才可建议映射 `none`；本稿不把这个映射注册为普遍事实。所有未知状态保留原文供评审，而不是进入可运行库。

## 16.7 保存格式完成判定

同一字段登记应驱动控件、校验器、序列化器、加载器和错误定位；不得分别维护五份不同默认值。完成判定包括七键严格一致、十二字段卡严格一致、七表现段严格一致、每个可填叶字段在 Schema 中有类型和范围、每条校验能定位到保存字段、往返不丢值、运行时加载无隐式修复。规范化前后允许键排序变化，不允许数组语义顺序和引用含义变化。

本稿提供的是接口提案和验收标准，不是最终 Schema 文件。评审合书时必须把本稿推荐子字段与第 5、9 章登记逐项对照；若未完成合并，应将“CFG Schema 一致”保持未验收状态。不能仅因顶层七个名字一致就勾选整个硬指标，也不能用本稿自己定义的字段去证明已有运行时已经支持。

## 与运行时契约的引用关系

| 本章条款 | 主书稿章节／决策号 | 对齐依据 |
|---|---|---|
| 七键与登记卡 | 冻结约定第一、三、七节 | 存档形状唯一 |
| 配置与实例隔离 | 5.4、36.4、附录 B instance_fields | 运行结果不写回定义 |
| 枚举和权限 | 36.2—36.6、附录 B | 不改既有词表和数值工序 |
| 快照分层 | 附录 B snapshot_layers、D-92 | L0—L2 入快照，L3 为技能字段修饰 |
| 迁移行为验证 | 第14章、D-09、36.8 | 迁移不等于只换版本字符串 |
| 生成时机冲突处理 | 14.4、36.7 | 细则优先于摘要的笼统布尔项 |