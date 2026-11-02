class_name PlayerController
extends CharacterBody3D

## 玩家移动与探针（T1.4 / T1.6）。
## 移动：相机相对方向；速度 = Tuning 基础速度 × 上坡衰减 × 深雪衰减（GameRules.move_speed）。
## 探针：按住 probe 键 Tuning.probe_seconds 秒（站定、下蹲代理动作），读数来自 SnowField 深度场。

signal probe_activated(pos: Vector3, depth: float)
signal probe_progress(ratio: float)

@export var rotation_speed: float = 12.0
@export var gravity: float = 20.0

@onready var visual_node: Node3D = $Visual

var tuning: Tuning
## 由 GameDirector 控制：简报 / 建造确认 / 结算时禁止移动。
var controls_enabled: bool = true
var is_probing: bool = false
## 由 GameDirector 写入：正在按住交互（施工 / 采集）时播放劳作动画。
var working: bool = false
## 劳作动画："Dig"（挖雪 / 施工 / 采集）或 "Chop"（砍柴）。
var work_anim: String = "Dig"
var current_speed: float = 0.0
var _probe_t: float = 0.0

func _ready() -> void:
	tuning = load("res://resources/tuning.tres") as Tuning

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0

	if not controls_enabled:
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()
		if working and visual_node and visual_node.has_method("set_motion"):
			visual_node.set_motion(0.0, false, true, work_anim)
		return

	# 探针：按住推进；松开取消
	HoldAssist.cancel_if_moving()
	if HoldAssist.held("probe"):
		_probe_t += delta
		is_probing = true
		probe_progress.emit(clampf(_probe_t / tuning.probe_seconds, 0.0, 1.0))
		if _probe_t >= tuning.probe_seconds:
			_probe_t = -INF   # 本次按住只读一次
			HoldAssist.release("probe")
			_finish_probe()
		if visual_node and visual_node.has_method("set_motion"):
			visual_node.set_motion(0.0, true, false)
		velocity.x = move_toward(velocity.x, 0, 20.0 * delta)
		velocity.z = move_toward(velocity.z, 0, 20.0 * delta)
		move_and_slide()
		return
	if is_probing:
		is_probing = false
		_probe_t = 0.0
		probe_progress.emit(0.0)

	var input_dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	# 屏幕上下左右 → 世界方向：按当前相机的偏航角旋转（不写死 45°）
	var raw_dir := Vector3(input_dir.x, 0.0, input_dir.y)
	var dir := raw_dir.rotated(Vector3.UP, _camera_yaw()).normalized()

	if dir.length() > 0.1:
		var p := global_position
		var ahead := p + dir * 0.6
		var rise := SnowField.height_at(ahead.x, ahead.z) - SnowField.height_at(p.x, p.z)
		var uphill := rad_to_deg(atan(maxf(rise, 0.0) / 0.6))
		current_speed = GameRules.move_speed(tuning.move_speed_mps, uphill, SnowField.snow_at(p.x, p.z), tuning)
		velocity.x = dir.x * current_speed
		velocity.z = dir.z * current_speed
		if visual_node:
			var target_rot = atan2(dir.x, dir.z)
			visual_node.rotation.y = lerp_angle(visual_node.rotation.y, target_rot, rotation_speed * delta)
	else:
		current_speed = 0.0
		velocity.x = move_toward(velocity.x, 0, 30.0 * delta)
		velocity.z = move_toward(velocity.z, 0, 30.0 * delta)

	move_and_slide()
	if visual_node and visual_node.has_method("set_motion"):
		visual_node.set_motion(current_speed, false, working, work_anim)
	# 地图边界（山谷外是远景，不可行走）
	global_position.x = clampf(global_position.x, -48.5, 48.5)
	global_position.z = clampf(global_position.z, -48.5, 48.5)

func facing() -> Vector3:
	var yaw := visual_node.rotation.y if visual_node else 0.0
	return Vector3(sin(yaw), 0, cos(yaw))

func _camera_yaw() -> float:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return deg_to_rad(45.0)
	var fwd := -cam.global_transform.basis.z
	return atan2(-fwd.x, -fwd.z)

func _finish_probe() -> void:
	var p := global_position + facing() * 0.6
	var depth := SnowField.snow_at(p.x, p.z)
	probe_activated.emit(Vector3(p.x, SnowField.height_at(p.x, p.z), p.z), depth)
