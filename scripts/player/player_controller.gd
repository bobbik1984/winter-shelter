class_name PlayerController
extends CharacterBody3D

signal probe_activated(pos: Vector3, depth: float)

@export var move_speed: float = 4.5
@export var rotation_speed: float = 12.0
@export var gravity: float = 20.0

@onready var probe_ray: RayCast3D = $AvalancheProbe
@onready var visual_node: Node3D = $Visual

var is_probing: bool = false

func _physics_process(delta: float) -> void:
	# 重力应用
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0

	# 探雪动作执行中禁止移动
	if is_probing:
		velocity.x = move_toward(velocity.x, 0, move_speed * delta * 5.0)
		velocity.z = move_toward(velocity.z, 0, move_speed * delta * 5.0)
		move_and_slide()
		return

	# 输入检测
	var input_dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	
	# 屏幕上下左右 → 世界方向：按当前相机的偏航角旋转（不再写死 45°）
	var raw_dir := Vector3(input_dir.x, 0.0, input_dir.y)
	var iso_dir := raw_dir.rotated(Vector3.UP, _camera_yaw()).normalized()

	if iso_dir.length() > 0.1:
		velocity.x = iso_dir.x * move_speed
		velocity.z = iso_dir.z * move_speed
		
		# 朝向平滑转向
		if visual_node:
			var target_rot = atan2(iso_dir.x, iso_dir.z)
			visual_node.rotation.y = lerp_angle(visual_node.rotation.y, target_rot, rotation_speed * delta)
	else:
		velocity.x = move_toward(velocity.x, 0, move_speed)
		velocity.z = move_toward(velocity.z, 0, move_speed)

	move_and_slide()

	# 探针检测触发
	if Input.is_action_just_pressed("probe"):
		perform_probe()

func _camera_yaw() -> float:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return deg_to_rad(45.0)
	var fwd := -cam.global_transform.basis.z
	return atan2(-fwd.x, -fwd.z)

func perform_probe() -> void:
	is_probing = true
	
	# 简单延时模拟扎雪动作
	await get_tree().create_timer(0.35).timeout
	
	if probe_ray and probe_ray.is_colliding():
		var hit_pos = probe_ray.get_collision_point()
		var collider = probe_ray.get_collider()
		var depth: float = 0.8
		if collider and collider.has_meta("snow_depth"):
			depth = float(collider.get_meta("snow_depth"))
		probe_activated.emit(hit_pos, depth)
	
	is_probing = false
