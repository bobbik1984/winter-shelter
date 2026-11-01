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

## [TUNE] 远景林：采样间距（m）与林线（相对谷底的最大海拔，m）。
@export var far_tree_spacing: float = 12.0
@export var far_tree_max_height: float = 45.0

const SPRUCE_SNOW := Color(0.05, 0.12, 0.11)

func _ready() -> void:
	_coords = _build_coords()
	_build()
	_build_far_forest()
	_build_lake()

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

## 远景方向（= 相机前方 = 西南，午后太阳方位）：这一侧做深谷，远处才起山，留出天际线与落日。
const VISTA_DIR := Vector2(-0.7071, 0.7071)

func _height(x: float, z: float) -> float:
	var cx := clampf(x, -map_half, map_half)
	var cz := clampf(z, -map_half, map_half)
	var edge := TerrainHeight.height_at(cx, cz) - 0.35
	var dist := maxf(absf(x), absf(z)) - map_half
	var along := Vector2(x, z).normalized().dot(VISTA_DIR)
	var vista := smoothstep(0.15, 0.8, along)
	# 远景一侧山更远、更高（成排的背光雪峰）；两侧近处起坡框住画面
	var start := lerpf(valley_width, 260.0, vista)
	var ramp := smoothstep(start, start + 200.0, dist)
	var ridge := _fbm(x * 0.006, z * 0.006)
	# 正前方（落日方位）远山压低到地平线上几度，让太阳落在山脊上方；两侧高山框住画面
	var peaks := pow(clampf(ridge, 0.0, 1.0), 1.6) * mountain_height * lerpf(1.25, 0.55, vista) * ramp
	# 远景谷底：从地图边缘向下跌约 38 m，再在远山脚下回升
	var drop := -38.0 * vista * smoothstep(5.0, 150.0, dist) * (1.0 - ramp)
	var valley := -3.0 * smoothstep(0.0, 60.0, dist) * (1.0 - ramp) * (1.0 - vista)
	return lerpf(edge, 0.0, smoothstep(0.0, 40.0, dist)) + valley + drop + peaks

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
	mat.set_shader_parameter("snow_amount", 0.68)
	mat.set_shader_parameter("snow_softness", 0.22)
	mat.set_shader_parameter("noise_scale", 0.03)
	mat.set_shader_parameter("noise_strength", 0.35)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


## 远景云杉林：低面数 SpruceMesh（6 枝尖）MultiMesh，铺在谷坡与山脚、林线以下。
func _build_far_forest() -> void:
	var wind := load("res://resources/default_wind.tres") as WindData
	var blow := wind.get_blow_direction_3d() if wind else Vector3.RIGHT
	var transforms: Array[Transform3D] = []
	var lim := 330.0
	var n := int(lim * 2.0 / far_tree_spacing)
	for j in range(n):
		for i in range(n):
			var x := -lim + (float(i) + TerrainHeight.hash2(i, j, 501)) * far_tree_spacing
			var z := -lim + (float(j) + TerrainHeight.hash2(i, j, 503)) * far_tree_spacing
			if maxf(absf(x), absf(z)) < map_half + 3.0:
				continue
			var h := _height(x, z)
			if h > far_tree_max_height:
				continue
			var dens := _fbm(x * 0.02 + 3.0, z * 0.02 - 7.0)
			if dens < 0.45:
				continue
			# 太陡不长树（用有限差分估算坡度）
			var gx := _height(x + 2.0, z) - _height(x - 2.0, z)
			var gz := _height(x, z + 2.0) - _height(x, z - 2.0)
			if Vector2(gx, gz).length() / 4.0 > 0.75:
				continue
			var s := lerpf(1.0, 2.1, TerrainHeight.hash2(i, j, 507))
			transforms.append(Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * s), Vector3(x, h - 0.3, z)))
	if transforms.is_empty():
		return
	var mat := ShaderMaterial.new()
	mat.shader = SNOW_COVER_SHADER
	mat.set_shader_parameter("base_color", SPRUCE_SNOW)
	mat.set_shader_parameter("snow_amount", 0.66)
	ForestScatter.add_chunked(self, "FarForest", SpruceMesh.build(9, blow, 0.38, 6), mat, transforms, 110.0, false)
	print("[FarTerrain] far trees: %d" % transforms.size())


## 远景谷底冰湖（V6，对应 North Star 远景）：在远景方向的谷底找最低点，铺一片冰面。
func _build_lake() -> void:
	var best := Vector2.ZERO
	var best_h := INF
	for r in range(110, 260, 10):
		for k in range(-6, 7):
			var dir := VISTA_DIR.rotated(deg_to_rad(k * 4.0))
			var p := dir * float(r)
			var h := _height(p.x, p.y)
			if h < best_h:
				best_h = h
				best = p
	var mi := MeshInstance3D.new()
	mi.name = "FrozenLake"
	var disc := CylinderMesh.new()
	disc.top_radius = 1.0
	disc.bottom_radius = 1.0
	disc.height = 0.2
	disc.radial_segments = 40
	mi.mesh = disc
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.70, 0.82, 0.95)
	mat.roughness = 0.08
	mat.metallic_specular = 0.8
	mi.material_override = mat
	mi.position = Vector3(best.x, best_h + 1.2, best.y)
	mi.scale = Vector3(90.0, 1.0, 50.0)
	mi.rotation.y = atan2(VISTA_DIR.x, VISTA_DIR.y)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
