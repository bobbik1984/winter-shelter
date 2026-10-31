class_name Interactable
extends Node3D

## 统一交互组件（T2.1）：任何可交互物（立枯木、桦树、干草、庇护所工地、篝火…）都通过它接入。
## 玩家走近时由 InteractionController 选中最近的一个，按住交互键 hold_seconds 秒后调用 handler。
## handler: Callable() -> Dictionary  返回 {"msg": String, "minutes": float(消耗的游戏分钟), "ok": bool}
## prompt_fn（可选）: Callable() -> String  动态提示；为空字符串表示当前不可交互。

@export var kind: String = ""
@export var prompt: String = "Interact"
@export var hold_seconds: float = 1.35
## 剩余可用次数，-1 = 无限。
@export var uses_left: int = -1
## 高亮圈半径（m）。
@export var ring_radius: float = 0.9

var handler: Callable
var prompt_fn: Callable
var enabled: bool = true

func _ready() -> void:
	add_to_group("interactables")

func current_prompt() -> String:
	if not enabled or uses_left == 0:
		return ""
	if prompt_fn.is_valid():
		return String(prompt_fn.call())
	return prompt

func trigger() -> Dictionary:
	if not handler.is_valid():
		return {"ok": false, "msg": ""}
	var result: Dictionary = handler.call()
	if bool(result.get("ok", true)) and uses_left > 0:
		uses_left -= 1
	return result
