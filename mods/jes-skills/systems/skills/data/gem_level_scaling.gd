# GemLevelScaling（规格 §3.1）
# 等级缩放：base × (1 + scaling_per_level × (level - 1))
class_name GemLevelScaling
extends Resource

## 每级成长率（0.1 = 每级 +10% 基础值）
@export var per_level: float = 0.0


func factor_for(level: int) -> float:
	return 1.0 + per_level * float(maxi(level - 1, 0))
