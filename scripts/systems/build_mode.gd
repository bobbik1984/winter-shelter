class_name BuildMode
extends Node3D

## 建造模式（B，T2.4）：玩家前方显示预览（ghost），实时按 D5 雪深区间、坡度、挡风物校验，
## 不合格时显示**第一条原因**；入口朝向可旋转（R），预设可切换（Tab）。
## 本节点只做预览与校验；确认放置由 GameDirector 处理（材料、唯一工地）。

const PRESETS := ["RaisedCave", "BasicCave", "SnowTrench", "LeanTo", "TreeWell", "Quinzhee", "RockOverhang", "FallenLog"]

var player: Node3D
var visual: Node3D          # 玩家朝向来源（player.visual_node）
var tuning: Tuning
var wind_from: Vector3 = Vector3.LEFT
var active: bool = false
var preset_id: String = "RaisedCave"
## 本局可用的庇护所（D13 §9.2：已学会 ∪ 本关引入；GameDirector 设置）。
var available: PackedStringArray = PackedStringArray(PRESETS)
var entrance_dir: Vector3 = Vector3.RIGHT
## 内部细节（MVP 清单第 9 项，仅雪庇护所）：快速薄顶 / 结实顶；通风管 1 或 2 根。
var quick_roof: bool = false
var vent_count: int = 1

## 当前预览点的校验结果（供 HUD 读取）
var site_pos: Vector3
var depth: float
var slope: float
var near_windbreak: bool
var valid: bool
var reason: String
var wind_angle: float

var _builder := ShelterBuilder.new()
var _ghost: Node3D
var _ring_mat: StandardMaterial3D
var _arrow: MeshInstance3D

func _ready() -> void:
	add_child(_builder)
	_ghost = Node3D.new()
	add_child(_ghost)
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 1.45
	torus.outer_radius = 1.6
	torus.rings = 32
	ring.mesh = torus
	_ring_mat = StandardMaterial3D.new()
	_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring.material_override = _ring_mat
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ghost.add_child(ring)
	_arrow = MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.35
	cone.height = 0.8
	_arrow.mesh = cone
	_arrow.material_override = _ring_mat
	_arrow.rotation = Vector3(PI * 0.5, 0, 0)
	_arrow.position = Vector3(0, 0.15, 2.1)
	_arrow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ghost.add_child(_arrow)
	_ghost.visible = false

## 地图上的树（工地避开树干用）。
func _tree_points() -> PackedVector2Array:
	var out := PackedVector2Array(OldSpruces.points)
	for g in ["forest", "scenery"]:
		for n in get_tree().get_nodes_in_group(g):
			if "spruce_points" in n:
				out.append_array(n.get("spruce_points"))
	return out

func enter() -> void:
	active = true
	# 默认入口朝下风（背风），并推荐适合当前雪深的预设
	entrance_dir = -wind_from
	_update_site()
	var rec := _builder.recommend_preset_for_site(depth, slope, near_windbreak)
	preset_id = rec if rec != "None" else "LeanTo"
	# 帐篷局：没有雪洞选项，直接拿帐篷；否则推荐雪洞后 fallback 会把它留在“坡太缓”的无效状态。
	if "Tent" in available and available.size() == 1:
		preset_id = "Tent"
		_update_site()
	# 站在老云杉旁且会做树井 → 推荐树井（S5：条件就在眼前）
	if "TreeWell" in available and float(OldSpruces.nearest(Vector2(player.global_position.x, player.global_position.z))["distance"]) <= tuning.tree_well_max_trunk_dist_m + 1.5:
		preset_id = "TreeWell"
	if not (preset_id in available) and not available.is_empty():
		# 推荐的庇护所还没学会：先给一个在这里能建的已学会类型，没有就给第一个
		preset_id = available[0]
		for p in available:
			if _builder.validate_site(p, depth, slope, near_windbreak).get("ok", false):
				preset_id = p
				break
	_ghost.visible = true

func exit() -> void:
	active = false
	_ghost.visible = false

func cycle_preset() -> void:
	if available.is_empty():
		return
	var i := available.find(preset_id)
	preset_id = available[(i + 1) % available.size()]

func toggle_roof() -> void:
	quick_roof = not quick_roof

func toggle_vents() -> void:
	vent_count = 2 if vent_count == 1 else 1

func is_snow_preset() -> bool:
	return preset_id in NightSimulator.SNOW_TYPES

func interior_text() -> String:
	if preset_id == "RockOverhang":
		return Loc.t("The rock is your wall and reflects a fire's heat, but cold stone drinks warmth: pile the bed thick.")
	if preset_id == "FallenLog":
		return Loc.t("The trunk is your ridgepole. No wall to reflect a fire, so keep your back to the wind.")
	if not is_snow_preset():
		return Loc.t("Lean-to: the reflector fire burns your stockpiled wood all night (%.0f h per log).") % tuning.fire_fuel_hours_per_log
	var roof := Loc.t("Quick roof %.2f m (−%d%% time, weaker)") % [tuning.roof_thickness_min_m, int(round((1.0 - tuning.quick_roof_time_factor) * 100.0))] if quick_roof else Loc.t("Solid roof %.2f m") % tuning.roof_thickness_good_m
	var vents := Loc.t("2 vents (more air, a little colder)") if vent_count == 2 else Loc.t("1 vent")
	return Loc.t("%s · %s   [T] roof  [2] vents") % [roof, vents]

func rotate_entrance() -> void:
	entrance_dir = entrance_dir.rotated(Vector3.UP, deg_to_rad(-45.0)).normalized()

func display_name() -> String:
	return Loc.t((_builder.presets[preset_id] as ShelterPreset).display_name)

func _process(_delta: float) -> void:
	if not active or player == null:
		return
	_update_site()
	var ok := Color(0.45, 1.0, 0.55, 0.85)
	var bad := Color(1.0, 0.35, 0.25, 0.85)
	_ring_mat.albedo_color = ok if valid else bad
	_ghost.global_position = site_pos + Vector3(0, 0.08, 0)
	_ghost.rotation.y = atan2(entrance_dir.x, entrance_dir.z)

func _update_site() -> void:
	var yaw := visual.rotation.y if visual else 0.0
	var fwd := Vector3(sin(yaw), 0, cos(yaw))
	var p := player.global_position + fwd * tuning.ghost_distance_m
	site_pos = Vector3(p.x, SnowField.height_at(p.x, p.z), p.z)
	depth = SnowField.snow_at(p.x, p.z)
	slope = SnowField.slope_at(p.x, p.z)
	if preset_id == "TreeWell":
		# 树井：工地对准最近的老云杉树干；"深度"取树干周围的开阔积雪（坑壁有多高）
		var n := OldSpruces.nearest(Vector2(p.x, p.z))
		if float(n["distance"]) > tuning.tree_well_max_trunk_dist_m:
			valid = false
			reason = Loc.t("No big spruce with low branches here — look for one: the snow around its trunk is shallow.")
			return
		var tp: Vector2 = n["point"]
		site_pos = Vector3(tp.x, SnowField.height_at(tp.x, tp.y), tp.y)
		depth = TerrainHeight.snow_depth_at(tp.x, tp.y)
		slope = SnowField.slope_at(tp.x, tp.y)
	near_windbreak = ResourceSpawner.nearest_windbreak_distance(get_tree(), site_pos) < tuning.windbreak_radius_m
	if preset_id == "RockOverhang":
		# 岩檐：工地贴在最近岩体的下风侧；悬崖脚就地算（上风方向要真的有崖）
		var rn := LandFeatures.nearest(LandFeatures.rocks, Vector2(p.x, p.z))
		if float(rn["distance"]) <= tuning.rock_max_dist_m:
			var rp: Vector2 = rn["point"]
			var at := LandFeatures.clear_spot_downwind(rp, wind_from, 2.4, _tree_points(), 2.2)
			site_pos = Vector3(at.x, SnowField.height_at(at.x, at.y), at.y)
		elif not LandFeatures.cliff_upwind(p.x, p.z, wind_from, tuning.rock_cliff_run_m, tuning.rock_cliff_rise_m):
			valid = false
			reason = Loc.t("No rock or cliff to shelter behind here: it has to stand between you and the wind.")
			return
		near_windbreak = true
		depth = SnowField.snow_at(site_pos.x, site_pos.z)
		slope = SnowField.slope_at(site_pos.x, site_pos.z)
	elif preset_id == "FallenLog":
		var ln := LandFeatures.nearest(LandFeatures.logs, Vector2(p.x, p.z))
		if float(ln["distance"]) > tuning.fallen_log_max_dist_m:
			valid = false
			reason = Loc.t("No fallen trunk here to use as a ridgepole: look for a log lying in the snow.")
			return
		var lp: Vector2 = ln["point"]
		var la := LandFeatures.clear_spot_downwind(lp, wind_from, 1.4, _tree_points(), 2.2)
		site_pos = Vector3(la.x, SnowField.height_at(la.x, la.y), la.y)
		depth = SnowField.snow_at(site_pos.x, site_pos.z)
		slope = SnowField.slope_at(site_pos.x, site_pos.z)
	wind_angle = GameRules.entrance_wind_angle(entrance_dir, wind_from)
	var v := _builder.validate_site(preset_id, depth, slope, near_windbreak)
	valid = bool(v.get("ok", false))
	reason = String(v.get("reason", ""))
	if valid and (absf(p.x) > 47.0 or absf(p.z) > 47.0):
		valid = false
		reason = Loc.t("Too close to the edge of the valley.")
	if valid and preset_id == "LeanTo" and not near_windbreak and depth >= tuning.snow_depth_non_snow_max_m:
		reason = Loc.t("Allowed, but a lean-to without a rootball windbreak is cold. Snow here is deep enough for a snow shelter.")

## 入口与风向的玩家可读描述。
func wind_text() -> String:
	if wind_angle < 60.0:
		return Loc.t("Entrance faces INTO the wind (%d°) — expect drafts. [R] rotate") % int(wind_angle)
	if wind_angle < 120.0:
		return Loc.t("Entrance is side-on to the wind (%d°)") % int(wind_angle)
	return Loc.t("Entrance is leeward (%d°) — good") % int(wind_angle)
