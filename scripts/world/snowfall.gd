class_name Snowfall
extends GPUParticles3D

## 傍晚降雪（T3.1 一部分）：跟随玩家的雪花场，16:00 后逐渐变密，随风向下风飘。
## 强度由 GameDirector 按时间写入 intensity（0..1）。

var follow: Node3D
var intensity: float = 0.0

func _ready() -> void:
	amount = 900
	lifetime = 6.0
	preprocess = 3.0
	local_coords = false
	visibility_aabb = AABB(Vector3(-30, -20, -30), Vector3(60, 40, 60))
	var wind := load("res://resources/default_wind.tres") as WindData
	var blow := wind.get_blow_direction_3d() if wind else Vector3.RIGHT
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(22, 1, 22)
	pm.direction = Vector3(blow.x * 0.6, -1.0, blow.z * 0.6)
	pm.spread = 12.0
	pm.initial_velocity_min = 1.2
	pm.initial_velocity_max = 2.4
	pm.gravity = Vector3(blow.x * 0.8, -0.6, blow.z * 0.8)
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.6
	pm.scale_min = 0.6
	pm.scale_max = 1.4
	process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.06, 0.06)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.92, 0.95, 1.0, 0.85)
	q.material = m
	draw_pass_1 = q
	amount_ratio = 0.0
	# 启动守卫：等窗口 swapchain 重建后再开始发射（GameDirector 在第 30 帧统一打开）
	emitting = false
	add_to_group("deferred_particles")

func _process(_delta: float) -> void:
	if follow:
		global_position = follow.global_position + Vector3(0, 12, 0)
	amount_ratio = clampf(intensity, 0.0, 1.0)
