class_name ShelterSite
extends Node3D

## 世界内的庇护所工地（T2.4–T2.6 / T2.7b）：持有 ShelterBuilder，按阶段刷新程序化外观。
## 局部坐标：+Z = 入口朝向（出口方向）。交互（按住 E）推进下一阶段，材料与工时由 GameDirector 结算。

const SNOW_COVER_SHADER := preload("res://shaders/snow_cover.gdshader")
## Blender 生成的外观模型（tools/blender/build_shelters.py）：每个部件一个节点，名字 "s<a>_<b>__<部件>" = 第 a..b 阶段显示。
## 没有模型文件时用下面的程序化几何（旧版）。
const MODEL_DIR := "res://assets/models/shelters/"
## 入口离中心多远（米，和模型一致：标记、走出庇护所的落点都用它）。
const ENTRANCE_DIST := {"RaisedCave": 2.3, "BasicCave": 2.3, "Quinzhee": 2.3, "SnowTrench": 1.1, "LeanTo": 1.0,
	"TreeWell": 2.3, "RockOverhang": 1.7, "FallenLog": 2.2, "Tent": 1.5}


var builder: ShelterBuilder
## D16 / B4：工地旁的材料堆。
var pile := SitePile.new()
var _pile_root: Node3D
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
var _interior_view: ShelterInterior
var _mound_ghost: StandardMaterial3D
var _inside := false

var _visual: Node3D
var _snow: ShaderMaterial
var _camp_snow: ShaderMaterial
var _terrain: TerrainBuilder
var _dark: StandardMaterial3D
var _wood: ShaderMaterial
var _bough: ShaderMaterial
var _glow: StandardMaterial3D
var _tent_mat: StandardMaterial3D
var _bag_mat: StandardMaterial3D
var _model_mats := {}
var _has_model := false
var _detail := EnvironmentDetails.settings()

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
	_terrain = get_tree().get_first_node_in_group("terrain") as TerrainBuilder
	_snow = ShaderMaterial.new()
	_snow.shader = TerrainBuilder.TERRAIN_SHADER
	_snow.set_shader_parameter("constructed_snow", true)
	_snow.set_shader_parameter("site_snow_depth", clampf(TerrainHeight.snow_depth_at(global_position.x, global_position.z) / 2.5, 0.0, 1.0))
	_snow.set_shader_parameter("site_ground_normal", TerrainHeight.normal_at(global_position.x, global_position.z))
	_camp_snow = _snow.duplicate() as ShaderMaterial
	_camp_snow.set_shader_parameter("packed_vertex_mask", true)
	if _terrain:
		_terrain.snow_render_changed.connect(_sync_snow_render)
		_sync_snow_render()
	_wood = _snow_mat(EnvPalette.DEAD_WOOD, 0.3)
	_bough = _snow_mat(EnvPalette.SPRUCE, 0.35)
	_dark = StandardMaterial3D.new()
	_dark.albedo_color = Color(0.05, 0.07, 0.12)
	_dark.roughness = 1.0
	_glow = StandardMaterial3D.new()
	_glow.albedo_color = Color(1.0, 0.62, 0.26)
	_glow.emission_enabled = true
	_glow.emission = Color(1.0, 0.55, 0.18)
	_glow.emission_energy_multiplier = 2.5
	# 帐篷布：低饱和的苔绿帆布，和云杉 / 雪面同一套冷色环境里不刺眼。
	_tent_mat = StandardMaterial3D.new()
	_tent_mat.albedo_color = Color(0.46, 0.54, 0.44)
	_tent_mat.roughness = 0.95
	_tent_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	# 帐篷布在低角度阳光下容易整块变黑；用不受光的浅帆布色，仍然保留轮廓和雪地对比。
	_tent_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_bag_mat = StandardMaterial3D.new()
	_bag_mat.albedo_color = Color(0.55, 0.32, 0.20)
	_bag_mat.roughness = 0.9
	interactable = Interactable.new()
	interactable.kind = "shelter"
	interactable.ring_radius = 1.6
	_has_model = ResourceLoader.exists(MODEL_DIR + preset_id + ".glb")
	# 交互点在入口前面（模型的入口离中心更远）
	interactable.position = Vector3(0, 0.3, maxf(1.4, float(ENTRANCE_DIST.get(preset_id, 1.9)) - 0.5) if _has_model else 1.4)
	add_child(interactable)
	_refresh()

func stage() -> int:
	return builder.current_stage

func is_complete() -> bool:
	return builder.current_stage >= ShelterBuilder.STAGES_MAX

func is_snow_shelter() -> bool:
	return preset_id in NightSimulator.SNOW_TYPES

## 下一阶开工前还要等到什么时候（游戏分钟；0 = 不用等）。
var ready_at := 0.0

## 入口在世界里的位置（地面上）：每种庇护所的开口离中心不一样远，标记要真的指着开口。
func entrance_point() -> Vector3:
	var dist := 1.5
	if _has_model:
		dist = float(ENTRANCE_DIST.get(preset_id, 1.5))
		var q := global_position + entrance_dir * dist
		return Vector3(q.x, SnowField.height_at(q.x, q.z) + 0.12, q.z)
	match preset_id:
		"SnowTrench": dist = 0.7
		"LeanTo": dist = 1.0
		"TreeWell": dist = 1.6
		"Quinzhee": dist = 2.2
		"RockOverhang": dist = 1.1
		"FallenLog": dist = 0.9
		"Tent": dist = 1.45
	var p := global_position + entrance_dir * dist
	return Vector3(p.x, SnowField.height_at(p.x, p.z) + 0.12, p.z)

## 工地在地面上大约占多大半径（米）。
func footprint_radius() -> float:
	if _has_model:
		return 2.6 if preset_id in ["TreeWell", "Quinzhee"] else 2.3
	return 2.4 if preset_id == "Quinzhee" else 2.0

func next_stage_cost() -> Dictionary:
	var s := builder.current_stage
	if s >= ShelterBuilder.STAGES_MAX:
		return {}
	return builder.active_preset().stage_costs[s]

## 从下一阶到完工还需要的全部材料（第二次评审：倒棚最后一阶要桦皮，玩家到第 4 阶才发现）。
func remaining_cost() -> Dictionary:
	var out := {}
	var costs: Array = builder.active_preset().stage_costs
	for i in range(builder.current_stage, costs.size()):
		for k in costs[i]:
			out[k] = int(out.get(k, 0)) + int(costs[i][k])
	return out

func next_stage_title() -> String:
	var p := builder.active_preset()
	var s := builder.current_stage
	return Loc.t(p.stage_titles[s]) if s < p.stage_titles.size() else ""

func stage_minutes() -> float:
	var p := builder.active_preset()
	var s := mini(builder.current_stage, ShelterBuilder.STAGES_MAX - 1)
	var share := float(p.stage_weights[s]) if s < p.stage_weights.size() else 1.0 / float(ShelterBuilder.STAGES_MAX)
	return p.build_minutes_total * share * time_factor

## 下一阶开工前要等多久（游戏分钟）。
func wait_before_next_stage() -> float:
	var p := builder.active_preset()
	var s := builder.current_stage
	if s >= p.stage_wait_minutes.size() or float(p.stage_wait_minutes[s]) <= 0.0:
		return 0.0
	return OldSpruces.tuning().quinzhee_set_minutes if p.preset_id == "Quinzhee" else float(p.stage_wait_minutes[s])

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

func _sync_snow_render() -> void:
	_terrain.sync_constructed_snow(_snow)
	_terrain.sync_constructed_snow(_camp_snow)

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
	if _has_model:
		_model_visual(s)
	else:
		_legacy_visual(s)
	if s >= 1:
		_ground_blend(s)
	if s == 0:
		# 工地标桩：四根小木桩 + 入口方向
		for c in [Vector3(-1, 0, -1), Vector3(1, 0, -1), Vector3(-1, 0, 1), Vector3(1, 0, 1)]:
			_cyl(c * 1.1 + Vector3(0, 0.35, 0), 0.04, 0.7, _wood)

## 地面过渡（2026-11-09 用户反馈：庇护所像一个放在雪面上的盒子）：
## ① 一圈起伏的雪裙，里侧抬高盖住模型底边、外侧没入地面，边缘用地形高度逐点贴合（坡上也不悬空）；
## ② 几团被踩出来 / 堆出来的雪块撒在周围；③ 入口前有暗底与雪边的施工鞋印。
## 雪裙 + 合并入口 / 弃雪网格 + 鞋印批绘；只在施工阶段变化时生成。
func _site_ground_y(local: Vector3) -> float:
	var w := to_global(Vector3(local.x, 0.0, local.z))
	var h := _terrain.surface_height_at(w.x, w.z) if _terrain else TerrainHeight.height_at(w.x, w.z)
	return h - global_position.y

func _ground_blend(s: int) -> void:
	var fr := footprint_radius()
	var seg := 30
	var inner := fr * 0.7
	var outer := fr + 0.5 + 0.1 * float(s)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pin: Array[Vector3] = []
	var pout: Array[Vector3] = []
	for i in seg:
		var a := TAU * float(i) / float(seg)
		var d := Vector3(sin(a), 0.0, cos(a))
		var n1 := TerrainHeight.hash2(i, s + 3, 311)
		var n2 := TerrainHeight.hash2(i, s + 3, 313)
		# 入口一侧（+Z）雪裙收窄，免得堵住门；背面和侧面厚一点
		var door := smoothstep(0.55, 1.0, d.z)
		var ro := outer * (0.86 + 0.34 * n1) * (1.0 - 0.35 * door)
		var a_in := d * inner
		var a_out := d * ro
		a_in.y = _site_ground_y(a_in) + 0.14 + 0.12 * n2 * (1.0 - door)
		a_out.y = _site_ground_y(a_out) - 0.06
		pin.append(a_in)
		pout.append(a_out)
	for i in seg:
		var j := (i + 1) % seg
		st.add_vertex(pin[i]); st.add_vertex(pout[j]); st.add_vertex(pout[i])
		st.add_vertex(pin[i]); st.add_vertex(pin[j]); st.add_vertex(pout[j])
	st.generate_normals()
	var skirt := MeshInstance3D.new()
	skirt.name = "GroundSkirt"
	skirt.mesh = st.commit()
	skirt.material_override = _snow
	skirt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_visual.add_child(skirt)
	# Deposits live beside the actual opening; no fake stock or extra gameplay nodes.
	var door_z := float(ENTRANCE_DIST.get(preset_id, 1.9)) if _has_model else entrance_point().distance_to(global_position)
	var dressed := CampGroundDress.build(global_transform, door_z, s, is_snow_shelter(), _detail, _terrain.surface_height_at if _terrain else Callable())
	if dressed:
		var camp := MeshInstance3D.new()
		camp.name = "CampGroundDress"
		camp.mesh = dressed
		camp.material_override = _camp_snow
		camp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_visual.add_child(camp)
	# 已发生的施工留下鞋印，复用单 surface 鞋印网格，不叠一整片透明色块。
	if s >= 2:
		var config := EnvironmentDetails.settings()
		var print_count := clampi(config.worksite_prints, 0, 16)
		if not config.enabled or print_count == 0: return
		var prints_z := float(ENTRANCE_DIST.get(preset_id, 1.9)) + 0.5 if _has_model else 1.9
		var prints := MultiMeshInstance3D.new()
		prints.name = "WorksiteFootprints"
		var marks := MultiMesh.new()
		marks.transform_format = MultiMesh.TRANSFORM_3D
		marks.mesh = Footprints.make_mesh()
		marks.instance_count = print_count
		for i in print_count:
			var local := Vector3((0.2 if i % 2 == 0 else -0.2) + (TerrainHeight.hash2(i, 2, 839) - 0.5) * 0.8,
				0, prints_z + (float(i) / maxi(1, print_count - 1) - 0.5) * 1.6)
			var world := to_global(local)
			world.y = SnowField.height_at(world.x, world.z) + 0.012
			var facing := entrance_dir.rotated(Vector3.UP, (TerrainHeight.hash2(i, 3, 839) - 0.5) * 0.8)
			var basis := global_basis.inverse() * Footprints.surface_basis(world, facing)
			marks.set_instance_transform(i, Transform3D(basis.scaled(Vector3(0.24, 1.0, 0.42)), to_local(world)))
		prints.multimesh = marks
		prints.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_visual.add_child(prints)

## 模型外观：按阶段显示部件，材质换成游戏里的雪 / 木头 / 枝条，完工后入口亮灯（倒棚生火）。
func _model_visual(s: int) -> void:
	if s <= 0:
		return
	var inst := (load(MODEL_DIR + preset_id + ".glb") as PackedScene).instantiate()
	_visual.add_child(inst)
	var glow_at := Vector3.INF
	for n in inst.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		var tag := String(mi.name).split("__")
		var range_ := tag[0].trim_prefix("s").split("_")
		var label := tag[1] if tag.size() > 1 else ""
		var a := int(range_[0])
		var b := int(range_[1]) if range_.size() > 1 else 5
		var on := a <= s and s <= b
		# Replace the GLB's isolated spoil balls with the ground-following side heaps.
		if label.begins_with("spoil") and s >= 2 and _detail.enabled and _detail.camp_enabled:
			on = false
		if label == "vent":
			on = on and vent_count >= 1
		elif label == "vent2":
			on = on and vent_count >= 2
		mi.visible = on
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		for i in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(i)
			var m := _model_material(src.resource_name if src else "")
			if m:
				mi.set_surface_override_material(i, m)
		if label == "mound" and on:
			_mound = mi
		if label == "glow":
			# The GLB rectangle was a lighting proxy, not a luminous door panel.
			mi.visible = false
			if on: glow_at = mi.get_aabb().get_center()
	if glow_at != Vector3.INF:
		_entrance_light = OmniLight3D.new()
		_entrance_light.light_color = Color(1.0, 0.6, 0.25)
		_entrance_light.omni_range = 5.0
		_entrance_light.light_energy = _detail.entrance_day_energy
		_entrance_light.position = glow_at + Vector3(0, 0.25, -0.3)
		_visual.add_child(_entrance_light)
	if preset_id == "LeanTo" and s >= 5 and fire == null:
		fire = Campfire.new()
		fire.position = Vector3(0, 0, 2.0)
		add_child(fire)

func _model_material(name_: String) -> Material:
	if _model_mats.is_empty():
		var inner := StandardMaterial3D.new()
		inner.albedo_color = Color(0.22, 0.30, 0.46)
		inner.roughness = 1.0
		var metal := StandardMaterial3D.new()
		metal.albedo_color = Color(0.40, 0.48, 0.60)
		metal.metallic = 0.4
		metal.roughness = 0.45
		var grass := StandardMaterial3D.new()
		grass.albedo_color = EnvPalette.DRY_GRASS
		grass.roughness = 0.95
		_model_mats = {"Snow": _snow, "SnowIn": inner, "Dark": _dark, "Bough": _bough, "Wood": _wood, "Glow": _glow,
			"Rock": _snow_mat(Color(0.33, 0.34, 0.38), 0.45), "Metal": metal, "Grass": grass}
	return _model_mats.get(name_.get_slice(".", 0))

## 旧版程序化外观（没有模型文件时）。
func _legacy_visual(s: int) -> void:
	match preset_id:
		"RaisedCave", "BasicCave":
			_cave_visual(s)
		"SnowTrench":
			_trench_visual(s)
		"LeanTo":
			_leanto_visual(s)
		"TreeWell":
			_treewell_visual(s)
		"Quinzhee":
			_quinzhee_visual(s)
		"RockOverhang":
			_rock_visual(s)
		"FallenLog":
			_fallen_visual(s)
		"Tent":
			_tent_visual(s)

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

## 把材料堆画出来：看得见还有多少柴和枝条（入口旁边，不挡入口）。
func refresh_pile() -> void:
	if _pile_root == null:
		_pile_root = Node3D.new()
		_pile_root.name = "Pile"
		add_child(_pile_root)
	for c in _pile_root.get_children():
		_pile_root.remove_child(c)
		c.queue_free()
	# 放在工地屏幕上的一侧（离入口远的那边），略靠后：材料堆也不能挡住工地和入口（§12.2）
	var side := entrance_dir.cross(Vector3.UP).normalized()
	var away := Vector3.FORWARD
	var camera := get_viewport().get_camera_3d()
	if camera:
		side = camera.global_transform.basis.x
		away = -camera.global_transform.basis.z
		away.y = 0.0
		away = away.normalized()
	if side.dot(entrance_dir) > 0.0:
		side = -side
	# Keep supplies beside the approach, outside the mound and existing trunks/rocks.
	var trees := PackedVector2Array()
	var rocks: Array[Vector3] = []
	for forest in get_tree().get_nodes_in_group("forest"):
		trees.append_array(forest.spruce_points)
		rocks.append_array(forest.rock_spheres)
	for scenery in get_tree().get_nodes_in_group("scenery"):
		trees.append_array(scenery.spruce_points)
	var at := CampGroundDress.pile_position(global_position, side, entrance_dir, trees, rocks)
	_pile_root.global_position = Vector3(at.x, SnowField.height_at(at.x, at.z) + 0.06, at.z)
	_pile_root.global_rotation = Vector3(0.0, atan2(away.x, away.z), 0.0)
	# One draw per resource type, with visible cut ends and irregular branch bundles.
	_pile_batch("StoredWood", CampGroundDress.log_mesh(), mini(pile.amount("wood"), 15), false)
	_pile_batch("StoredBoughs", CampGroundDress.bough_mesh(), mini(pile.amount("bedding"), 6), true)

func _pile_batch(label: String, mesh: ArrayMesh, count: int, bedding: bool) -> void:
	if count <= 0: return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = count
	for i in count:
		var pos := Vector3(0.68, 0.04 + float(i) * 0.06, 0.0) if bedding else Vector3((float(i % 4) - 1.5) * 0.17, 0.08 + float(i / 4) * 0.15, 0.0)
		var yaw := float(i) * 0.36 if bedding else (0.04 if i % 2 else -0.04)
		mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, yaw), pos))
	var drawn := MultiMeshInstance3D.new()
	drawn.name = label
	drawn.multimesh = mm
	drawn.material_override = CampGroundDress.material()
	_pile_root.add_child(drawn)

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
		_entrance_light.light_energy = _detail.entrance_day_energy
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

## 帐篷没有雪洞剖面；完工后只提供 N 休息 / 外观查看，不进入“雪洞内部”视图。
func can_enter() -> bool:
	return preset_id != "Tent"

## "进入庇护所"剖面：平常的外观藏起来，换成切开的那一半。返回剖面相机。
func set_interior_view(on: bool) -> Camera3D:
	if preset_id == "Tent":
		return null
	if on and _interior_view == null:
		_interior_view = ShelterInterior.new()
		add_child(_interior_view)
		_interior_view.build(preset_id, is_complete(), vent_count)
	if _interior_view:
		_interior_view.visible = on
	if _visual:
		_visual.visible = not on
	return _interior_view.camera if on else null

func interior_view() -> ShelterInterior:
	return _interior_view

func interior_daylight(k: float) -> void:
	if _interior_view:
		_interior_view.set_daylight(k)

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
		# 模型的雪丘有好几种材质（外面的雪、洞里的暗面），恢复时去掉整体覆盖即可
		_mound.material_override = _mound_ghost if on else (null if _has_model else _snow)
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


## 洞口已有灯只透出柔和暖光；强度来自视觉资源，不代表可添柴的火源。
func _process(_delta: float) -> void:
	if _entrance_light == null:
		return
	var w := get_tree().get_first_node_in_group("weather")
	if w:
		var elev: float = w.sun_elevation_deg
		_entrance_light.light_energy = lerpf(_detail.entrance_day_energy, _detail.entrance_night_energy, clampf((6.0 - elev) / 8.0, 0.0, 1.0))

## S5 树井外观（工地中心 = 树干）：树干周围挖开的浅坑、修剪后的低枝、枝条地板、补顶的枝条裙、封门。
## 2026-11-12 帐篷套装：草甸 → 帐篷壳 → 火盆/烟囱 → 睡袋 → 压边。
## 帐篷布用低饱和苔绿；火盆是独立 Campfire，柴从工地堆扣。
func _tent_visual(s: int) -> void:
	if s <= 0:
		return
	# 1 阶：草甸 / 地面隔热（即使还没支帐篷，也已经铺好）
	_box(Vector3(0, 0.025, -0.1), Vector3(2.1, 0.05, 2.4), _bough)
	if s >= 2:
		# 帐篷本体：三棱柱 + 两端门帘；沿 Z 轴是脊线。
		var pm := PrismMesh.new()
		pm.size = Vector3(2.6, 1.45, 2.9)
		var shell := MeshInstance3D.new()
		shell.mesh = pm
		shell.material_override = _tent_mat
		shell.position = Vector3(0, 0.72, -0.05)
		_visual.add_child(shell)
		# 入口暗帘（+Z 端）
		_box(Vector3(0, 0.34, 1.38), Vector3(0.85, 0.6, 0.04), _dark)
		# 两根脊杆 + 四根短地钉
		for x in [-1.15, 1.15]:
			_cyl(Vector3(x, 0.0, 0.0), 0.025, 1.5, _wood)
		for p in [Vector3(-1.35, 0.02, 1.35), Vector3(1.35, 0.02, 1.35), Vector3(-1.35, 0.02, -1.35), Vector3(1.35, 0.02, -1.35)]:
			_cyl(p, 0.018, 0.18, _wood)
	if s >= 3:
		# 小火盆 + 烟囱（在帐篷内部靠入口，不挡睡袋）
		var pan := _cyl(Vector3(0.72, 0.12, 0.45), 0.16, 0.08, _dark)
		pan.scale = Vector3(1.0, 1.0, 0.85)
		_cyl(Vector3(0.72, 0.44, 0.45), 0.035, 1.15, _dark)
		if fire == null:
			fire = Campfire.new()
			fire.name = "TentFirePan"
			fire.position = Vector3(0.72, 0.12, 0.45)
			fire.warm_radius = OldSpruces.tuning().tent_fire_warm_radius_m
			add_child(fire)
	if s >= 4:
		# 睡袋 / 防潮垫：必须铺在草甸上
		_box(Vector3(-0.45, 0.10, -0.15), Vector3(0.78, 0.14, 1.85), _bag_mat)
	if s >= 5:
		# 门帘压边 + 帐篷里的柴堆
		_box(Vector3(0, 0.06, 1.58), Vector3(1.15, 0.08, 0.18), _tent_mat)
		refresh_pile()

## 雪堆屋：雪丘一阶阶长高；插着当标记的木棍；掏空后才有洞口。本节点入口 = +Z。
func _quinzhee_visual(s: int) -> void:
	if s <= 0:
		return
	_mound = _sphere(Vector3(0, 0.0, 0), 2.0, Vector3(1.15, 0.45 if s == 1 else 0.7, 1.15), _snow)
	if s >= 2 and s < 3:
		for c in [Vector3(0.6, 1.25, 0.3), Vector3(-0.5, 1.3, -0.3), Vector3(0.1, 1.42, 0.0), Vector3(-0.2, 1.2, 0.7)]:
			_cyl(c, 0.025, 0.4, _wood)
	if s >= 3:
		_sphere(Vector3(0, 0.34, 2.05), 0.5, Vector3(1.0, 0.8, 0.4), _dark)
		_box(Vector3(0, 0.03, 2.7), Vector3(0.9, 0.08, 1.2), _dark)
	if s >= 4:
		_cyl(Vector3(0.2, 1.45, -0.2), 0.05, 0.3, _dark)
	if s >= 5:
		_box(Vector3(0.75, 0.25, 2.25), Vector3(0.5, 0.5, 0.35), _snow)
		_entrance_light = OmniLight3D.new()
		_entrance_light.light_color = Color(1.0, 0.6, 0.25)
		_entrance_light.omni_range = 4.0
		_entrance_light.light_energy = 1.2
		_entrance_light.position = Vector3(0, 0.45, 2.3)
		_visual.add_child(_entrance_light)

## 岩檐：岩体在 -Z 一侧（本节点入口 = +Z，朝下风）。
func _rock_visual(s: int) -> void:
	if s <= 0:
		return
	_box(Vector3(0, 0.03, 0), Vector3(2.4, 0.06, 2.2), _dark)
	if s >= 2:
		for x in [-0.9, 0.0, 0.9]:
			_cyl(Vector3(x, 0.7, 0.2), 0.05, 1.9, _wood, Vector3(-0.75, 0, 0))
	if s >= 3:
		_box(Vector3(0, 0.1, -0.2), Vector3(1.9, 0.14, 1.3), _bough)
	if s >= 4:
		_box(Vector3(0, 0.72, 0.2), Vector3(2.3, 0.1, 1.9), _bough, Vector3(-43.0, 0, 0))
	if s >= 5:
		_cyl(Vector3(1.25, 0.32, 0.5), 0.14, 1.5, _wood, Vector3(PI * 0.5, 0, 0))

## 倒木斜棚：倒木作脊梁（横在 -Z 侧），肋条和枝条斜靠上去。
func _fallen_visual(s: int) -> void:
	if s <= 0:
		return
	_cyl(Vector3(0, 0.75, -0.7), 0.13, 3.2, _wood, Vector3(0, 0, PI * 0.5))
	if s >= 2:
		for x in [-1.2, -0.4, 0.4, 1.2]:
			_cyl(Vector3(x, 0.42, 0.0), 0.04, 1.75, _wood, Vector3(0.95, 0, 0))
	if s >= 3:
		_box(Vector3(0, 0.45, 0.0), Vector3(3.0, 0.1, 1.7), _bough, Vector3(55.0, 0, 0))
	if s >= 4:
		_box(Vector3(0, 0.1, -0.2), Vector3(2.2, 0.14, 1.0), _bough)
	if s >= 5:
		_sphere(Vector3(0, 0.1, -1.25), 1.0, Vector3(1.8, 0.5, 0.45), _snow)

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
