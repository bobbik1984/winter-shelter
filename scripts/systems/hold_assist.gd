class_name HoldAssist
extends RefCounted

## 无障碍：按住辅助（F9 开关，存 user://settings.cfg）。
## 开启后"按住"类动作（探针 / 交互 / 生火）轻点一次即开始并自动进行，移动或再按一次取消。

const PATH := "user://settings.cfg"
static var enabled := false
static var _loaded := false
## 当前锁存中的动作名（"probe" / "interact" / "fire"），空 = 无。
static var latched := ""
## 触屏的"生火"按钮按住时为 true（触屏按键不经过 Input 的键盘状态）。
static var touch_fire := false

static func load_setting() -> void:
	if _loaded:
		return
	_loaded = true
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		enabled = bool(cfg.get_value("ui", "hold_assist", false))

static func toggle() -> bool:
	enabled = not enabled
	latched = ""
	var cfg := ConfigFile.new()
	cfg.load(PATH)
	cfg.set_value("ui", "hold_assist", enabled)
	cfg.save(PATH)
	return enabled

## 动作是否处于"按住"状态（真实按住，或辅助模式下已锁存）。
static func held(action: String) -> bool:
	if action == "fire":
		if touch_fire or Input.is_key_pressed(KEY_F) or Input.is_joy_button_pressed(0, JOY_BUTTON_B):
			return true
	elif Input.is_action_pressed(action):
		return true
	return enabled and latched == action

## 在辅助模式下处理按下：同一动作再按一次 = 取消，否则锁存。
static func on_pressed(action: String) -> void:
	if not enabled:
		return
	latched = "" if latched == action else action

static func release(action: String) -> void:
	if latched == action:
		latched = ""

## 玩家在移动 → 取消锁存（避免边走边自动干活）。
static func cancel_if_moving() -> void:
	if latched != "" and Input.get_vector("move_left", "move_right", "move_up", "move_down").length() > 0.2:
		latched = ""
