extends WorldEnvironment

## M1 大气：低角度暖金夕阳 + 冷蓝天光 + 远景雾。
## 挂在 main.tscn 的 WorldEnvironment 上，运行时替换占位 Environment。

func _ready() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY

	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.10, 0.20, 0.42)
	sky_mat.sky_horizon_color = Color(0.92, 0.68, 0.50)
	sky_mat.sky_curve = 0.18
	sky_mat.ground_bottom_color = Color(0.18, 0.24, 0.36)
	sky_mat.ground_horizon_color = Color(0.72, 0.62, 0.58)
	sky_mat.ground_curve = 0.10
	sky_mat.sun_angle_max = 18.0
	sky_mat.sun_curve = 0.12
	sky.sky_material = sky_mat
	env.sky = sky

	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 0.70
	env.ambient_light_color = Color(0.42, 0.56, 0.78)
	env.ambient_light_energy = 0.55

	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 0.72

	env.fog_enabled = true
	env.fog_light_color = Color(0.58, 0.68, 0.84)
	env.fog_light_energy = 0.55
	env.fog_density = 0.003
	env.fog_aerial_perspective = 0.65
	env.fog_sky_affect = 0.45

	environment = env

	var sun := get_parent().get_node_or_null("SunLight") as DirectionalLight3D
	if sun:
		sun.rotation_degrees = Vector3(-74.0, -35.0, 0.0)
		sun.light_color = Color(1.0, 0.72, 0.46)
		sun.light_energy = 1.45
		sun.shadow_enabled = true
		sun.directional_shadow_max_distance = 120.0
		sun.shadow_blur = 1.5
