extends GPUParticles3D

## M1 最低限度的风吹雪流线：西北 -> 东南，跟随场景的大范围发射盒。
## 不依赖贴图；用细长 billboard quad 表示雪粒流线。

func _ready() -> void:
	amount = 320
	lifetime = 3.2
	preprocess = 2.0
	local_coords = false
	visibility_aabb = AABB(Vector3(-70.0, -20.0, -70.0), Vector3(140.0, 60.0, 140.0))
	# 启动守卫：等窗口 swapchain 重建后再开始发射（GameDirector 在第 30 帧统一打开）
	emitting = false
	add_to_group("deferred_particles")

	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(38.0, 12.0, 38.0)
	var wind := load("res://resources/default_wind.tres") as WindData
	var blow := wind.get_blow_direction_3d() if wind else Vector3.RIGHT
	process.direction = Vector3(blow.x, -0.08, blow.z + 0.18)
	process.spread = 9.0
	process.initial_velocity_min = 8.0
	process.initial_velocity_max = 14.0
	process.gravity = Vector3(0.0, -0.55, 0.0)
	process.scale_min = 0.45
	process.scale_max = 1.25
	process.color = Color(0.82, 0.90, 1.0, 0.55)
	process_material = process

	var quad := QuadMesh.new()
	quad.size = Vector2(0.32, 0.025)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.albedo_color = Color(0.82, 0.90, 1.0, 0.55)
	mat.vertex_color_use_as_albedo = true
	quad.material = mat
	draw_pass_1 = quad
