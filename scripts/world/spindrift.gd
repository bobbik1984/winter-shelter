class_name Spindrift
extends GPUParticles3D

## 贴地吹雪（T3.1 / Read the Land 第 1 条）：跟随玩家的低空雪尘流，沿下风方向贴着雪面飞掠。
## 暴露越高越密（GameDirector 写入 intensity = 暴露度），躲进背风处 / 林子里明显变少。

var follow: Node3D
var intensity: float = 0.5

func _ready() -> void:
	amount = 500
	lifetime = 1.8
	preprocess = 1.0
	local_coords = false
	visibility_aabb = AABB(Vector3(-25, -6, -25), Vector3(50, 12, 50))
	var wind := load("res://resources/default_wind.tres") as WindData
	var blow := wind.get_blow_direction_3d() if wind else Vector3.RIGHT
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(18, 0.35, 18)
	pm.direction = Vector3(blow.x, 0.05, blow.z)
	pm.spread = 6.0
	pm.initial_velocity_min = 6.0
	pm.initial_velocity_max = 11.0
	pm.gravity = Vector3(0, -0.4, 0)
	pm.scale_min = 0.7
	pm.scale_max = 1.6
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0))
	fade.add_point(0.2, Color(1, 1, 1, 1))
	fade.add_point(0.8, Color(1, 1, 1, 1))
	fade.set_color(fade.get_point_count() - 1, Color(1, 1, 1, 0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	pm.color_ramp = ramp
	process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.55, 0.035)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.albedo_color = Color(0.92, 0.95, 1.0, 0.45)
	q.material = m
	draw_pass_1 = q
	# 启动守卫：等窗口 swapchain 重建后再开始发射（GameDirector 在第 30 帧统一打开）
	emitting = false
	add_to_group("deferred_particles")

func _process(_delta: float) -> void:
	if follow:
		var p := follow.global_position
		global_position = Vector3(p.x, SnowField.height_at(p.x, p.z) + 0.35, p.z)
	amount_ratio = clampf(0.15 + intensity * 0.85, 0.0, 1.0)
