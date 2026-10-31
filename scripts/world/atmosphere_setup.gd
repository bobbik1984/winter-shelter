extends WorldEnvironment

## M1->M2 大气与夕阳光照（主创定标版）：
## 对齐 VISUAL_LANGUAGE.md：低角度暖金夕阳（俯角 -24°）+ 钴蓝高空环境光 + 远景暖雾。

const SKY_SHADER := preload("res://shaders/sky_backdrop.gdshader")

var _sky_mat: ShaderMaterial

## "sun_receivers" 组回调：天空 shader 的太阳方向 + 随日高变化的环境光 / 雾。
func set_sun_dir(dir: Vector3) -> void:
	if _sky_mat:
		_sky_mat.set_shader_parameter("sun_dir", dir)
	if environment:
		var day := smoothstep(-0.10, 0.12, dir.y)
		environment.ambient_light_energy = lerpf(0.18, 0.75, day)
		environment.fog_light_energy = lerpf(0.12, 0.75, day)
		environment.fog_sun_scatter = 0.25 * day

## "lens_receivers" 组回调：移轴镜头参数（见 sky_backdrop.gdshader 的说明）。
func set_lens(enabled: bool, half_t: float, aspect: float, shift_t: float, basis: Basis) -> void:
	if _sky_mat == null:
		return
	_sky_mat.set_shader_parameter("lens_fix", 1.0 if enabled else 0.0)
	_sky_mat.set_shader_parameter("lens_half_t", half_t)
	_sky_mat.set_shader_parameter("lens_aspect", aspect)
	_sky_mat.set_shader_parameter("lens_shift_t", shift_t)
	_sky_mat.set_shader_parameter("lens_basis", basis)

func _ready() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY

	var sky := Sky.new()
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = SKY_SHADER
	sky.sky_material = sky_mat
	_sky_mat = sky_mat
	add_to_group("sun_receivers")
	add_to_group("lens_receivers")
	add_to_group("world_environment")
	env.sky = sky

	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 0.55
	env.ambient_light_energy = 0.75

	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 0.72
	env.tonemap_white = 5.0

	# 逆光雪景：太阳在画面里，需要柔和泛光与朝阳侧的暖色雾散射
	env.glow_enabled = true
	env.glow_intensity = 0.45
	env.glow_strength = 0.85
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = 1.3
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT

	env.ssao_enabled = true
	env.ssao_radius = 1.4
	env.ssao_intensity = 1.6

	env.fog_enabled = true
	env.fog_light_color = Color(0.62, 0.70, 0.86)
	env.fog_light_energy = 0.75
	env.fog_sun_scatter = 0.25
	env.fog_density = 0.0011
	env.fog_aerial_perspective = 0.55
	env.fog_sky_affect = 0.12

	env.adjustment_enabled = true
	env.adjustment_saturation = 1.08
	env.adjustment_contrast = 1.06

	environment = env

	var sun := get_parent().get_node_or_null("SunLight") as DirectionalLight3D
	if sun:
		# 太阳的方向 / 颜色 / 强度由 WeatherController 按 SunModel 真实日轨驱动，这里只设阴影质量。
		sun.shadow_enabled = true
		sun.directional_shadow_max_distance = 90.0
		sun.shadow_blur = 1.2
