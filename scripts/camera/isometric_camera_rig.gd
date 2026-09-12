class_name IsometricCameraRig
extends Node3D

@export var target: Node3D
@export var follow_speed: float = 6.0
@export var camera_size: float = 18.0
@export var camera_pitch_degrees: float = -38.0
@export var camera_yaw_degrees: float = 45.0

@onready var camera_3d: Camera3D = $Camera3D

func _ready() -> void:
	# 设置固定正交等距角
	rotation_degrees = Vector3(camera_pitch_degrees, camera_yaw_degrees, 0.0)
	if camera_3d:
		camera_3d.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera_3d.size = camera_size

func _process(delta: float) -> void:
	if is_instance_valid(target):
		global_position = global_position.lerp(target.global_position, follow_speed * delta)
