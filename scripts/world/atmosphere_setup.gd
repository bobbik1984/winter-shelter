extends WorldEnvironment

## M1->M2 大气与夕阳光照（主创定标版）：
## 对齐 VISUAL_LANGUAGE.md：低角度暖金夕阳（俯角 -24°）+ 钴蓝高空环境光 + 远景暖雾。

func _ready() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY

	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.14, 0.26, 0.50)
	sky_mat.sky_horizon_color = Color(0.94, 0.72, 0.52)
	sky_mat.sky_curve = 0.16
	sky_mat.ground_bottom_color = Color(0.20, 0.28, 0.42)
	sky_mat.ground_horizon_color = Color(0.76, 0.66, 0.58)
	sky_mat.ground_curve = 0.10
	sky_mat.sun_angle_max = 22.0
	sky_mat.sun_curve = 0.10
	sky.sky_material = sky_mat
	env.sky = sky

	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 0.62
	env.ambient_light_color = Color(0.38, 0.52, 0.78)
	env.ambient_light_energy = 0.55

	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 0.58
	env.tonemap_white = 4.5

	env.fog_enabled = true
	env.fog_light_color = Color(0.72, 0.76, 0.86)
	env.fog_light_energy = 0.65
	env.fog_density = 0.0028
	env.fog_aerial_perspective = 0.70
	env.fog_sky_affect = 0.40

	environment = env

	var sun := get_parent().get_node_or_null("SunLight") as DirectionalLight3D
	if sun:
		# 低角度西北偏西落日：拉出斜向长树影，同时避免脊线正顶面垂直过曝
		sun.rotation_degrees = Vector3(-24.0, -42.0, 0.0)
		sun.light_color = Color(1.0, 0.78, 0.54)
		sun.light_energy = 0.90
		sun.shadow_enabled = true
		sun.directional_shadow_max_distance = 110.0
		sun.shadow_blur = 1.35
