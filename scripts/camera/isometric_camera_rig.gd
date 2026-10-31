class_name IsometricCameraRig
extends Node3D

## 相机沿 rig 本地 +Z 的后移距离（米）。
## [TUNE] 40.0 是当前 blockout 的视感值；后续由 T0.5 / T1.3 迁入 tuning。
@export var camera_distance: float = 40.0
## 正交视口高度（米）。
## [TUNE] 18.0 与 ARCHITECTURE_GODOT.md §3.1 一致；后续由 T0.5 / T1.3 迁入 tuning。
@export var camera_size: float = 18.0
## 俯仰角（度）。-38° 为当前仓库既有值，保持到 T1.3 再定稿。
@export var camera_pitch_degrees: float = -38.0
## 偏航角（度）。45° 为工程红线固定值。
@export var camera_yaw_degrees: float = 45.0
@export var target: Node3D
@export var follow_speed: float = 6.0

@onready var camera_3d: Camera3D = $Camera3D

func _ready() -> void:
	# 固定 ISO 机位角度：Yaw 45°、Pitch -38°（真等距 -35.264° 的视感微调区间）
	rotation_degrees = Vector3(camera_pitch_degrees, camera_yaw_degrees, 0.0)
	if camera_3d:
		camera_3d.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera_3d.size = camera_size
		# 沿 rig 本地 +Z 后移，让 rig 原点（target 跟随点）落在正交画面中心
		camera_3d.position = Vector3(0.0, 0.0, camera_distance)
		# [GAME] 裁剪面：near 0.05 避免贴近物被切；far 200 覆盖 100 m 地图最远角（最坏约 175 m）
		camera_3d.near = 0.05
		camera_3d.far = 200.0

func _process(delta: float) -> void:
	if is_instance_valid(target):
		global_position = global_position.lerp(target.global_position, follow_speed * delta)
