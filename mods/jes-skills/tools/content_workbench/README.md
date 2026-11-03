# 策划配置表工具 · 使用说明（content_workbench）

> 全中文说明 · 面向策划与接手本工具的 AI。
> 本文件只描述**已实测**的命令与参数；所有路径一律写成「相对项目根」，不含任何本机盘符绝对路径。
> 工作目录约定：以下命令**全部在项目根**（含 `project.godot` 的那一层）执行。

---

## 〇、怎么用：点哪里、跑哪条

**没有可双击的 exe。**这是一个「Excel 填表 + 命令行工具」的组合：

- **策划动手的地方** = 一个 Excel 文件：`mods/jes-skills/content_src/技能配置表.xlsx`（双击用它打开）。
- **执行生成的地方** = 在项目根开一个终端（PowerShell），跑下面的命令。

### 策划日常三步（只用 Excel + 一句话）

1. **双击打开** `mods/jes-skills/content_src/技能配置表.xlsx`。
2. 到 **「② 技能卡」「③ 效果段」「④ 辅助石」** 三个页签里填：
   - 每个单元格**点一下**右上角的小红三角 → 弹出中文说明，写清这列填什么；
   - 有下拉箭头的格子（施法方式、消耗类型、效果、形状、属性、阵型…）**点格子右边的箭头选**，不要手打；
   - 新增内容 → 填到**已经解锁的预留行**（②第73行起、③第102行起、④第19行起，右击行号能看到没有锁）：「技能代号」列不用管，留空就行，工具会自动生成；
   - 改完 **按 Ctrl+S 保存**。
3. 在终端跑这两条（**这是唯一的「提交」动作**）：

   ```powershell
   # 先检查表填得对不对（错会逐条告诉你：哪个页签、第几行、哪一列）
   python mods/jes-skills/tools/content_workbench/build/read_workbook.py mods/jes-skills/content_src/技能配置表.xlsx

   # 全部正确后，交给开发者跑一键收尾（会跑 Godot 与全量门禁）
   python mods/jes-skills/tools/content_workbench/finish/run_all.py --godot <Godot 控制台 exe 路径>
   ```

   报错时打开 **「⑥ 检查结果」页签**（或看终端），按「怎么改」那一列改，再跑一次。

### 开发者日常（常用 4 条）

| 想做什么 | 跑什么 | 会不会动正式内容 |
|---|---|---|
| 查表有没有填错 | ② 读表校验 | 不会（只写 `_tmp/`） |
| 生成看效果 | ③ 生成资源 | 不会（只写 `_tmp/dryrun/`） |
| 全链自检 + 门禁 | ④ 一键收尾 | 不会（只回写⑥页签） |
| 让游戏真正用上 | ⑤ 空跑看清单 → ⑥ `--apply` | **会**，需制作人拍板 |

> 一句话记忆：**Excel 负责「写」，终端负责「检查与生成」，`--apply` 才负责「上线」。**

---

## 一、这个工具是干什么的

一句话：**Excel 工作簿是唯一真源（单一真源），Godot 的 `.tres` 资源由它一键生成。**

```
   策划在 Excel 里填表
          │
          ▼
   content_src/技能配置表.xlsx        ← 人写的唯一真源（6 个页签）
          │  读表校验 + 生成
          ▼
   tools/content_workbench/_tmp/dryrun/*.tres   ← 干跑产物，先看不动正式内容
          │  落盘（需人工确认）
          ▼
   content/gems/active/    67 个主动技能 .tres
   content/gems/supports/  13 个辅助石   .tres   ← 游戏真正读取
```

- **单一真源**：内容只改 `.xlsx`。`.tres` 是生成物，**手改会被下一次生成覆盖**。
- **先干跑、后落盘**：生成只写 `_tmp/dryrun`，正式目录 `content/gems/` 只有落盘工具（`--apply`）会写，且必须人工确认。
- **契约驱动**：表结构、中文词表、下拉项、必填规则全部由 `schema.json` 决定，代码里不再内置第二份口径。

### 工作簿 6 个页签

| 页签 | 内容 | 数据行量（基线） |
|---|---|---|
| ① 先看这里 | 三句话说明 + 三色图例 + 常见错误 | — |
| ② 技能卡 | 一行一个主动技能 | 67 行（另有 4 行锁定示例） |
| ③ 效果段 | 一行一个效果段，双段技能占两行 | 95 行（另有 5 行锁定示例） |
| ④ 辅助石 | 一行一个辅助石 | 13 行（另有 4 行锁定示例） |
| ⑤ 可选项 | 全部下拉词表（**隐藏**，工具自动生成，策划不看） | — |
| ⑥ 检查结果 | 生成后回写的中文错误：页签 + 行 + 列 + 问题 + 怎么改 | 由工具写 |

### 填表三色规则

- **黄色格** = 本行必填（只按契约 `behavior_required` 标）；
- **白底格** = 选填；
- **灰底格 + 锁定** = 工具自动 / 不可改（代号列、高级数据列、示例行）。

---

## 二、前置依赖

| 依赖 | 要求 | 说明 |
|---|---|---|
| Python | 3.13（实测 3.13.1） | 只用标准库 + `openpyxl` |
| openpyxl | 3.1.5（实测） | 读写 `.xlsx`，缺了装：`pip install openpyxl` |
| Godot | 4.7.1 控制台版（`*_console.exe`） | **仅**「生成资源」「一键收尾」需要；路径用 `--godot` 或环境变量 `GODOT_BIN` / `GODOT` 传入 |
| git | 任意 | 「一键收尾」的漂移检查用 |
| GUT 插件 | `addons/gut/` | 「一键收尾」的全量门禁用 |

> 重建工作簿 / 读表校验 / 落盘空跑 / 两个自检**都不需要 Godot**。
>
> **中文乱码提醒**：Windows 控制台默认 GBK（代码页 936），中文/符号可能报 `UnicodeEncodeError` 或显示乱码。建议先设置：
> ```powershell
> $env:PYTHONUTF8 = '1'
> ```
> （或在 cmd 里先跑 `chcp 65001`。）

---

## 三、6 条命令（全部已实测）

> 记法：**① 重建 → ② 校验 → ③ 生成 → ④ 收尾**，⑤⑥ 是落盘的最后一步（空跑 / 真写）。

### ① 重建工作簿（Excel 工作簿 ← 现有 .tres）

**用途**：把 `content/gems/` 里现有的 80 个正式资源导出成中间 JSON，再整本重画出 `技能配置表.xlsx`。只在**首次建表**或**表结构变更**时跑。

```powershell
# 第 1 步：Godot 反导出为 _tmp/export.json
godot --headless --path . -s res://mods/jes-skills/tools/content_workbench/export/export_to_json.gd

# 第 2 步：依据 export.json 重建整本工作簿
python mods/jes-skills/tools/content_workbench/export/build_workbook.py
```

- **参数**：两个脚本都是**零入参**（`build_workbook.py` 不解析任何命令行参数，传 `--help` 它也只会照常建表）。
- **产物**：`_tmp/export.json`（中间 JSON）→ `content_src/技能配置表.xlsx`（整本工作簿）。
- **是否写盘**：**是**，会整体覆盖工作簿。
- ⚠️ **会覆盖策划已填的内容**。日常加技能 / 改数值**不要**跑这一条；只有在表结构（列、页签、词表）要变时才跑，且跑前先备份工作簿。

### ② 读表校验（工作簿 → 中间 JSON，带中文分层校验）

**用途**：把工作簿读回结构化 JSON，同时做全部中文校验。**改动内容后的第一件事就是跑它。**

```powershell
python mods/jes-skills/tools/content_workbench/build/read_workbook.py mods/jes-skills/content_src/技能配置表.xlsx
```

- **参数（实测 `--help`）**：

  | 参数 | 必填 | 说明 |
  |---|---|---|
  | `workbook` | ✅ 位置参数 | 中文 Excel 工作簿路径 |
  | `--schema` | 否 | 冻结契约 `schema.json`（只读），默认取工具目录下的那份 |
  | `--out` | 否 | 中间 JSON 输出，默认 `_tmp/build_input.json` |
  | `--errors` | 否 | 中文错误清单，默认 `_tmp/errors.json` |
  | `--snapshot` | 否 | 数值快照（只读），用于「数值是否超出运行时统计区间」的黄色提醒 |

- **产物**：`_tmp/build_input.json`（给 ③ 用）+ `_tmp/errors.json`（错误清单，成功时也写，内容为「零错误」）。
- **是否写盘**：**是**，但**只写 `_tmp/`**，绝不碰 `content/gems/`。
- **实测输出（通过）**：
  ```
  校验通过：67 个技能、95 个效果段、13 个辅助石，中间 JSON 已写入 .../_tmp/build_input.json
  ```
- **实测输出（不通过，退出码 1，且会清理旧的 `build_input.json`）**：
  ```
  校验未通过，共 1 处错误（未生成任何中间 JSON、未落盘，已清理旧中间 JSON）：
    ③ 效果段 第 10 行 · 形状：填了『方形』，只能选 点/圆/环/扇形/线/矩形/多点
  ```

### ③ 生成资源（中间 JSON → `.tres` 干跑）

**用途**：把 ② 产出的中间 JSON 生成成 80 个 `.tres`，**只写到 `_tmp/dryrun/`**，不碰正式内容。

```powershell
godot --headless --path . -s res://mods/jes-skills/tools/content_workbench/build/build_from_json.gd
```

- **参数**：默认零入参。需要改路径时用 `--` 之后的参数（res:// 形态）：
  ```powershell
  godot --headless --path . -s res://mods/jes-skills/tools/content_workbench/build/build_from_json.gd -- --input <res://…/x.json> --output <res://…/dryrun>
  ```
- **产物**：`_tmp/dryrun/*.tres`（80 个）。
- **是否写盘**：**是，但只写 `_tmp/dryrun/`**；绝不写 `content/gems/`。
- **特性**：事务式（先写暂存目录并逐条回读自查，全通过才整体替换）+ 幂等（同一输入跑两次产物逐字节一致）。

### ④ 一键收尾（刷新缓存 → 导出 → 校验 → 生成 → API 地图 → 数值快照 → 漂移检查 → 全量门禁 → 回写结果）

**用途**：一条命令串起全部 10 步 + 回写工作簿「⑥ 检查结果」。**收尾前跑它，确认全绿。**

```powershell
# 先空看命令序列（不需要 Godot，不执行任何命令）
python mods/jes-skills/tools/content_workbench/finish/run_all.py --dry-run

# 真跑
python mods/jes-skills/tools/content_workbench/finish/run_all.py --godot <Godot 控制台 exe 路径>
```

- **参数（实测 `--help`）**：

  | 参数 | 说明 |
  |---|---|
  | `--godot` | Godot 4.7.1 控制台可执行文件路径；也可设环境变量 `GODOT_BIN` / `GODOT`。**默认留空** |
  | `--project-root` | 项目根（含 `project.godot`），默认自动上溯定位 |
  | `--workbook` | 工作簿路径，默认取契约 `schema.json` 的 `workbook` 字段 |
  | `--result-json` | 结果 JSON 落点，默认 `finish/_tmp/last_result.json` |
  | `--rebuild-workbook` | 顺带执行 ① 的重建；**默认跳过**（避免覆盖策划已填内容） |
  | `--dry-run` | 只打印命令序列 + 依赖检查，不执行、不落盘 |
  | `--timeout` | 单条命令超时秒数，默认 900 |

- **执行顺序**：两次 `--import` 刷类缓存 → 导出 `export.json` →〔① 建表，默认跳过〕→ ② 读表校验 → ③ 生成 → `gen_api_map.gd` → `gen_content_snapshot.gd` → `git diff --exit-code content/`（漂移检查）→ GUT 全量门禁 → 回写「⑥ 检查结果」。
- **产物**：各步骤的中间产物 + `finish/_tmp/last_result.json` + `finish/_tmp/run_all_raw_output.txt` + 工作簿「⑥ 检查结果」。
- **是否写盘**：**是**——除「⑥ 检查结果」外不写正式内容；**不做真实落盘**（不写 `content/gems/`）。
- **any 一步失败即停**，不继续后续步骤，并把中文错误回写到「⑥ 检查结果」。
- **实测退出码**：`0` 全绿；`1` 有步骤失败；`2` 依赖缺失（等待交付）；`3` 找不到项目根 / 未提供 Godot。

### ⑤ 落盘 · 空跑（默认）

**用途**：把 `_tmp/dryrun` 的 80 个 `.tres` 与 `content/gems/` 现状**按字节比对**，只打印「新增 / 会改动 / 不变」三类清单。**一个字节都不写。**

```powershell
python mods/jes-skills/tools/content_workbench/finish/apply.py
```

- **参数（实测 `--help`）**：

  | 参数 | 说明 |
  |---|---|
  | `--project-root` | 项目根（含 `project.godot`）；默认从脚本位置向上自动定位 |
  | `--dryrun` | 生成目录，默认 `_tmp/dryrun` |
  | `--export` | 反向导出 JSON，默认 `_tmp/export.json` |
  | `--content` | 正式内容目录，默认 `mods/jes-skills/content/gems` |
  | `--apply` | **不加 = 空跑**（本模式）；加 = ⑥ 真实写盘 |

- **产物**：仅屏幕输出（`[新增]` / `[会改动]` / `[不变]` + 每项「旧字节 → 新字节」+ 汇总）。
- **是否写盘**：**否**（实测结尾固定打印「`[本次是否真实写盘] 否（空跑，一个字节都没写）`」）。
- **前置守卫**（任一不过即中文报错、退出 1、不创建任何文件）：dryrun 不是恰好 80 个 `.tres` / 缺 `export.json` / 文件名或代号非法 / 类别数量不是 67 主动 + 13 辅助 / 内容目录不存在 / 目标位置被目录占用 / 代号与文件名不一致。

### ⑥ 落盘 · 真写（`--apply`）

**用途**：真正把 80 个 `.tres` 写进 `content/gems/{active,supports}`。

```powershell
python mods/jes-skills/tools/content_workbench/finish/apply.py --apply
```

- **参数**：同 ⑤，只是多一个 `--apply`。
- **产物**：`content/gems/active/*.tres`（67 个）+ `content/gems/supports/*.tres`（13 个）。
- **是否写盘**：**是**（写正式内容目录，**唯一会改 `content/` 的命令**）。
- ⚠️ **务必先跑 ⑤ 空跑看清单，确认无误再 `--apply`。** 真实写盘需制作人拍板。
- **安全机制**：逐文件先写临时副本并校验、对已存在目标先备份、再原子替换；任一步失败**按逆序回滚**（已覆盖的恢复原样、本次新建的删除），不留半写状态。
- **只写 `.tres`**：`.gdkeep` 等非 `.tres` 文件一律不碰；正常写盘不删除任何既有文件。
- **写盘后**：需重生成 API 地图、重生成数值快照、跑 GUT 全量门禁——即再跑一次 ④「一键收尾」。本脚本不代劳。

---

## 四、自检命令（不需要 Godot）

| 命令 | 验什么 | 是否需要 Godot |
|---|---|---|
| `python mods/jes-skills/tools/content_workbench/export/selfcheck.py` | 工作簿 ← → `_tmp/export.json` 逐字段往返零差异、6 页签/中文列头/行数/代号唯一性/示例行锁定/下拉/批注 | 否（**零入参**，直接跑） |
| `python mods/jes-skills/tools/content_workbench/finish/apply_selfcheck.py` | 落盘工具：空跑零写入、`--apply` 正确落盘、幂等、中途失败回滚、7 类守卫拒绝 | 否（**零入参**；在系统临时目录造一次性假项目根，不碰真实 `content/`） |
| `python mods/jes-skills/tools/content_workbench/finish/selfcheck.py` | 一键收尾的编排逻辑（空跑命令序列 / 结果回写 / 依赖缺失 / 失败即停 / 错误行），**在隔离目录里造数，不打开真实工作簿、不落盘** | 否（**零入参**） |
| `python mods/jes-skills/tools/content_workbench/build/selfcheck.py [--godot <exe>]` | 读表 + 生成的整条链（含各种错表变体） | **需要** |

> `export/selfcheck.py` 依赖 `_tmp/export.json`——**若该文件不存在，先跑 ① 的导出步骤**。
> `export/selfcheck.py`、`finish/selfcheck.py`、`apply_selfcheck.py` 都没有参数解析器，传 `--help` 会直接开始执行。

---

## 五、常见报错怎么办

### 5.1 先看错误清单在哪

校验失败时，**结构化中文错误清单**固定写在这两个位置之一：

| 命令 | 错误清单位置 |
|---|---|
| ② 读表校验 | `_tmp/errors.json`（或 `--errors` 指定的路径） |
| ④ 一键收尾 | 屏幕中文清单 **+** 工作簿 **「⑥ 检查结果」**页签 |

`errors.json` 的字段：

```json
{
  "ok": false,
  "count": 1,
  "errors": [
    { "sheet": "③ 效果段", "row": 10, "col": "形状",
      "message": "填了『方形』，只能选 点/圆/环/扇形/线/矩形/多点",
      "text": "③ 效果段 第 10 行 · 形状：填了『方形』，只能选 点/圆/环/扇形/线/矩形/多点" }
  ],
  "warnings": [],
  "text": "…（同上，纯文本）"
}
```

### 5.2 怎么按「页签 + 行 + 列」定位

错误文案格式固定为：

```
<页签> 第 <行号> 行 · <列名>：<问题>
```

例：`③ 效果段 第 10 行 · 形状：填了『方形』，只能选 点/圆/环/扇形/线/矩形/多点`

定位步骤：

1. 打开「**③ 效果段**」页签；
2. 找到 **Excel 左端的第 10 行**（行号与错误里的「第 N 行」**完全一致**，含表头和示例行，不用自己换算）；
3. 找到列名「**形状**」那一列；
4. 按「只能选 …」里的候选，或按「怎么改」列的提示改；
5. 重跑 ② 读表校验。

### 5.3 中文错误速查表

| 你会看到 | 意思 | 怎么改 |
|---|---|---|
| `填了『X』，只能选 点/圆/环/扇形/线/矩形/多点` | 枚举列填了词表外的值 | 改填候选之一；别手打英文代号（下拉外填值多数会被拦） |
| `找不到原始记录` | 示例行/预留行被当成真实数据了 | 检查该行首列是否以 `【示例】` 开头；示例行不要删标记 |
| `不能作为资源文件名` | 代号不合法（须 `^[a-z][a-z0-9_]*$`） | 代号列是自动的，一般不用填；新行留空让工具生成 |
| `重复` | 代号重复 | 两个技能/辅助石用了同一个代号，改其一 |
| `超出…` / `未填任何尺寸参数` | **黄色提醒**，不是错误 | 只提醒，不拦截；确认数值合理即可 |
| `③ 效果段 第 N 行 · 半径：… 点爆豁免` | `范围爆发` + 非点形状，却没有任何尺寸 | 补「半径 / 长度 / 宽度」之一（形状=点时豁免） |
| `校验未通过，共 N 处错误` | 有错，**未生成**中间 JSON | 按上面逐条改；注意旧的 `build_input.json` 已被清理 |
| `dryrun 目录不存在：…（请先跑 W3 正向生成）` | 落盘前还没生成 | 先跑 ③ 生成资源 |
| `文件数 = N，期望 80` | dryrun 不是 80 个 `.tres` | dryrun 混入了别的文件，或上次生成没跑完 |
| `类别数量…不是 67 主动 + 13 辅助` | 归属数量对不上 | 检查 `export.json` 是否过期 → 重跑 ① 的导出 |
| `缺 export.json` | 没跑过反导出 | 先跑 ① 的导出步骤 |
| `未提供 Godot 可执行文件` | 一键收尾没拿到 Godot 路径 | 加 `--godot <exe>` 或设 `GODOT_BIN` |
| `找不到项目根` | 没在项目根执行，或 `project.godot` 不存在 | 回到项目根，或加 `--project-root` |
| `等待 W2/W3 交付：…缺失` | 依赖脚本缺失 | 确认工具目录完整（别单独拷某个脚本） |
| `content/ 存在漂移` / `git diff --exit-code` 红 | 正式资源与生成结果不一致（有人手改了 `.tres`） | `git diff mods/jes-skills/content/` 看差异，确认无误后重跑 |
| `UnicodeEncodeError: 'gbk' codec…` | 控制台编码问题 | `$env:PYTHONUTF8 = '1'` 或 `chcp 65001` |
| `ModuleNotFoundError: No module named 'openpyxl'` | 没装依赖 | `pip install openpyxl` |
| `表结构/列头与契约不一致` | 工作簿被手工改过表头/删过列 | 重跑 ① 重建（**会覆盖内容，先备份**），或还原工作簿 |
| `预留行不符合契约` | 表结构（预留行/批注/锁定）被改动 | 同上；或用 `export/selfcheck.py` 的详细输出逐条核对 |

---

## 六、文件分布与「谁可以改」

```
mods/jes-skills/
├─ content/gems/                      ← 正式资源（生成物，勿手改）
│  ├─ active/*.tres                     67 个主动技能
│  └─ supports/*.tres                   13 个辅助石
├─ content_src/技能配置表.xlsx        ← ★ 唯一真源（策划只改这里）
└─ tools/content_workbench/           ← 本工具
   ├─ README.md                         ← 本文件
   ├─ schema.json                       ← ★ 冻结契约（勿改）
   ├─ export/
   │  ├─ export_to_json.gd              ① 反导出 .tres → JSON
   │  ├─ build_workbook.py              ① 重建工作簿
   │  └─ selfcheck.py                   自检：往返零差异（需 _tmp/export.json）
   ├─ build/
   │  ├─ read_workbook.py               ② 读表校验
   │  ├─ build_from_json.gd             ③ 生成 .tres（干跑）
   │  └─ selfcheck.py                   自检：读表 + 生成全链（需 Godot）
   ├─ finish/
   │  ├─ run_all.py                     ④ 一键收尾
   │  ├─ report.py                      ④ 子步骤：结果回写「⑥ 检查结果」
   │  ├─ apply.py                       ⑤⑥ 落盘（空跑 / --apply）
   │  ├─ selfcheck.py                   自检：一键收尾编排
   │  └─ apply_selfcheck.py             自检：落盘工具（假项目根，不碰真实 content/）
   ├─ _probe/                           一次性探针（勿依赖）
   └─ _tmp/                             ← 中间产物，全部不入库
      ├─ export.json                     ① 产物
      ├─ build_input.json                ② 产物（③ 的输入）
      ├─ errors.json                     ② 错误清单
      ├─ dryrun/*.tres                   ③ 产物（⑤⑥ 的输入）
      └─ selfcheck/                      自检产物
```

### 「谁可以改」规则

| 对象 | 规则 |
|---|---|
| `content_src/技能配置表.xlsx` | ✅ **只有它可以改**（策划填表）。改表结构 / 重跑 ① 会整本覆盖，先备份 |
| `schema.json` | 🔒 **冻结**。表结构、词表、必填、下拉的唯一真源。要改必须由上级 AI 统一改并通知全员，其他人**只读** |
| `content/gems/**/*.tres` | 🚫 **生成物，勿手改**。手改会被下一次落盘覆盖，且触发漂移检查 |
| `_tmp/` | 🚫 **不入库**，随时可删可重生成。不要把它当交付物，也不要把文件散放进来 |
| `.py` / `.gd` 工具本体 | 按归属改；改完必须跑对应的 `selfcheck.py` |
| `__pycache__/` | 运行 Python 自动产生，**不入库，可随时删** |

> **_tmp 不入库**：`.gitignore` 已覆盖 `_tmp/`、`__pycache__/`、`*.pyc`。
> 但 `content_src/`（含唯一真源工作簿）与 `tools/content_workbench/`（含 `schema.json` 与工具脚本）目前**未被忽略**，属正常——它们应当入库。

---

## 七、推荐工作流

```
改表（只动 技能配置表.xlsx）
   ↓
② 读表校验 ──✗──→ 看 _tmp/errors.json → 按「页签+行+列」改表 → 重跑
   ↓ ✓
③ 生成资源（只写 _tmp/dryrun）
   ↓
⑤ 落盘空跑 ──→ 看「新增 / 会改动 / 不变」清单
   ↓ 人工确认（制作人拍板）
⑥ 落盘真写 --apply
   ↓
④ 一键收尾（重生成 API 地图 / 数值快照 + 漂移检查 + GUT 全量门禁）
```

> 表结构要变（加列 / 改词表 / 改必填）时，才走 ①：先备份工作簿 → 改 `schema.json`（由上级 AI 改）→ 重建。
