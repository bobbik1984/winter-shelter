class_name ShelterSite
extends Node3D

## 世界内的庇护所工地（T2.4–T2.6 / T2.7b）：持有 ShelterBuilder，按阶段刷新程序化外观。
## 局部坐标：+Z = 入口朝向（出口方向）。交互（按住 E）推进下一阶段，材料与工时由 GameDirector 结算。

const SNOW_COVER_SHADER := preload("res://shaders/snow_cover.gdshader")

## 每个预设各阶段的材料消耗（索引 = 阶段 1..5 → 0..4）。[GAME]
const STAGE_COSTS := {
	"RaisedCave": [{}, {}, {"bedding": 2, "wood": 1}, {}, {}],
	"BasicCave": [{}, {}, {"bedding": 2}, {}, {}],
	"SnowTrench": [{}, {}, {"bedding": 1}, {"wood": 2}, {}],
	"LeanTo": [{"wood": 2}, {}, {"bedding": 2}, {"wood": 2}, {"wood": 2, "bark": 1}],
	# S5 树井：不花木头；云杉枝当地板、补顶、封门
	"TreeWell": [{}, {}, {"bedding": 2}, {"bedding": 1}, {"bedding": 1}],
}

var builder: ShelterBuilder
var preset_id: String = "RaisedCave"
var entrance_dir: Vector3 = Vector3.RIGHT
var snow_depth: float = 0.0
var slope_deg: float = 0.0
var near_windbreak: bool = false
var interactable: Interactable
var fire: Campfire
var quick_roof: bool = false
var vent_count: int = 1
var time_factor: float = 1.0
## 通风管里插了木棍（夜里可捅开新雪）：防止降雪堵塞。
var vent_stick: bool = false
## 世界内洞内视图（T4.4）：玩家进洞时雪丘半透明，露出洞腔、冷气坑、高床、垫层、烛灯。
var _mound: MeshInstance3D
## 完工雪洞的洞口灯（R3：黄昏后调亮，让玩家远远看到"我的洞在这"）。
var _entrance_light: OmniLight3D
var _interior: Node3D
var _mound_ghost: StandardMaterial3D
var _inside := false

var _visual: Node3D
var _snow: ShaderMaterial
var _dark: StandardMaterial3D
var _wood: ShaderMaterial
var _bough: ShaderMaterial
var _glow: StandardMaterial3D

func setup(p_preset: String, p_dir: Vector3, depth: float, slope: float, windbreak: bool) -> void:
	preset_id = p_preset
	entrance_dir = Vector3(p_dir.x, 0, p_dir.z).normalized()
	snow_depth = depth
	slope_deg = slope
	near_windbreak = windbreak

func _ready() -> void:
	add_to_group("shelter_sites")
	builder = ShelterBuilder.new()
	add_child(builder)
	builder.begin_build(preset_id, snow_depth, slope_deg, near_windbreak)
	builder.select_preset(preset_id)
	builder.set_site_conditions(snow_depth, slope_deg, near_windbreak)
	global_position.y = TerrainHeight.height_at(global_position.x, global_position.z)
	rotation.y = atan2(entrance_dir.x, entrance_dir.z)
	_snow = _snow_mat(Color(0.86, 0.90, 0.97), 1.0)
	_wood = _snow_mat(Color(0.30, 0.22, 0.14), 0.3)
	_bough = _snow_mat(Color(0.07, 0.20, 0.12), 0.35)
	_dark = StandardMaterial3D.new()
	_dark.albedo_color = Color(0.05, 0.07, 0.12)
	_dark.roughness = 1.0
	_glow = StandardMaterial3D.new()
	_glow.albedo_color = Color(1.0, 0.62, 0.26)
	_glow.emission_enabled = true
	_glow.emission = Color(1.0, 0.55, 0.18)
	_glow.emission_energy_multiplier = 2.5
	interactable = Interactable.new()
	interactable.kind = "shelter"
	interactable.ring_radius = 1.6
	interactable.position = Vector3(0, 0.3, 1.4)
	add_child(interactable)
	_refresh()

func stage() -> int:
	return builder.current_stage

func is_complete() -> bool:
	return builder.current_stage >= ShelterBuilder.STAGES_MAX

func is_snow_shelter() -> bool:
	return preset_id != "LeanTo"

func next_stage_cost() -> Dictionary:
	var s := builder.current_stage
	if s >= ShelterBuilder.STAGES_MAX:
		return {}
	return STAGE_COSTS.get(preset_id, [{}, {}, {}, {}, {}])[s]

## 从下一阶到完工还需要的全部材料（第二次评审：倒棚最后一阶要桦皮，玩家到第 4 阶才发现）。
func remaining_cost() -> Dictionary:
	var out := {}
	var costs: Array = STAGE_COSTS.get(preset_id, [{}, {}, {}, {}, {}])
	for i in range(builder.current_stage, costs.size()):
		for k in costs[i]:
			out[k] = int(out.get(k, 0)) + int(costs[i][k])
	return out

func next_stage_title() -> String:
	var p := builder.active_preset()
	var s := builder.current_stage
	return Loc.t(p.stage_titles[s]) if s < p.stage_titles.size() else ""

func stage_minutes() -> float:
	return builder.active_preset().build_minutes_total / float(ShelterBuilder.STAGES_MAX) * time_factor

## 0 露天 / 1 锁温 / 2 回温（来自预设的各阶段保温等级）。
func shelter_level() -> int:
	var s := builder.current_stage
	if s <= 0:
		return 0
	var levels := builder.active_preset().stage_shelter_levels
	return levels[mini(s - 1, levels.size() - 1)]

func advance() -> Dictionary:
	var r := builder.advance_stage()
	_refresh()
	return r

func _snow_mat(base: Color, amount: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SNOW_COVER_SHADER
	m.set_shader_parameter("base_color", base)
	m.set_shader_parameter("snow_amount", amount)
	return m

func _refresh() -> void:
	_mound = null
	_entrance_light = null
	_interior = null
	if _visual:
		_visual.queue_free()
	_visual = Node3D.new()
	add_child(_visual)
	var s := builder.current_stage
	match preset_id:
		"RaisedCave", "BasicCave":
			_cave_visual(s)
		"SnowTrench":
			_trench_visual(s)
		"LeanTo":
			_leanto_visual(s)
		"TreeWell":
			_treewell_visual(s)
	if s == 0:
		# 工地标桩：四根小木桩 + 入口方向
		for c in [Vector3(-1, 0, -1), Vector3(1, 0, -1), Vector3(-1, 0, 1), Vector3(1, 0, 1)]:
			_cyl(c * 1.1 + Vector3(0, 0.35, 0), 0.04, 0.7, _wood)

func _sphere(pos: Vector3, r: float, scale_v: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.radial_segments = 16
	m.rings = 8
	mi.mesh = m
	mi.material_override = mat
	mi.position = pos
	mi.scale = scale_v
	_visual.add_child(mi)
	return mi

func _box(pos: Vector3, size: Vector3, mat: Material, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = size
	mi.mesh = m
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	_visual.add_child(mi)
	return mi

func _cyl(pos: Vector3, r: float, h: float, mat: Material, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := CylinderMesh.new()
	m.top_radius = r
	m.bottom_radius = r
	m.height = h
	m.radial_segments = 7
	mi.mesh = m
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	_visual.add_child(mi)
	return mi

func _cave_visual(s: int) -> void:
	if s <= 0:
		return
	# 雪丘（挖掘弃雪堆成的穹顶）+ 入口暗洞
	_mound = _sphere(Vector3(0, -0.2, -1.0), 2.0, Vector3(1.3, 0.62 + 0.05 * s, 1.15), _snow)
	_build_interior(s)
	# 入口：必须突出雪丘表面（雪丘前缘在 z ≈ 1.30；原来洞口 z ≤ 1.14 整个埋在雪里，评审 R3）
	var hole := _sphere(Vector3(0, 0.36, 1.22), 0.55, Vector3(1.0, 0.75 + 0.08 * mini(s, 2), 0.42), _dark)
	# 入口前挖出的引道（从任何机位都看得出"这里挖进去了"）：下沉的暗色沟底 + 两侧弃雪埂
	if s >= 2:
		var trench_len := 1.2 + 0.25 * mini(s, 4)
		_box(Vector3(0, 0.03, 1.3 + trench_len * 0.5), Vector3(0.95, 0.08, trench_len), _dark)
		_sphere(Vector3(-0.85, 0.05, 1.35 + trench_len * 0.5), 0.5, Vector3(0.45, 0.42, trench_len * 1.1), _snow)
		_sphere(Vector3(0.85, 0.05, 1.35 + trench_len * 0.5), 0.5, Vector3(0.45, 0.42, trench_len * 1.1), _snow)
	# 弃雪堆
	for i in range(mini(s, 3) + 1):
		_sphere(Vector3(-1.4 + i * 0.9, 0.0, 1.6 + (i % 2) * 0.4), 0.45, Vector3(1, 0.5, 1), _snow)
	if s >= 3:
		_box(Vector3(0.3, 0.15, 1.35), Vector3(0.7, 0.12, 0.3), _bough)
	if s >= 4:
		_cyl(Vector3(0.15, 1.35, -1.2), 0.06, 0.6, _wood)
		if vent_count >= 2:
			_cyl(Vector3(-0.45, 1.25, -1.5), 0.06, 0.6, _wood)
	if s >= 5:
		hole.material_override = _glow
		# 完工：洞口烛光照亮引道与周围雪面（黄昏后越来越显眼；_process 按日高调亮）
		_entrance_light = OmniLight3D.new()
		_entrance_light.light_color = Color(1.0, 0.6, 0.25)
		_entrance_light.omni_range = 5.0
		_entrance_light.light_energy = 1.4
		_entrance_light.position = Vector3(0, 0.6, 1.9)
		_visual.add_child(_entrance_light)

func _build_interior(s: int) -> void:
	_interior = Node3D.new()
	_interior.visible = _inside
	_visual.add_child(_interior)
	var cave := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 20
	sm.rings = 10
	cave.mesh = sm
	var inner := StandardMaterial3D.new()
	inner.albedo_color = Color(0.55, 0.66, 0.82)
	inner.cull_mode = BaseMaterial3D.CULL_FRONT   # 从外面看到的是洞腔内壁
	inner.roughness = 0.95
	cave.material_override = inner
	cave.position = Vector3(0, 0.35, -1.0)
	cave.scale = Vector3(1.05, 0.55 + 0.05 * mini(s, 3), 0.95)
	_interior.add_child(cave)
	if s >= 2 and preset_id == "RaisedCave":
		var pit := _box(Vector3(-0.55, -0.12, -0.7), Vector3(0.6, 0.12, 0.9), _dark)
		pit.reparent(_interior)
	if s >= 3:
		var bed := _box(Vector3(0.35, 0.22 if preset_id == "RaisedCave" else 0.05, -1.15), Vector3(0.9, 0.1, 1.4), _bough)
		bed.reparent(_interior)
		var bag := _box(Vector3(0.35, 0.33 if preset_id == "RaisedCave" else 0.16, -1.15), Vector3(0.45, 0.14, 1.1), _wood)
		bag.reparent(_interior)
	if s >= 5:
		var candle := _sphere(Vector3(-0.45, 0.45, -1.55), 0.06, Vector3.ONE, _glow)
		candle.reparent(_interior)
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.62, 0.26)
		l.omni_range = 2.6
		l.light_energy = 1.6
		l.position = Vector3(-0.45, 0.6, -1.5)
		_interior.add_child(l)

## 进洞 / 出洞：雪丘变半透明并显示洞内。
func set_inside(on: bool) -> void:
	if on == _inside:
		return
	_inside = on
	if _interior:
		_interior.visible = on
	if _mound:
		if _mound_ghost == null:
			_mound_ghost = StandardMaterial3D.new()
			_mound_ghost.albedo_color = Color(0.88, 0.92, 1.0, 0.22)
			_mound_ghost.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			_mound_ghost.cull_mode = BaseMaterial3D.CULL_BACK
		_mound.material_override = _mound_ghost if on else _snow
		_mound.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

func _trench_visual(s: int) -> void:
	if s <= 0:
		return
	_box(Vector3(0, 0.02, -0.6), Vector3(0.95, 0.05, 2.4), _dark)
	if s >= 2:
		for x in [-0.65, 0.65]:
			_box(Vector3(x, 0.22, -0.6), Vector3(0.32, 0.45, 2.5), _snow)
	if s >= 3:
		_box(Vector3(0, 0.07, -0.6), Vector3(0.8, 0.06, 2.2), _bough)
	if s >= 4:
		for k in range(5):
			_cyl(Vector3(0, 0.48, -1.6 + k * 0.5), 0.05, 1.7, _wood, Vector3(0, 0, PI * 0.5))
		_box(Vector3(0, 0.6, -0.8), Vector3(1.5, 0.14, 1.9), _snow)
	if s >= 5:
		_box(Vector3(0, 0.3, -1.95), Vector3(1.6, 0.6, 0.35), _snow)

func _leanto_visual(s: int) -> void:
	if s <= 0:
		return
	# 骨架：两根叉柱 + 横梁（棚口朝 +Z）
	for x in [-1.3, 1.3]:
		_cyl(Vector3(x, 0.7, 0.4), 0.06, 1.4, _wood)
	_cyl(Vector3(0, 1.38, 0.4), 0.07, 2.9, _wood, Vector3(0, 0, PI * 0.5))
	if s >= 2:
		_box(Vector3(0, 0.72, -0.4), Vector3(2.8, 0.14, 1.9), _bough, Vector3(deg_to_rad(-48.0), 0, 0))
	if s >= 3:
		_box(Vector3(0, 0.08, 0.1), Vector3(2.3, 0.12, 1.1), _bough)
	if s >= 4:
		for k in range(3):
			_cyl(Vector3(0, 0.15 + k * 0.24, 2.6), 0.12, 2.6, _wood, Vector3(0, 0, PI * 0.5))
	if s >= 5 and fire == null:
		fire = Campfire.new()
		fire.position = Vector3(0, 0, 1.6)
		add_child(fire)


## R3：洞口灯随天色变亮（白天 1.4 → 入夜 3.2），远处也能看到雪地上的暖光。
func _process(_delta: float) -> void:
	if _entrance_light == null:
		return
	var w := get_tree().get_first_node_in_group("weather")
	if w:
		var elev: float = w.sun_elevation_deg
		_entrance_light.light_energy = lerpf(1.4, 3.2, clampf((6.0 - elev) / 8.0, 0.0, 1.0))

## S5 树井外观（工地中心 = 树干）：树干周围挖开的浅坑、修剪后的低枝、枝条地板、补顶的枝条裙、封门。
func _treewell_visual(s: int) -> void:
	if s <= 0:
		return
	# 浅坑：树干周围下沉的暗色雪坑 + 外圈弃雪
	_sphere(Vector3(0, 0.02, 0), 1.0, Vector3(1.5, 0.06, 1.5), _dark)
	for i in range(6):
		var a := TAU * float(i) / 6.0
		_sphere(Vector3(cos(a) * 1.9, 0.0, sin(a) * 1.9), 0.5, Vector3(0.8, 0.45, 0.8), _snow)
	if s >= 2:
		# 修下来的低枝堆在坑边
		_box(Vector3(1.6, 0.12, -1.2), Vector3(0.9, 0.12, 0.35), _bough, Vector3(0, 30, 0))
	if s >= 3:
		_box(Vector3(0, 0.08, 0.6), Vector3(1.2, 0.08, 1.2), _bough)
	if s >= 4:
		# 补顶：围着树干的枝条裙（低矮圆锥）
		var cone := CylinderMesh.new()
		cone.top_radius = 0.25
		cone.bottom_radius = 1.9
		cone.height = 1.3
		cone.radial_segments = 10
		var mi := MeshInstance3D.new()
		mi.mesh = cone
		mi.material_override = _bough
		mi.position = Vector3(0, 0.75, 0)
		_visual.add_child(mi)
	if s >= 5:
		# 封门的枝条束 + 洞口暖光（朝 entrance_dir，本节点已按入口朝向旋转，入口 = +Z）
		_box(Vector3(0, 0.35, 1.75), Vector3(0.8, 0.5, 0.25), _bough)
		_entrance_light = OmniLight3D.new()
		_entrance_light.light_color = Color(1.0, 0.6, 0.25)
		_entrance_light.omni_range = 4.0
		_entrance_light.light_energy = 1.2
		_entrance_light.position = Vector3(0, 0.5, 1.6)
		_visual.add_child(_entrance_light)
