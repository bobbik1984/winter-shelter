class_name ShelterInterior
extends Node3D

## "进入庇护所"的剖面视图（2026-11-04 用户方向：对标 north star 右上角的 SHELTER DESIGN 剖面，不用第一人称）。
## 工地沿入口轴线切开：只画切面（局部 x = 0）背后那一半，切面上是厚厚的雪壁，里面是暖色的空腔，
## 人躺在里面。入口在屏幕左边，和参考图一样。外面的地形、树、天气照常。
## 本节点是工地的子节点：局部 +Z = 入口方向，原点在地面。纯外观，不改任何玩法数值。
## 全部不受光（顶点色画好明暗）：剖面要的是图解式的清晰，也最省（兼容渲染器）。

const SNOW_OUT := Color(0.86, 0.91, 0.98)
const SNOW_CUT := Color(0.97, 0.98, 1.0)
const SNOW_IN := Color(0.50, 0.63, 0.84)
const THATCH := Color(0.20, 0.36, 0.22)
const ROCK := Color(0.42, 0.43, 0.48)
const WOOD := Color(0.36, 0.25, 0.15)
const BOUGH := Color(0.17, 0.33, 0.19)
const BAG := Color(0.58, 0.20, 0.13)
const PIT := Color(0.27, 0.38, 0.60)

var camera: Camera3D
## 人躺在哪（局部坐标，脚的位置）；头朝 -Z。
var figure_spot := Vector3(-0.42, 0.25, 0.75)
var _preset := ""
var _vents := 0
var _mat: StandardMaterial3D
var _st: SurfaceTool
var _candle := false
var _candle_pos := Vector3.ZERO

func build(preset: String, finished: bool, vents: int) -> void:
	_preset = preset
	_vents = vents
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.vertex_color_use_as_albedo = true
	_mat.vertex_color_is_srgb = true
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_st = SurfaceTool.new()
	_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var aim := Vector3(0.0, 0.55, 0.45)
	var dist := 5.6
	match preset:
		"RaisedCave":
			_candle = finished
			_candle_pos = Vector3(-1.15, 0.5, -1.15)
			_snow_dome(1.75, 1.6, 1.45, 0.6, 0.6)
			# 高床占后半，前半低下去是冷气坑（雪面以上画不出真的坑，用深色台阶表示）
			_box(Vector3(-0.8, 0.2, -0.65), Vector3(0.8, 0.2, 1.0), SNOW_IN * 1.25)
			_box(Vector3(-0.72, 0.012, 1.0), Vector3(0.72, 0.012, 0.6), PIT)
			figure_spot = Vector3(-0.55, 0.5, 0.2)
			_bed(-0.55, 0.42, -0.65)
			_vent_pipe(0.1, 1.45, 2.1)
		"BasicCave":
			_candle = finished
			_candle_pos = Vector3(-1.15, 0.16, -1.1)
			_snow_dome(1.75, 1.6, 1.3, 0.6, 0.6)
			figure_spot = Vector3(-0.55, 0.14, 0.45)
			_bed(-0.55, 0.05, -0.4)
			_vent_pipe(0.1, 1.3, 1.95)
		"Quinzhee":
			_snow_dome(1.95, 1.8, 1.4, 0.55, 0.5)
			figure_spot = Vector3(-0.6, 0.14, 0.55)
			_bed(-0.6, 0.05, -0.3)
			_vent_pipe(0.0, 1.4, 2.0)
		"SnowTrench":
			_trench()
			figure_spot = Vector3(-0.3, 0.14, 0.6)
			_bed(-0.3, 0.05, -0.3, 0.24)
		"TreeWell":
			_snow_dome(1.7, 1.6, 1.0, 0.6, 0.5, THATCH)
			_half_cone(1.75, 0.95, 2.3, THATCH)
			_cyl(Vector3(0, 0, 0), Vector3(0, 2.6, 0), 0.17, WOOD)
			figure_spot = Vector3(-0.8, 0.14, 0.55)
			_bed(-0.8, 0.05, -0.3)
		"LeanTo":
			_slant_section(1.8, -1.5, 0.25, 1.5, 1.75, THATCH, 0.18)
			_half_floor(2.0, 1.8, BOUGH)
			figure_spot = Vector3(-0.6, 0.14, 0.45)
			_bed(-0.6, 0.05, -0.35)
			aim = Vector3(0.0, 0.6, 0.2)
		"RockOverhang":
			_rock_back()
			_slant_section(1.9, -1.4, 1.0, 1.5, 1.5, THATCH, 0.16)
			_half_floor(2.0, 1.9, BOUGH)
			figure_spot = Vector3(-0.6, 0.14, 0.45)
			_bed(-0.6, 0.05, -0.35)
			aim = Vector3(0.0, 0.6, 0.1)
		"FallenLog":
			_a_frame_section(1.25, 1.05, -1.7, 1.7)
			_cyl(Vector3(0, 1.05, -2.1), Vector3(0, 1.12, 2.5), 0.2, WOOD)
			_half_floor(1.9, 1.25, BOUGH)
			figure_spot = Vector3(-0.55, 0.14, 0.5)
			_bed(-0.55, 0.05, -0.3)
		_:
			_snow_dome(1.75, 1.6, 1.3, 0.6, 0.6)
			_bed(-0.55, 0.05, -0.4)
	if _candle:
		_box(_candle_pos - Vector3(0, 0.08, 0), Vector3(0.05, 0.08, 0.05), Color(0.95, 0.88, 0.7))
		_box(_candle_pos + Vector3(0, 0.03, 0), Vector3(0.035, 0.05, 0.035), Color(1.0, 0.72, 0.28))
	var mi := MeshInstance3D.new()
	mi.mesh = _st.commit()
	mi.material_override = _mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	camera = Camera3D.new()
	camera.fov = 36.0
	camera.near = 0.1
	camera.far = 1400.0
	var elev := deg_to_rad(26.0)
	camera.position = aim + Vector3(cos(elev) * dist, sin(elev) * dist, -0.9)
	add_child(camera)
	camera.look_at(to_global(aim), Vector3.UP)

## 剖面标注：[局部位置, 标题, 副标题]，每种庇护所写它真正有的东西。
func labels() -> Array:
	match _preset:
		"RaisedCave":
			var out := [[Vector3(-0.3, 0.42, -0.7), Loc.t("Raised sleeping platform"), Loc.t("Stay above cold air")],
				[Vector3(0, 0.02, 1.0), Loc.t("Cold-air pit"), Loc.t("Traps cold air (lower)")],
				[Vector3(0, 0.3, 2.2), Loc.t("Entrance tunnel"), Loc.t("Low door keeps the warmth in")]]
			if _vents > 0:
				out.append([Vector3(0, 2.05, 0.1), Loc.t("Vent / Chimney"), Loc.t("Lets out moisture and stale air")])
			return out
		"BasicCave", "Quinzhee":
			var out := [[Vector3(0, 1.75, -0.8), Loc.t("Thick snow roof"), Loc.t("Snow holds your body heat in")],
				[Vector3(0, 0.3, 2.2), Loc.t("Entrance tunnel"), Loc.t("Low door keeps the warmth in")]]
			if _vents > 0:
				out.append([Vector3(0, 1.95, 0.1), Loc.t("Vent / Chimney"), Loc.t("Lets out moisture and stale air")])
			return out
		"SnowTrench":
			return [[Vector3(0, 1.0, -0.4), Loc.t("Roof over the trench"), Loc.t("Blocks wind and falling snow")],
				[Vector3(-0.3, 0.1, -1.0), Loc.t("Bough floor"), Loc.t("Keeps you off the snow")]]
		"TreeWell":
			return [[Vector3(0, 1.7, -0.9), Loc.t("Spruce bough roof"), Loc.t("The tree shelters you")],
				[Vector3(0, 0.5, -1.9), Loc.t("Snow wall"), Loc.t("Blocks the wind")]]
		"LeanTo":
			return [[Vector3(0, 1.1, -0.2), Loc.t("Thatched roof"), Loc.t("Open at the front")],
				[Vector3(0, 0.05, 1.7), Loc.t("Fire side"), Loc.t("Heat reflects in from here")]]
		"RockOverhang":
			return [[Vector3(0, 1.0, -1.8), Loc.t("Cold rock wall"), Loc.t("Blocks wind, drinks heat")],
				[Vector3(-0.6, 0.1, -1.0), Loc.t("Thick bough bed"), Loc.t("Keeps you off cold rock")]]
		"FallenLog":
			return [[Vector3(0, 1.25, -0.6), Loc.t("Fallen log ridge"), Loc.t("Holds up the thatched ribs")],
				[Vector3(-0.55, 0.1, -1.1), Loc.t("Bough bed"), Loc.t("Keeps you off the snow")]]
	return []

## 天黑后压暗，但洞里的烛光不熄（烛光已经画在顶点色里）。
func set_daylight(k: float) -> void:
	var d := clampf(k, 0.0, 1.0)
	var v := lerpf(0.3, 1.0, d)
	if _candle:
		v = maxf(v, 0.6)
	_mat.albedo_color = Color(v, v, v * lerpf(1.3, 1.0, d))

func _process(_delta: float) -> void:
	if camera == null or not camera.current:
		return
	var vp := get_viewport().get_visible_rect().size
	get_tree().call_group("lens_receivers", "set_lens", true, tan(deg_to_rad(camera.fov) * 0.5),
		vp.x / maxf(vp.y, 1.0), 0.0, camera.global_transform.basis.orthonormalized())

# ------------------------------------------------------------------ 明暗

func _speck(x: float, y: float) -> float:
	var v := sin(x * 12.9898 + y * 78.233) * 43758.5453
	return v - floor(v)

## 里面：越靠地面越暗，烛光附近发暖。
func _inner_col(p: Vector3, base: Color) -> Color:
	var k := lerpf(0.62, 1.0, clampf(p.y / 1.4, 0.0, 1.0)) * (0.94 + _speck(p.x * 3.0, p.z * 3.0 + p.y * 3.0) * 0.12)
	var c := Color(base.r * k, base.g * k, base.b * k)
	if _candle:
		var w := clampf(1.0 - p.distance_to(_candle_pos) / 2.3, 0.0, 1.0)
		c += Color(0.75, 0.42, 0.14) * w * w
	return c

func _v(p: Vector3, col: Color) -> void:
	_st.set_color(col)
	_st.add_vertex(p)

func _quad_col(a: Vector3, b: Vector3, c: Vector3, d: Vector3, ca: Color, cb: Color, cc: Color, cd: Color) -> void:
	_v(a, ca); _v(b, cb); _v(c, cc)
	_v(a, ca); _v(c, cc); _v(d, cd)

func _quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, base: Color) -> void:
	_quad_col(a, b, c, d, _inner_col(a, base), _inner_col(b, base), _inner_col(c, base), _inner_col(d, base))

# ------------------------------------------------------------------ 形状（都只画 x <= 0 那半，x = 0 是切面）

## 半球壳上的点：a = 0 在 +Z（入口），a = PI 在 -Z，经 -X。
func _shell_pt(a: float, e: float, rz: float, rx: float, h: float) -> Vector3:
	return Vector3(-sin(a) * cos(e) * rx, sin(e) * h, cos(a) * cos(e) * rz)

## 雪穹顶的剖面：外壳、内壁、切面，加一段低矮的入口隧道。wall = 雪壁厚度。
func _snow_dome(rz: float, rx: float, h: float, wall: float, door_h: float, roof_col: Color = SNOW_IN) -> void:
	var segs := 28
	var rings := 12
	for i in range(segs):
		for j in range(rings):
			var a0 := PI * i / segs
			var a1 := PI * (i + 1) / segs
			var e0 := (PI * 0.5) * j / rings
			var e1 := (PI * 0.5) * (j + 1) / rings
			# 外壳：朝上的面亮，贴地的暗一点
			var o := [_shell_pt(a0, e0, rz + wall, rx + wall, h + wall), _shell_pt(a1, e0, rz + wall, rx + wall, h + wall),
				_shell_pt(a1, e1, rz + wall, rx + wall, h + wall), _shell_pt(a0, e1, rz + wall, rx + wall, h + wall)]
			var cs: Array[Color] = []
			for p: Vector3 in o:
				var k := lerpf(0.72, 1.0, clampf(p.y / (h + wall), 0.0, 1.0))
				cs.append(Color(SNOW_OUT.r * k, SNOW_OUT.g * k, SNOW_OUT.b * k))
			_quad_col(o[0], o[1], o[2], o[3], cs[0], cs[1], cs[2], cs[3])
			# 内壁：入口那一小块开着
			var m := _shell_pt((a0 + a1) * 0.5, (e0 + e1) * 0.5, rz, rx, h)
			if m.z > 0.0 and m.y < door_h and absf(m.x) < 0.55:
				continue
			var base := roof_col if m.y > h * 0.6 else SNOW_IN
			_quad(_shell_pt(a0, e0, rz, rx, h), _shell_pt(a1, e0, rz, rx, h), _shell_pt(a1, e1, rz, rx, h), _shell_pt(a0, e1, rz, rx, h), base)
	# 切面：内外轮廓之间的雪壁。靠内壁一圈透一点暖色，雪壁才有厚度感。
	var warm := SNOW_CUT.lerp(Color(1.0, 0.86, 0.68), 0.55) if _candle else SNOW_CUT.lerp(SNOW_IN, 0.3)
	for side in [0.0, PI]:
		for j in range(rings):
			var e0 := (PI * 0.5) * j / rings
			var e1 := (PI * 0.5) * (j + 1) / rings
			var i0 := _shell_pt(side, e0, rz, rx, h)
			var i1 := _shell_pt(side, e1, rz, rx, h)
			var o0 := _shell_pt(side, e0, rz + wall, rx + wall, h + wall)
			var o1 := _shell_pt(side, e1, rz + wall, rx + wall, h + wall)
			if side == 0.0 and i1.y < door_h:
				continue   # 入口隧道那段没有雪壁
			_quad_col(i0, o0, o1, i1, warm, SNOW_CUT, SNOW_CUT, warm)
	_half_floor(rz, rx, SNOW_IN * 0.85)
	# 隧道：左右墙（只有后面那面）和顶
	var z0 := rz - 0.1
	var z1 := rz + wall + 0.35
	_quad(Vector3(-0.55, 0, z0), Vector3(-0.55, 0, z1), Vector3(-0.55, door_h, z1), Vector3(-0.55, door_h, z0), SNOW_IN)
	_quad(Vector3(-0.55, door_h, z0), Vector3(-0.55, door_h, z1), Vector3(0, door_h, z1), Vector3(0, door_h, z0), SNOW_IN * 1.1)
	_quad_col(Vector3(0, door_h, z0), Vector3(0, door_h, z1), Vector3(0, door_h + wall * 0.6, z1), Vector3(0, door_h + wall, z0), warm, SNOW_CUT, SNOW_CUT, SNOW_CUT)
	_quad(Vector3(-0.55, 0.012, z0), Vector3(-0.55, 0.012, z1), Vector3(0, 0.012, z1), Vector3(0, 0.012, z0), SNOW_IN * 0.8)

## 雪沟：一面墙、后墙、顶板的切面，一端敞开。
func _trench() -> void:
	var w := 0.62
	var h := 0.72
	var roof := 0.28
	var z0 := -1.8
	var z1 := 1.2
	var berm := 0.5
	var steps := 6
	for i in range(steps):
		var a := lerpf(z0, z1, float(i) / steps)
		var b := lerpf(z0, z1, float(i + 1) / steps)
		_quad(Vector3(-w, 0, a), Vector3(-w, 0, b), Vector3(-w, h, b), Vector3(-w, h, a), SNOW_IN)
		_quad(Vector3(-w, h, a), Vector3(-w, h, b), Vector3(0, h, b), Vector3(0, h, a), SNOW_IN * 1.1)
		_quad(Vector3(-w, 0.012, a), Vector3(-w, 0.012, b), Vector3(0, 0.012, b), Vector3(0, 0.012, a), BOUGH)
		# 外面：顶板上表面 + 堆起来的雪墙外坡
		_quad_col(Vector3(0, h + roof, a), Vector3(0, h + roof, b), Vector3(-w - berm, h + roof, b), Vector3(-w - berm, h + roof, a), SNOW_OUT, SNOW_OUT, SNOW_OUT, SNOW_OUT)
		var low := SNOW_OUT * 0.8
		_quad_col(Vector3(-w - berm, h + roof, a), Vector3(-w - berm, h + roof, b), Vector3(-w - berm - 0.5, 0, b), Vector3(-w - berm - 0.5, 0, a), SNOW_OUT, SNOW_OUT, low, low)
	# 切面：顶板和后墙
	_quad_col(Vector3(0, h, z0), Vector3(0, h, z1), Vector3(0, h + roof, z1), Vector3(0, h + roof, z0), SNOW_CUT, SNOW_CUT, SNOW_CUT, SNOW_CUT)
	_quad_col(Vector3(0, 0, z0 - 0.4), Vector3(0, 0, z0), Vector3(0, h + roof, z0), Vector3(0, h + roof, z0 - 0.4), SNOW_CUT, SNOW_CUT, SNOW_CUT, SNOW_CUT)
	_quad(Vector3(-w, 0, z0), Vector3(0, 0, z0), Vector3(0, h, z0), Vector3(-w, h, z0), SNOW_IN * 0.85)

## 斜顶棚：切面是一条斜带，后面是斜下来的枝条面和几根杆子。
func _slant_section(half_w: float, z0: float, y0: float, z1: float, y1: float, base: Color, thick: float) -> void:
	var steps := 8
	for i in range(steps):
		var t0 := float(i) / steps
		var t1 := float(i + 1) / steps
		var a := Vector3(0, lerpf(y0, y1, t0), lerpf(z0, z1, t0))
		var b := Vector3(0, lerpf(y0, y1, t1), lerpf(z0, z1, t1))
		var ao := a + Vector3.UP * thick
		var bo := b + Vector3.UP * thick
		_quad(a, b, b + Vector3(-half_w, 0, 0), a + Vector3(-half_w, 0, 0), base)
		_quad_col(ao, bo, bo + Vector3(-half_w, 0, 0), ao + Vector3(-half_w, 0, 0), base * 1.25, base * 1.25, base * 1.25, base * 1.25)
		_quad_col(a, b, bo, ao, base * 1.7, base * 1.7, base * 1.7, base * 1.7)
	for k in range(4):
		var x := lerpf(-half_w * 0.9, -0.05, float(k) / 3.0)
		_cyl(Vector3(x, y0 - 0.04, z0), Vector3(x, y1 - 0.04, z1), 0.04, WOOD)
	# 贴地的枝条挡边（后面那一侧）
	_quad(Vector3(-half_w, 0, z0), Vector3(-half_w, 0, z1 - 0.5), Vector3(-half_w, lerpf(y0, y1, 0.8), z1 - 0.5), Vector3(-half_w, y0, z0), base)
	_quad(Vector3(-half_w, 0, z0), Vector3(0, 0, z0), Vector3(0, y0, z0), Vector3(-half_w, y0, z0), base)

func _rock_back() -> void:
	var r := ROCK
	_quad(Vector3(-1.9, 0, -1.4), Vector3(0, 0, -1.4), Vector3(0, 1.25, -1.4), Vector3(-1.9, 1.25, -1.4), r)
	_quad_col(Vector3(0, 0, -1.4), Vector3(0, 0, -2.4), Vector3(0, 1.9, -2.4), Vector3(0, 1.25, -1.4), r * 1.5, r * 1.5, r * 1.5, r * 1.5)
	_quad(Vector3(-1.9, 1.25, -1.4), Vector3(0, 1.25, -1.4), Vector3(0, 1.9, -2.4), Vector3(-1.9, 1.9, -2.4), r * 1.2)

## 倒木棚：切在脊上，看到后面那面斜墙和一排肋条。
func _a_frame_section(half_w: float, h: float, z0: float, z1: float) -> void:
	var steps := 8
	for i in range(steps):
		var a := lerpf(z0, z1, float(i) / steps)
		var b := lerpf(z0, z1, float(i + 1) / steps)
		_quad(Vector3(-half_w, 0, a), Vector3(-half_w, 0, b), Vector3(0, h, b), Vector3(0, h, a), THATCH)
		_cyl(Vector3(-half_w, 0, a), Vector3(0, h, a), 0.035, WOOD)
	_quad(Vector3(-half_w, 0, z0), Vector3(0, 0, z0), Vector3(0, h, z0), Vector3(0, h, z0), THATCH * 0.8)

func _half_cone(r: float, y0: float, y1: float, base: Color) -> void:
	var segs := 12
	for i in range(segs):
		var a0 := PI * i / segs
		var a1 := PI * (i + 1) / segs
		var w0 := Vector3(-sin(a0), 0, cos(a0))
		var w1 := Vector3(-sin(a1), 0, cos(a1))
		_quad_col(w0 * r + Vector3.UP * y0, w1 * r + Vector3.UP * y0, w1 * 0.15 + Vector3.UP * y1, w0 * 0.15 + Vector3.UP * y1, base * 1.2, base * 1.2, base * 1.5, base * 1.5)

func _half_floor(rz: float, rx: float, base: Color) -> void:
	var segs := 20
	var c := Vector3(0, 0.01, 0)
	for i in range(segs):
		var a0 := PI * i / segs
		var a1 := PI * (i + 1) / segs
		var p0 := Vector3(-sin(a0) * rx, 0.01, cos(a0) * rz)
		var p1 := Vector3(-sin(a1) * rx, 0.01, cos(a1) * rz)
		_v(c, _inner_col(c, base)); _v(p0, _inner_col(p0, base)); _v(p1, _inner_col(p1, base))

## 枝条垫 + 睡袋。人躺在 figure_spot，头朝 -Z。
func _bed(x: float, y: float, z: float, half_w: float = 0.36) -> void:
	_box(Vector3(x, y + 0.02, z), Vector3(half_w, 0.03, 1.0), BOUGH)
	_box(Vector3(x, y + 0.07, z - 0.05), Vector3(half_w * 0.62, 0.035, 0.85), BAG)

func _vent_pipe(z: float, y0: float, y1: float) -> void:
	if _vents <= 0:
		return
	_cyl(Vector3(-0.08, y0 - 0.05, z), Vector3(-0.08, y1, z), 0.06, Color(0.3, 0.42, 0.6))

func _box(c: Vector3, half: Vector3, base: Color) -> void:
	var n := [Vector3(-1, -1, -1), Vector3(1, -1, -1), Vector3(1, 1, -1), Vector3(-1, 1, -1),
		Vector3(-1, -1, 1), Vector3(1, -1, 1), Vector3(1, 1, 1), Vector3(-1, 1, 1)]
	var p: Array[Vector3] = []
	for k: Vector3 in n:
		p.append(c + k * half)
	for f in [[0, 1, 2, 3], [4, 5, 6, 7], [0, 1, 5, 4], [3, 2, 6, 7], [0, 3, 7, 4], [1, 2, 6, 5]]:
		_quad(p[f[0]], p[f[1]], p[f[2]], p[f[3]], base)

func _cyl(a: Vector3, b: Vector3, r: float, base: Color) -> void:
	var axis := (b - a).normalized()
	var side := axis.cross(Vector3.FORWARD if absf(axis.z) < 0.9 else Vector3.RIGHT).normalized()
	var up := axis.cross(side).normalized()
	var segs := 6
	for i in range(segs):
		var a0 := TAU * i / segs
		var a1 := TAU * (i + 1) / segs
		var o0 := (side * cos(a0) + up * sin(a0)) * r
		var o1 := (side * cos(a1) + up * sin(a1)) * r
		_quad(a + o0, a + o1, b + o1, b + o0, base)
