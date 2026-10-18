# 技能编辑器 · 本地 Claude CLI 工作规则

> 本文件由 WorkBuddy（审核方）维护，Claude CLI（执笔方）每次开工前必读。
> 最后更新：2026-10-18　第 1 轮

## 零、开工必读前置（工作区级）

工作区手册：`D:/AI-game-All/G_docs/开发标准手册_v1.md`（方法层，178 行，开工必读）。
本项目定级 **P3 新系统**，最低流程：口径/规格 → 接口冻结 → 实现计划 → 分任务卡 → TDD → 并行集成 → 验证报告。

与本项目的对应（已就位，不必重做）：

| 手册环节 | 本项目落点 |
|---|---|
| ① 文档冻结（规格 + 接口） | `S_docs/技能系统书-v1.md` + T-000 冻结 `skill_core/api/` |
| ①.5 开发规范 | 本文件 + `S_docs/collab/00-协作协议.md` |
| ② 主会话串行冻结共享文件 | 目录所有权见协议第三节，共享文件由 WorkBuddy 串行收口 |
| ③ 拆子任务卡 | `01-WBS-任务拆解.md`，每路一张卡，零共享冲突 |
| ④ 多路并行 | 四条线各写自己目录 |
| ⑤ 主会话串行集成 | WorkBuddy 审核 PASS 后集成 |
| ⑥ 门禁验证 | GUT headless 全绿 + M6 验收清单 |

**手册 §4 TDD 铁则（本项目同样适用）**：
1. 测试期望来自规格，**不得按现有实现倒推**；预期与实现冲突时先核对规则，不为通过测试改断言。
2. 一次推进一个验收例子，禁止一次性写完实现再补测试。
3. 测试红了先修实现，不放松断言。
4. 断言前先问「它可能恒真吗」——空集合恒真类断言是高频坑。

**手册 §5**：遇到未定细节，给候选方案 + 优缺点 + 推荐理由 + 案例，再由人选择；不得只丢问题，也不得把推荐草案冒充已确认规则。

**联网规则**：WebFetch 在本机不可用；用 Bash 的 `curl -sL -m 20 -A "Mozilla/5.0" "<URL>"`。Godot 文档与 GitHub raw 可直连。外部资料只有真正抓到原文才能标「外部事实」，否则标「灵感，待核验」。

## 一、你的角色

你是**执笔方**：按任务卡写代码 + 写 GUT 测试 + 跑绿 + 交回执。
WorkBuddy 是**审核方**：拆任务、给素材、审回执、判 PASS/REJECT。

**你不做**：改规格真源、改协作文档、扩任务范围、跳过门禁、替用户做方向性决策。

## 二、开工前必读（按顺序）

1. `S_docs/collab/00-协作协议.md` — 角色边界、目录所有权、回执模板、审核判据、门禁
2. `S_docs/collab/01-WBS-任务拆解.md` — 任务卡（ID／依赖／产出／验收／禁止）
3. `S_docs/collab/02-决策台账.md` — 已拍板决策，避免你重复做决定

**不要通读** `S_docs/技能系统书-v1.md`（12245 行 / 1.17MB）。用 `S_docs/collab/assets/` 下的机器可读素材，需要原文时读 `assets/_raw_*.md` 章节切片，并按协议第二节的权威层级判读。

## 三、素材（只读，写前先看）

| 文件 | 内容 |
|---|---|
| `S_docs/collab/assets/schema_v0_1.yaml` | Schema v0.1，落盘结构唯一依据 |
| `S_docs/collab/assets/brick_catalog.json` | 28 块积木目录 |
| `S_docs/collab/assets/validation_rules.csv` | V-001…V-084 |
| `S_docs/collab/assets/error_messages.csv` | E-0001…E-0042 |
| `S_docs/collab/assets/acceptance_cases.csv` | ED-78 + AC-166 验收用例 |
| `S_docs/collab/assets/_raw_*.md` | 真源章节切片（ch04/ch05/ch14/ch15/ch16/ch20/卷三/卷四） |

## 四、硬约束（违反即 REJECT）

1. **`res://skill_core/` 内禁止引用任何编辑器 API**（`@tool`、`EditorPlugin`、`EditorInterface`）。core 必须 headless 可测。
2. **禁止硬编码策略**：积木 ID、载体枚举、part_type、原因码、权限等值一律从素材载入，代码保持通用。
3. **禁止把运行态写回 CFG**：`instance_id`、`seq`、`origin`、`snapshot`、`state`、结算结果不落盘。
4. **禁止先保存后校验**：任何保存路径必须过 `skill_core/validate/`。
5. **禁止严重度降级**：真源标「阻止保存」的不能变警告。
6. **禁止对空集合跑「全部成立」**来冒充验收通过。
7. **只写你有权限的目录**（见协议第三节）。越权写入直接 REJECT。
8. **不修改** `S_docs/技能系统书-v1.md` 与 `S_docs/collab/00*.md`、`01*.md`、`02*.md`。

## 五、交付流程

```
领取任务卡 → 实现 + 写 GUT → 本地跑绿 → 写回执 → 等审核
```

回执写到 `S_docs/collab/reports/T-xxx.md`，模板见协议第四节（缺项直接 REJECT）。

**测试门禁**（两条命令都要能跑通）：

```bash
# 唯一正确的引擎（4.7.1-stable，由 Ryko.GodotHub 管理）
GODOT="C:/Users/Administrator/AppData/Roaming/Ryko.GodotHub/godot-versions/4.7.1-stable/Godot_v4.7.1-stable_win64.exe"

# 步骤 1：预热导入（只在新增/删除 .gd 文件后需要一次）
"$GODOT" --headless --path . --import --quit

# 步骤 2：跑测试——必须逐个文件串行，一个进程跑一个文件
GODOT_DISABLE_LEAK_CHECKS=1 "$GODOT" --headless --display-driver headless \
  --audio-driver Dummy --path . \
  -s res://addons/gut/gut_cmdln.gd -gtest=res://tests/<文件名>.gd -gexit
```

**十六个坑（已踩过，别再踩）**：
1. `godot` **不在 PATH**（portable 版），必须用上面的绝对路径。写 `godot` 会 command not found。
2. **版本必须锁 4.7.1**。用 4.7.2 跑过一次 import，把 `.godot/` 缓存写成 4.7.2 格式，与用户开着的 4.7.1 编辑器抢同一份缓存，**直接把编辑器搞崩过**。`Downloads/Godot_v4.7.2-.../` 那个**禁用**。
3. **禁止 `-gdir=res://tests -ginclude_subdirs`**。实测该模式会挂起 5 分钟无输出直到超时。必须用 `-gtest=` 单文件模式，每个文件 0.4 秒。全量门禁 = 对每个 `res://tests/test_*.gd` 串行循环。
4. `GODOT_DISABLE_LEAK_CHECKS=1` 不能省，否则引擎退出噪声会让退出码不等于测试结果（绿跑变红）。
5. **别把函数头写丢**（T-011 真踩过）：`r_types.gd` 里 `_type_or_range_error(value, entry) -> String` 的**签名行在编辑中丢失**，
   函数体变成游离代码，`--check-only` 一次抛 7 条 Parse Error（`Function "_type_or_range_error()" not found in base self` +
   一串 `Identifier "entry"/"value" not declared` + `Cannot return a value of type "String" as "Array[String]"`）。
   **只有第一条（not found in base self）是真定位点**，后面的都是连锁噪声。写完函数体回头确认签名行还在；
   看到 `Function X() not found in base self` 先查是不是函数头没了。
6. **Variant 跨类型比较会抛运行时错误**（T-012/T-033 真踩过）：`permission` 这类「作者可能乱填」的字段
   被填成 Array / int / null 时，`value == "some_string"` 或 `value != "x"` 会抛
   `Invalid operands 'Array' and 'String' in operator '=='`。它**不中断脚本**，但被 GUT 计为
   `Unexpected Errors` → 整个用例红掉，且断言数只差 1，极难一眼看出。
   写法：先 `var text: String = value if value is String else ""`，再用 `text` 做比较；
   语义上「非法值由专门的枚举/类型规则拦截，其余规则跳过，不重复报错」。
7. **Dictionary 用点语法写「新键」会生成 StringName 键，不是 String**（T-033 真踩过）：
   `dict.new_key = v` → 键是 `&"new_key"`；`key is String` 为 false，`dict.has("new_key")` 取不到，
   与素材（JSON 解析出来是 String 键）对不上。新键一律写 `dict["new_key"] = v`。
   已有键用点语法赋值没问题。
8. **给显式类型变量赋 null 会抛运行时错误**（T-034 真踩过）：`var list: Array = by_target.get(target, null)`
   在键不存在时抛 `Trying to assign value of type 'Nil' to a variable of type 'Array'`；
   它**不中断脚本**但让函数返回空值，下游 `result.ok` 再报一次 `Invalid access to property or key 'ok'`，
   两条连报且第二条具有误导性。从容器取值且可能为空时，变量一律声明为 `Variant`，再用
   `is Array` / `is Dictionary` 判定后按需创建（与坑 2「默认值写 null」是同一家族：判空在赋值之后，不在赋值之时）。
9. **JSON 解析出来的数字一律是 float**（T-013 真踩过）：实测 `JSON.parse_string('{"a":1}')["a"] is int` → **false**（typeof=float）。
   所以**不要对素材 JSON 里的数值用 `is int` 单判**（`minimum is int` 恒为 false → 该子检查静默不触发，测试只差 1 个断言且报 `actual=[]`，极难看出）。
   素材数值一律按 `value is int or value is float` 判定后再 `float()` 比较；
   反过来，**作者填进 CFG 的值**才用严格 `is int` 做 integer 字段类型校验 —— 两者不要混淆。
10. **「路径合法性」在素材侧与作者侧是两个判据，不得复用同一个函数**（T-031 真踩过）：
    `params_meta.json` 的 `arrays[].path` / `objects[].path` **带下标段**（`templates[i].parts`、
    `templates[i].cast.shot_ticks`），而作者手填的键**严禁 `[` `]`**（下标由解析器生成）。
    T-031 把两者共用一个 `_valid_path()` → `configure()` 在第一条数组登记上就显式失败 →
    `_ready=false` → 全部 9 条用例拿到 `{ok:false, diagnostics:[LOCK_GUARD_INVALID]}`，
    GUT 只显示 `last_error`，完全看不出是素材口径问题。
    修法：拆成 `_valid_meta_path()`（先 `replace("[i]","")` 再分段校验）与 `_valid_path()`（拒绝 `[`/`]`）。
11. **素材 JSON 里的 `_` 前缀键是注释/元信息，不得计入业务条目数量**（T-046 真踩过）：
    `derive_meta.json` 的 `event_roles` / `budget_roles` 都带 `_note` 说明键。
    凡是「遍历素材字典的键」去做数量校验或查表（`roles.size() != enums.event.size()`、
    `for role in budget_roles: hard_caps.has(...)`），**必须先跳过 `str(key).begins_with("_")`**，
    否则一条 `_note` 就让数量对不上 / 把注释文本当成硬上限名去查表，报出
    `Missing project hard cap: 硬上限名 → project_limits.hard_caps 的键` 这种完全看不懂的错。
    已 PASS 的模块没暴露是因为它们用注入覆盖（override 里没有 `_note`）——
    **一旦改用 `res://data/*.json` 原文件配置就会炸**，所以这条对每张新卡都成立。
12. **测试脚本里不要调 GUT 不存在的方法**（T-006 真踩过）：`fail("...")` **不是** `GutTest` 的 API。
    后果比红灯更危险：它在**解析期**就抛 `Function "fail()" not found in base self` → 整个测试脚本
    **加载不了** → GUT 输出 `Nothing was run`、**0 条用例执行**，看板上会被误读成「通过」（假绿）。
    要制造「必然失败」用 `assert_true(false, "...")` 或 `assert_false(true, "...")`。
    同理：写完测试后若 GUT 报 `Ignoring script ... because it does not extend GutTest` 或
    `Nothing was run`，**先查是不是脚本根本没解析过**，不要当成环境问题。
13. **「区间内出现某类诊断」这类断言会恒真**（T-015 二轮真踩过，审核方反向对照才发现）：
    测试写「破坏 CFG 后，诊断里出现 V-039…069 区间的规则号」，而**基线（未破坏的）CFG 本身就带 6 条 V-053**，
    于是断言不改 CFG 也能通过 —— 看起来 5/5 全绿，其实**根本没证明那张卡被触发**。
    修法（通用）：**先跑一次基线拿到 `baseline`，再断言「相对基线新增的规则号」**
    （`_new_in_range(baseline, result, first, last).size() > 0`）。
    凡是「断言某个集合非空 / 某类东西存在」的用例，写之前先问一句：
    **它在什么情况下会恒真？基线状态是不是就已经满足了？**
16. **`String(x)` 不是万能转换器**（T-062 真踩过）：Godot 4 **没有** `String(Color)` / `String(null)` 构造器，
    运行期抛 `Invalid call. Nonexistent 'String' constructor.`，整条用例记 Unexpected Errors（脚本能编译过，静态检查抓不到）。
    凡是「把值拼成字符串」的地方一律用 `str(x)`；`Color` 显式 `to_html()`，`Vector2` 显式取 `.x/.y`。
    **同一家族**：`"%s|%s" % [a]` 占位符与实参数量不等 → `validated_evaluate` 类型/参数错误，
    现象同样只有运行时才炸。改格式串后**必须数一遍占位符个数**。
15. **新增脚本的 `class_name` 不能当类型名用**（T-023 真踩过，审核方修的）：
    `class_name` 只在 **全局类缓存** `.godot/global_script_class_cache.cfg` 里，而本项目**不依赖编辑器 import 刷新缓存**
    （实测已存在很久的 `SkillUnits` 在缓存里 **0 条**，因为 core 模块从来都是 `preload()`、不写裸类名）。
    所以 `var _units: SkillUnits` / `var form: ParamForm` 这种写法必定
    `Parse Error: Could not find type "X" in the current scope`，**整脚本加载不了**。
    写法：声明 `class_name` 可以，但**任何地方要用它做类型标注，一律 `const X = preload("res://...x.gd")` 再用 `X`**。
14. **坑 9 的隐藏变体：严格 `is int` 会把「素材默认值」判成非法**（T-016 真踩过，审核方在 core 里修的）：
    `r_modifier.gd` 的 `_limit()` 读 `res://data/project_limits.json` 的 `defaults.max_generation`，
    素材 JSON 解析出来是 **float 1.0**，`not value is int` 恒成立 → 报「项目限值不可用」→
    **每个积木 2 条 V-053**，基线永远不干净，连累 T-016 全部 84 条边界断言红掉。
    它自己 T-012 的 41/41 全绿，是因为测试用**注入整数**，绕开了真实素材（与坑 11 完全同家族：
    **已 PASS 的模块一旦改用 `res://data/*.json` 原文件配置就可能炸**）。
    修法：**凡是从素材/注入上下文取到的数值**，一律 `value is int or value is float` → `float()` →
    校验「有限且 `floor(n)==n`」→ `int(n)`；**只有作者手填进 CFG 的值**才用严格 `is int`。
    写新卡时凡涉及 `project_limits` / `hard_caps` / 素材默认值，先按这条写。

### ✅ 唯一例外：你被允许跑 `--check-only` 语法检查

```bash
GODOT="C:/Users/Administrator/AppData/Roaming/Ryko.GodotHub/godot-versions/4.7.1-stable/Godot_v4.7.1-stable_win64.exe"
timeout 60 "$GODOT" --headless --check-only --script res://<你改的文件>.gd
```

- 坏文件 → 退出码 **1**，打印 `Parse Error: ... at: ... (文件:行号)`；好文件 → 退出码 **0**，无输出。
- **不导入项目、不写 `.godot/`、不跑测试**，所以可以放心跑（这是它区别于 import/GUT 的关键）。
- 你写完**每个** `.gd` 文件都要跑一次，退出码必须 0 才能进回执。
- **仍然禁止**：`--import`、`--path`、`-s ...gut_cmdln.gd`、任何 GUT 命令。这些归 WorkBuddy 独占。

**为什么必须自查**：前两轮连续出现编译期错误（`var x := dict.duplicate()` 推断 Variant 失败、`SomeClass.static_only()` 调用非静态方法），两者都是**整脚本加载失败**，连带把依赖它的全部测试打成红，且报错信息（如 `Nonexistent function 'new'`）具有误导性。人眼静态复核拦不住这类错误，`--check-only` 能。

**引擎调用纪律**（硬性）：
- **不要并发跑多个 Godot 进程**，跑之前先确认没有其他 Godot 在跑。
- **不要跑到自己绿为止**——跑一次拿到原始输出即可，红了就是红了，把输出贴进回执。
- 新增 `.gd` 文件后只需**一次** import，不要每改一次就 import。
- 已知：`GUT 9.6.1` 对 4.7.1 有兼容性警告（建议 9.7.1），**不阻塞**，登记为 U-08。

## 六、遇到冲突

**不要自己二选一**。登记到回执「未决与风险」，写两处真源行号，按**较严口径**实现并留 `TODO(U-xx)`，由 WorkBuddy 裁决。

## 七、当前批次

首批可并行任务见 `01-WBS-任务拆解.md` 第九节。**T-000（冻结核心接口）为单点先行任务**，其余线可基于本协议已定死的目录树同时开工。

### 本批次特别纪律：你不要调用 Godot（第 2 轮起生效）

**引擎由 WorkBuddy 独占执行**。你在这一轮**只写代码 + 写测试，不运行 `godot` 命令**（不改 ENGINE 调用、不跑 import、不跑 GUT）。

理由：多路并发跑 Godot headless 会抢 `.godot/` 缓存，已经把用户的编辑器搞崩过一次。你写完后，WorkBuddy 串行跑全量门禁，把**原始失败输出**回传给你，你据此修。

因此你的交付标准是：
1. 代码与测试写完，目录不越权；
2. 自己**静态复核**一遍 GDScript 语法，重点六条（都是本项目真踩过的坑）：
   - `:=` 对 Variant 推断失败（从 Array/Dictionary 取元素、`.duplicate()` 返回值），一律写显式类型；
   - `static` 与实例调用混用（如 `SomeClass.is_tool()` 调非静态方法）；
   - **`.get(key, {})` 用可变容器作默认值会掩盖「键不存在」**——取子节点并按需创建时，
     默认值必须写 `null`，新建的中间层容器必须显式写回父节点（见决策 D-20，曾让 `resolved` 恒为空）；
   - **函数头丢失**（T-011）：函数体游离 → 一串 `Identifier not declared` / 返回类型冲突，
     真定位点是 `Function X() not found in base self` 那一条（见第五节坑 5）。
   - **Variant 跨类型比较**（T-012/T-033）：作者可乱填的字段先转 `String`（非字符串即空），
     再参与 `==`/`!=`，否则 GUT 记为 `Unexpected Errors`（见第五节坑 6）。
   - **点语法写新键变 StringName**（T-033）：新键必须 `dict["key"] = v`（见第五节坑 7）。
   - **显式类型变量被赋 null**（T-034）：`var arr: Array = dict.get(k, null)` 会抛运行时错误，
     容器取值一律先声明 `Variant`，再用 `is` 判定（见第五节坑 8）。
   - **素材 JSON 里的数字是 float**（T-013）：`is int` 单判恒为 false，会让子检查静默不触发；
     素材数值用 `is int or is float` 判定，只有作者填进 CFG 的值才用严格 `is int`（见第五节坑 9）。
   - **「路径合法性」在素材侧与作者侧是两个判据**（T-031）：素材登记路径**带 `[i]` 下标段**
     （`templates[i].parts`），作者输入的键**严禁 `[` `]`**。用同一个校验函数会让 `configure()` 在第一条
     数组登记上显式失败 → `_ready=false` → 全部用例拿 `LOCK_GUARD_INVALID` 红掉，且失败信息只显示
     `last_error`，极难看出是素材口径问题（见第五节坑 10）。
   编译错误会让整脚本加载失败，代价很高；
3. 回执里写「自测声明：未运行引擎，已静态复核 X 处」，并把你认为可能红的点列进「未决与风险」。

不要因为没跑过就写"已通过"——写"未验证"即可，**绝不伪造门禁结果**（协议硬门禁第 3 条）。
