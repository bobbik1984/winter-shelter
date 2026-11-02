class_name ShelterBuilder
extends Node

## 4 策略庇护所建造控制器：预设加载、选址推荐/校验、5 阶推进、
## 以及把当前施工状态打包成 NightSimulator 输入。
## 规则来源：PRODUCTION_PLAN T2.4–T2.7 / CORE_GAMEPLAY §5 / ShelterPreset。

const STAGES_MAX := 5

var presets: Dictionary = {}
var active_preset_id: String = "RaisedCave"
var current_stage: int = 0
var completion_ratio: float = 0.0

var _site_snow_depth: float = 0.0
var _site_slope_deg: float = 0.0
var _site_near_rootball: bool = false

func _init() -> void:
	_ensure_presets()

func _ready() -> void:
	_ensure_presets()

func _ensure_presets() -> void:
	if presets.is_empty():
		presets = ShelterPreset.create_all_presets()
	if not presets.has(active_preset_id):
		active_preset_id = "RaisedCave"

func recommend_preset_for_site(
	snow_depth: float,
	slope_deg: float,
	near_rootball: bool
) -> String:
	if near_rootball and snow_depth < 1.0:
		return "LeanTo"
	if snow_depth >= 2.0 and slope_deg >= 8.0:
		return "RaisedCave"
	if snow_depth >= 1.5 and slope_deg >= 8.0:
		return "BasicCave"
	if snow_depth >= 0.3:
		return "SnowTrench"
	return "None"

func set_site_conditions(snow_depth: float, slope_deg: float, near_rootball: bool) -> void:
	_site_snow_depth = maxf(snow_depth, 0.0)
	_site_slope_deg = maxf(slope_deg, 0.0)
	_site_near_rootball = near_rootball

func select_preset(preset_id: String) -> bool:
	_ensure_presets()
	if not presets.has(preset_id):
		return false
	active_preset_id = preset_id
	current_stage = 0
	completion_ratio = 0.0
	return true

func active_preset() -> ShelterPreset:
	_ensure_presets()
	return presets.get(active_preset_id, presets["RaisedCave"]) as ShelterPreset

func validate_site(
	preset_id: String,
	snow_depth: float,
	slope_deg: float,
	near_rootball: bool
) -> Dictionary:
	_ensure_presets()
	if not presets.has(preset_id):
		return {"ok": false, "reason": "Unknown shelter preset: %s" % preset_id}
	var preset := presets[preset_id] as ShelterPreset
	return preset.validate_site(snow_depth, slope_deg, near_rootball)

func validate_current_site() -> Dictionary:
	return validate_site(
		active_preset_id, _site_snow_depth, _site_slope_deg, _site_near_rootball
	)

func begin_build(
	preset_id: String,
	snow_depth: float,
	slope_deg: float,
	near_rootball: bool
) -> Dictionary:
	var validation := validate_site(preset_id, snow_depth, slope_deg, near_rootball)
	if not bool(validation.get("ok", false)):
		return validation
	select_preset(preset_id)
	set_site_conditions(snow_depth, slope_deg, near_rootball)
	return validation

func advance_stage() -> Dictionary:
	_ensure_presets()
	var preset := active_preset()
	if current_stage < STAGES_MAX:
		current_stage += 1
		completion_ratio = float(current_stage) / float(STAGES_MAX)

	var idx := clampi(current_stage - 1, 0, STAGES_MAX - 1)
	var stage_title := ""
	if current_stage > 0 and preset.stage_titles.size() > idx:
		stage_title = preset.stage_titles[idx]
	var shelter_level := 0
	var wind_muffle := 0.0
	if current_stage > 0:
		if preset.stage_shelter_levels.size() > idx:
			shelter_level = preset.stage_shelter_levels[idx]
		if preset.stage_wind_muffle.size() > idx:
			wind_muffle = preset.stage_wind_muffle[idx]
	return {
		"stage": current_stage,
		"stage_title": stage_title,
		"shelter_level": shelter_level,
		"wind_muffle": wind_muffle,
		"completion_ratio": completion_ratio,
		"preset_id": active_preset_id,
	}

func build_night_sim_input(warmth_ctrl: WarmthController = null) -> Dictionary:
	_ensure_presets()
	var preset := active_preset()
	var is_lean_to := active_preset_id == "LeanTo"
	var is_snow := active_preset_id in NightSimulator.SNOW_TYPES
	var is_quinzhee := active_preset_id == "Quinzhee"
	var is_tree_well := active_preset_id == "TreeWell"
	var stage := current_stage
	var is_complete := stage >= STAGES_MAX
	var starting_warmth := 100.0
	if warmth_ctrl != null:
		starting_warmth = clampf(warmth_ctrl.body_warmth, 0.0, 100.0)

	var has_cold_pit := active_preset_id == "RaisedCave" and stage >= 2
	var has_raised_bed := active_preset_id == "RaisedCave" and stage >= 3
	var has_vent := stage >= 4 and is_snow and not is_tree_well   # 树井：枝条屋顶透气，没有通风管
	var has_snow_wall := active_preset_id == "SnowTrench" and _site_snow_depth < 1.0 \
		and stage >= 2
	# 岩壁本身就是反射面：只要搭好就算（倒棚要砌反射墙）
	var has_reflector_wall := (is_lean_to and stage >= 4) or (active_preset_id == "RockOverhang" and stage >= 2)
	var bedding := 1.0 if stage >= 3 else 0.0
	var roof := 0.0
	if is_tree_well:
		roof = 0.35 if stage >= 4 else 0.2   # 枝条屋顶：补顶后约等于薄雪顶
	elif is_quinzhee:
		roof = 0.35 if stage >= 3 else 0.0   # 墙厚 = 掏空时留到木棍的厚度
	elif is_snow and stage >= 1:
		roof = clampf(_site_snow_depth * 0.22, 0.30, 0.55)
	var fuel_hours := 0.0
	var fire_lit := is_lean_to and is_complete
	var fire_held := fire_lit
	if fire_lit:
		fuel_hours = 8.0 * 2.0
	var fire_exposure := 0.15 if _site_near_rootball else 0.45

	return {
		"shelter_type": active_preset_id,
		"wind_angle_diff": 180.0 if _site_near_rootball else 150.0,
		"terrain_shelter": 0.7 if _site_near_rootball else 0.35,
		"snow_depth_meters": maxf(_site_snow_depth, OldSpruces.tuning().quinzhee_pile_height_m) if is_quinzhee else _site_snow_depth,
		"slope_deg": _site_slope_deg,
		"roof_thickness_meters": roof,
		"completion_ratio": completion_ratio,
		"has_cold_pit": has_cold_pit,
		"has_raised_bed": has_raised_bed,
		"vent_count": 1 if has_vent else 0,
		"has_vent": has_vent,
		"vent_snow_clogged": false,
		"bedding_quality": bedding,
		"has_snow_wall": has_snow_wall,
		"has_reflector_wall": has_reflector_wall,
		"fire_lit": fire_lit,
		"fire_held": fire_held,
		"fire_exposure": fire_exposure,
		"fuel_hours": fuel_hours,
		"firewood_logs": 0.0 if not fire_lit else 8.0,
		"prewarmed": is_complete and starting_warmth >= 70.0,
		"starting_warmth": starting_warmth,
		"wood_left": float(maxi(preset.wood_cost, 0)),
		"night_hours": 13.8,
	}
