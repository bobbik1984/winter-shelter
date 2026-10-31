class_name FarTerrainBuilder
extends Node3D

## 100 m 地图之外的一圈山谷与远山（无碰撞，仅视觉）。
## 内缘高度取自 TerrainHeight（略下沉避免接缝露底），向外平滑过渡到山脊噪声。
## 材质复用 snow_cover.gdshader：平坡积雪、陡坡露岩。

const SNOW_COVER_SHADER := preload("res://shaders/snow_cover.gdshader")

@export var map_half: float = 50.0
@export var outer_half: float = 520.0
## [TUNE] 远山最大抬升（m）。
@export var mountain_height: float = 95.0
## [TUNE] 谷底平坦带宽度（m）：从地图边缘起这么远内几乎无抬升。
@export var valley_width: float = 30.0
@export var seed_idx: int = 5

var _coords: PackedFloat32Array

func _ready() -> void:
	_coords = _build_coords()
	_build()

## 非均匀网格：地图边缘附近密、远处稀。
func _build_coords() -> PackedFloat32Array:
	var pos: Array[float] = []
	var d := map_half
	var step := 5.0
	while d < outer_half:
		pos.append(d)
		d += step
		step *= 1.16
	pos.append(outer_half)
	var all := PackedFloat32Array()
	for i in range(pos.size() - 1, -1, -1):
		all.append(-pos[i])
	all.append(-map_half)
	all.append(map_half)
	for v in pos:
		all.append(v)
	return all

func _height(x: float, z: float) -> float:
	var cx := clampf(x, -map_half, map_half)
	var cz := clampf(z, -map_half, map_half)
	var edge := TerrainHeight.height_at(cx, cz) - 0.35
	var dist := maxf(absf(x), absf(z)) - map_half
	var ramp := smoothstep(valley_width, valley_width + 170.0, dist)
	var ridge := _fbm(x * 0.006, z * 0.006)
	var peaks := pow(clampf(ridge, 0.0, 1.0), 1.6) * mountain_height * ramp
	# 谷底缓缓下沉再抬升，形成"山谷"而不是平台
	var valley := -3.0 * smoothstep(0.0, 60.0, dist) * (1.0 - ramp)
	return lerpf(edge, 0.0, smoothstep(0.0, 40.0, dist)) + valley + peaks

func _fbm(x: float, z: float) -> float:
	var sum := 0.0
	var amp := 0.6
	var f := 1.0
	for o in range(4):
		sum += amp * _vnoise(x * f, z * f, o)
		amp *= 0.5
		f *= 2.07
	return sum / 0.9375

func _vnoise(x: float, z: float, o: int) -> float:
	var ix := floori(x)
	var iz := floori(z)
	var fx := x - ix
	var fz := z - iz
	fx = fx * fx * (3.0 - 2.0 * fx)
	fz = fz * fz * (3.0 - 2.0 * fz)
	var a := TerrainHeight.hash2(ix, iz, seed_idx * 17 + o)
	var b := TerrainHeight.hash2(ix + 1, iz, seed_idx * 17 + o)
	var c := TerrainHeight.hash2(ix, iz + 1, seed_idx * 17 + o)
	var d := TerrainHeight.hash2(ix + 1, iz + 1, seed_idx * 17 + o)
	return lerpf(lerpf(a, b, fx), lerpf(c, d, fx), fz)

func _build() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := _coords.size()
	for j in range(n - 1):
		for i in range(n - 1):
			var x0 := _coords[i]
			var x1 := _coords[i + 1]
			var z0 := _coords[j]
			var z1 := _coords[j + 1]
			# 跳过被 100 m 地图占据的中心洞
			if x0 >= -map_half and x1 <= map_half and z0 >= -map_half and z1 <= map_half:
				continue
			var p00 := Vector3(x0, _height(x0, z0), z0)
			var p10 := Vector3(x1, _height(x1, z0), z0)
			var p01 := Vector3(x0, _height(x0, z1), z1)
			var p11 := Vector3(x1, _height(x1, z1), z1)
			st.add_vertex(p00)
			st.add_vertex(p11)
			st.add_vertex(p01)
			st.add_vertex(p00)
			st.add_vertex(p10)
			st.add_vertex(p11)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.name = "FarTerrainMesh"
	mi.mesh = st.commit()
	var mat := ShaderMaterial.new()
	mat.shader = SNOW_COVER_SHADER
	mat.set_shader_parameter("base_color", Color(0.16, 0.20, 0.32))
	mat.set_shader_parameter("snow_color", Color(0.82, 0.88, 0.98))
	mat.set_shader_parameter("snow_amount", 0.58)
	mat.set_shader_parameter("snow_softness", 0.22)
	mat.set_shader_parameter("noise_scale", 0.03)
	mat.set_shader_parameter("noise_strength", 0.35)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
