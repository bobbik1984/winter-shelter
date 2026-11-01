class_name ShelterCutawayRig
extends Node3D

## 45° 等距剖面高床雪洞。
## 雪丘 / 洞腔 / 冷气坑 / 下倾隧道 / 睡台 / 通风孔 / 陈设全部是 shaders/cutaway_sdf.gdshader
## 里的一套距离场，本节点只负责：放一块全屏四边形、喂 uniform、摆后景云杉。
## 下面的 static 函数是 shader 中 hill_mid / floor_y / ceil_y 的 GDScript 镜像，
## 供标注线 / 顶厚尺寸线投影使用 —— 改 shader 几何时必须同步这里。

const SDF_SHADER := preload("res://shaders/cutaway_sdf.gdshader")
const SNOW_COVER_SHADER := preload("res://shaders/snow_cover.gdshader")
const TUNING_PATH := "res://resources/tuning.tres"

## 烛灯位置（rig 局部坐标）。
const LANTERN_LOCAL := Vector3(0.18, 0.70, -1.08)
## 测量顶厚的位置：主洞室穹顶最高处 x。
const ROOF_PROBE_X := 0.65
const VENT_X := 0.25

@export var place_on_terrain: bool = false
@export var world_origin: Vector3 = Vector3(20.5, 0.0, 11.2)

## 顶厚（m）：来自 Tuning.roof_thickness_good_m；Tuning 缺失时回退到 0.45（与 tuning.gd 默认值一致）。
var roof_built_m: float = 0.45
var roof_min_m: float = 0.30

var _sdf_material: ShaderMaterial

func _ready() -> void:
	if place_on_terrain:
		var o: Vector2 = MapLayout.get_layout()["cutaway"]   # S2：随布局（旧地图 = 旧位置）
		global_position = Vector3(o.x, TerrainHeight.height_at(o.x, o.y) - 0.10, o.y)
	var tuning := load(TUNING_PATH) as Tuning
	if tuning:
		roof_built_m = tuning.roof_thickness_good_m
		roof_min_m = tuning.roof_thickness_min_m
	_build_sdf_quad()
	_build_diorama_trees()


func _build_sdf_quad() -> void:
	_sdf_material = ShaderMaterial.new()
	_sdf_material.shader = SDF_SHADER
	_sdf_material.set_shader_parameter("roof_m", roof_built_m)
	_sdf_material.set_shader_parameter("lantern_pos", LANTERN_LOCAL)
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	var mi := MeshInstance3D.new()
	mi.name = "CutawaySDF"
	mi.mesh = quad
	mi.material_override = _sdf_material
	# 全屏四边形在 vertex() 里直接写 POSITION，必须禁用视锥剔除。
	mi.extra_cull_margin = 16384.0
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


## 后景覆雪云杉（共用 SpruceMesh + snow_cover），站在雪丘外轮廓上。
func _build_diorama_trees() -> void:
	var wind := load("res://resources/default_wind.tres") as WindData
	var wind_dir := wind.get_blow_direction_3d() if wind else Vector3.RIGHT
	var mat := ShaderMaterial.new()
	mat.shader = SNOW_COVER_SHADER
	mat.set_shader_parameter("base_color", Color(0.07, 0.17, 0.20))
	mat.set_shader_parameter("snow_amount", 0.78)
	var specs := [
		{"pos": Vector2(-3.7, -2.25), "scale": 0.30, "seed": 1},
		{"pos": Vector2(-2.9, -2.85), "scale": 0.36, "seed": 2},
		{"pos": Vector2(-1.9, -3.15), "scale": 0.30, "seed": 3},
		{"pos": Vector2(2.7, -3.0), "scale": 0.32, "seed": 0},
		{"pos": Vector2(3.55, -2.4), "scale": 0.36, "seed": 1},
	]
	for spec in specs:
		var xz: Vector2 = spec["pos"]
		var s: float = spec["scale"]
		var mi := MeshInstance3D.new()
		mi.name = "DioramaSpruce"
		mi.mesh = SpruceMesh.build(int(spec["seed"]), wind_dir)
		mi.material_override = mat
		mi.position = Vector3(xz.x, maxf(hill_mid(xz.x, xz.y), -0.55) - 0.05, xz.y)
		mi.scale = Vector3.ONE * s
		add_child(mi)


# --- shader 几何镜像 ------------------------------------------------------

static func hill_mid(x: float, z: float) -> float:
	var nx := (x - 0.10) / 4.05
	var nz := (z + 0.30) / 3.85
	var dome := maxf(0.0, 1.0 - nx * nx * 0.78 - nz * nz * 0.58)
	var shoulder_l := smoothstep(-4.2, -1.6, x) * (1.0 - smoothstep(-0.6, 1.4, x)) * 0.20
	var shoulder_r := (1.0 - smoothstep(1.8, 4.0, x)) * 0.12
	var ripple := sin(x * 2.2 + z * 1.6) * 0.03
	return -0.36 + pow(dome, 0.74) * 1.75 + shoulder_l + shoulder_r + ripple


static func floor_y(x: float) -> float:
	var f := lerpf(-0.04, -0.18, clampf((x + 3.8) / 2.45, 0.0, 1.0))
	f = lerpf(f, -0.50, smoothstep(-1.62, -1.30, x))
	f = lerpf(f, 0.50, smoothstep(-0.22, -0.02, x))
	return f


static func ceil_y(x: float, z: float) -> float:
	var zn := clampf(absf(z) / 2.05, 0.0, 1.0)
	var taper := sqrt(maxf(0.06, 1.0 - zn * zn * 0.90))
	var tx := clampf((x + 3.8) / 2.65, 0.0, 1.0)
	var tunnel := 0.30 + sin(tx * PI * 0.78) * 0.38 + tx * 0.18
	var cx := clampf((x - 0.42) / 1.95, -1.0, 1.0)
	var dome := -0.05 + pow(maxf(0.0, 1.0 - cx * cx), 0.56) * 1.62
	return lerpf(tunnel, dome, smoothstep(-1.75, -0.95, x)) * taper


## 穹顶内侧最高点 / 外侧雪面（= 内 + 顶厚）：顶厚尺寸线的两端（z = 0 剖切面上）。
func roof_inner_point() -> Vector3:
	return Vector3(ROOF_PROBE_X, ceil_y(ROOF_PROBE_X, 0.0), 0.0)

func roof_outer_point() -> Vector3:
	return roof_inner_point() + Vector3(0.0, roof_built_m, 0.0)
