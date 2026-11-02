class_name DriftScatter
extends Node3D

## 风积雪枕（Read the Land 第 2 条："Snow drifts reveal depth"）：
## 在背风且雪深足够的位置堆出圆润、朝下风拉长的雪枕，让玩家不探测也能"看出"哪里雪深。
## 只是视觉提示（无碰撞）；真实深度仍以探针为准。MultiMesh 分块。

@export var spacing: float = 6.5
## 雪枕出现的最小雪深（m）与最小背风度。
@export var min_depth: float = 2.2
@export var min_lee: float = 0.0

var _mat: ShaderMaterial

## "occlusion_fade" 组回调：雪枕（最高约 1.5 m）挡住玩家时镂空。
func set_focus(pos: Vector3) -> void:
	if _mat:
		_mat.set_shader_parameter("focus_pos", pos)

## D16：建造特写时放大镂空范围。
func set_focus_fade(radius: float, strength: float) -> void:
	if _mat:
		_mat.set_shader_parameter("occlusion_radius", radius)
		_mat.set_shader_parameter("occlusion_strength", strength)

func _ready() -> void:
	add_to_group("occlusion_fade")
	var wind := load("res://resources/default_wind.tres") as WindData
	var blow := wind.get_blow_direction_3d() if wind else Vector3.RIGHT
	var yaw := atan2(blow.x, blow.z)
	var transforms: Array = []
	var n := int(96.0 / spacing)
	for j in range(n):
		for i in range(n):
			var x := -48.0 + (float(i) + TerrainHeight.hash2(i, j, 611)) * spacing
			var z := -48.0 + (float(j) + TerrainHeight.hash2(i, j, 613)) * spacing
			var depth := SnowField.snow_at(x, z)
			var lee := SnowField.lee_factor_at(x, z)
			if depth < min_depth or lee < min_lee:
				continue
			var k := clampf((depth - min_depth) / 0.8, 0.3, 1.0)
			var s := Vector3(2.2 + 1.4 * k, 1.0 + 0.8 * k, 2.2 + 1.4 * k)
			var basis := Basis(Vector3.UP, yaw + (TerrainHeight.hash2(i, j, 617) - 0.5) * 0.5).scaled(s)
			transforms.append(Transform3D(basis, Vector3(x, SnowField.height_at(x, z) - 0.08, z)))
	if transforms.is_empty():
		return
	var mesh := PropMeshes.snow_drift()
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/snow_cover.gdshader")
	mat.set_shader_parameter("base_color", Color(0.80, 0.86, 0.96))
	mat.set_shader_parameter("snow_color", Color(0.94, 0.96, 1.0))
	mat.set_shader_parameter("snow_amount", 1.0)
	mat.set_shader_parameter("base_roughness", 0.8)
	mat.set_shader_parameter("occlusion_fade", true)
	_mat = mat
	ForestScatter.add_chunked(self, "Drifts", mesh, mat, transforms, 25.0, true)
	print("[DriftScatter] drift pillows: %d" % transforms.size())
