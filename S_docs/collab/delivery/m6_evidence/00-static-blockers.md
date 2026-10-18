# T-078 静态阻塞定位（非运行凭据）

来源：本轮通过 Read 读取的当前源码。以下为源码摘录，不是执行输出；一基行号用于定位。未运行任何引擎命令，未查询进程。

## B-01 正式入口没有目标名单或实际结算宿主输入

`skill_core/api/skill_api.gd:126–133`：

```gdscript
	var _unsupported_part: Callable = func(_part: Dictionary, _record: Dictionary, _target: Dictionary) -> bool:
		return false
	var handlers: Dictionary = {}
	for kind in part_types:
		if not kind is String or kind.is_empty():
			return failure.call("handlers", "Invalid registered part type")
		handlers[kind] = _unsupported_part
```

`skill_core/api/skill_api.gd:149–154`：

```gdscript
	# No host roster or derivation routing is exposed by the frozen signature.
	# Empty targets is an explicit lifecycle sandbox; unresolved routes fail in start.
	var options: Dictionary = {"seed": seed, "roots": roots, "handlers": handlers,
		"template_families": families, "derivation_bindings": {}, "targets": []}
	var runner: RefCounted = RunnerScript.new()
	var started: Dictionary = runner.start(cfg, options)
```

`skill_core/runtime/preview_runner.gd:444–446,460–468`：

```gdscript
			var roster: Array = []
			var contacts: Dictionary = {}
			for target in _targets:
```

```gdscript
					roster.append(target)
					contacts[target["target_id"]] = candidate
			var result: Dictionary = entity["settle"].step(roster, {"position": motion.position, "direction": motion.direction})
			if not result["ok"]:
				last_error = result["error"]
				return false
			for record in result["records"]:
				_records.append(record.duplicate(true))
				if not _budget.record_settlement(record):
```

### 推论及边界

T-078 要求同一真实卡、固定同一初态/输入/种子、三栏分别非空、正式/预览首差异为空。当前正式 API 构造的是无目标生命周期沙盒，不能由测试调用者传入目标名册或真实 handler。T-077 回执 §2.6 也明确不声称完成命中结算。

直接预览可以独立传非空 targets 与真实 handler，但这样两入口初态不同，不能拿它与正式空名册比较并要求相等。将正式 sim 内部 runner 重启/私改其状态、人工向 records 填记录或把事件当结算，都不是要求的正式入口复现，不采用。

没有实际运行，因此**不报告实测 records 条数或具体错误包**。这是入口能力不足的静态定位，而非新红灯日志。发现该缺口后按派单立即停手，不修改 core，不新增已知无法满足硬验收的 GUT 测试。

## B-02 编辑器门面的其他入口仍是桩（补充，不替代 B-01）

`skill_core/api/skill_api.gd:16–21`：

```gdscript
func load_cfg(path: String) -> Dictionary:
	return _not_implemented("load_cfg", path)

# 职责：校验并保存技能 CFG；参数：path 为目标路径、cfg 为定义；返回：统一结果包；对应真源：第 16.1、14 章。
func save_cfg(path: String, cfg: Dictionary) -> Dictionary:
	return _not_implemented("save_cfg", path)
```

`skill_core/api/skill_api.gd:44–45`：

```gdscript
func validate(cfg: Dictionary, stage: StringName = STAGE_SAVE) -> Dictionary:
	return _not_implemented("validate", String(stage))
```

T-077 的测试直接调用 CfgCodec.save_cfg/load_cfg，这可以提供真实磁盘往返，但不能被改称 SkillApi 保存/加载已实现，也不证明实际编辑器全流程。即使沿用其底层 codec 路径，B-01 仍成立。

## 恢复所需（推荐方案，尚未批准）

1. 审核方另派 core/API 扩权卡，或指出现有正式宿主入口及契约，使正式与预览都能接受同一非空目标名单、固定初态/输入与真实结算适配器；全类型 handler 预检仍须满足，未实现类型仍显式拒绝。
2. 冻结运行态输入与 CFG 分离方式；不塞未知 params 键绕过 U-32，不把 runtime 状态回写 CFG，不私改 API 冻结签名。
3. 恢复 T-078 后逐例新增集成测试，保留 block=0、深比较、具体版本、三栏分别非空、双入口/重跑差分与破坏对照全部要求。
4. 审核方串行执行并回传实际输出，本卡逐步存档与绑定指纹。禁引擎期间不能由执笔方生成实际运行凭据。

不建议降级验收为无目标生命周期相等，那只是重复 T-077 局部证据，与 U-28 不降级口径冲突。
