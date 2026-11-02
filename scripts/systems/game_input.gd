class_name GameInput
extends RefCounted

## 输入辅助（键盘为主）：
## * ensure_joypad()：把手柄左摇杆 / A / X 写进 InputMap（移动、交互、探针）。
## * joy_to_key()：其余手柄键按当前情境转成等价键盘键，交给 GameDirector 的键盘处理逻辑。

## 手柄：左摇杆移动、A 交互、X 探针（写进 InputMap）；其余按键转成等价键盘键处理。
static func ensure_joypad() -> void:
	var axes := {"move_left": [JOY_AXIS_LEFT_X, -1.0], "move_right": [JOY_AXIS_LEFT_X, 1.0],
		"move_up": [JOY_AXIS_LEFT_Y, -1.0], "move_down": [JOY_AXIS_LEFT_Y, 1.0]}
	for action in axes:
		if InputMap.has_action(action):
			var e := InputEventJoypadMotion.new()
			e.axis = axes[action][0]
			e.axis_value = axes[action][1]
			# InputMap 跨场景重载保留：已绑定就不再重复添加（R 重开会再次调用）
			if not InputMap.action_has_event(action, e):
				InputMap.action_add_event(action, e)
	for pair in [["interact", JOY_BUTTON_A], ["probe", JOY_BUTTON_X]]:
		if InputMap.has_action(pair[0]):
			var b := InputEventJoypadButton.new()
			b.button_index = pair[1]
			if not InputMap.action_has_event(pair[0], b):
				InputMap.action_add_event(pair[0], b)

## state: GameDirector.State；building: 是否在建造模式。
static func joy_to_key(btn: JoyButton, state: int, building: bool) -> Key:
	match btn:
		JOY_BUTTON_START:
			match state:
				GameDirector.State.BRIEFING: return KEY_ENTER
				GameDirector.State.REPORT: return KEY_R
				_: return KEY_ESCAPE
		JOY_BUTTON_BACK: return KEY_I if state == GameDirector.State.BRIEFING else KEY_H
		JOY_BUTTON_Y:
			if state == GameDirector.State.BRIEFING: return KEY_N
			return KEY_R if state == GameDirector.State.PAUSED else KEY_B
		JOY_BUTTON_B: return KEY_B if building else (KEY_ESCAPE if state == GameDirector.State.PAUSED else KEY_F)
		JOY_BUTTON_LEFT_SHOULDER:
			if state == GameDirector.State.BRIEFING: return KEY_LEFT
			return KEY_R if building else KEY_NONE
		JOY_BUTTON_RIGHT_SHOULDER:
			if state == GameDirector.State.BRIEFING: return KEY_RIGHT
			if state == GameDirector.State.REPORT: return KEY_ENTER
			return KEY_TAB if building or state == GameDirector.State.PLAYING else KEY_NONE   # 情报面板开着时翻页
		JOY_BUTTON_DPAD_UP: return KEY_UP if state == GameDirector.State.BRIEFING else KEY_T
		JOY_BUTTON_DPAD_DOWN: return KEY_DOWN if state == GameDirector.State.BRIEFING else KEY_2
		JOY_BUTTON_DPAD_RIGHT: return KEY_N
		JOY_BUTTON_DPAD_LEFT: return KEY_L
	return KEY_NONE
