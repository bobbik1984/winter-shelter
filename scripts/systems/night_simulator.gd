class_name NightSimulator
extends RefCounted

## 6 维可解释夜间结算模型（T0.6）。
## 遵循 Hard != Obscure：输出 6 项 0–100 分 + 每项一句归因 + SAFE/COLD/DANGEROUS 结论。
##
## 用户裁定的 6 维 key（顺序与 notes 一致）：
##   site       选址 / 入口与风向夹角 / 地形避风
##   structure  雪深余量 / 顶厚 / 完工度 / 骨架
##   insulation 地面垫层
##   isolation  冷气池 / 高床 / 与地面冷空气隔离
##   air        通风管数量与堵塞
##   heat       保暖形制 + 火/备柴能否烧到天亮
##
## 输入 Dictionary 的键（未提供时使用保守默认值）：
##   shelter_type: String          "RaisedCave" / "BasicCave" / "SnowTrench" / "LeanTo" / "None"；
##                                 未知值按 None 结算，并在 details.unknown_preset 标记，不崩溃。
##   wind_angle_diff: float        入口（倒棚为棚口）与夜间主风向夹角，0=正迎风，180=完全背风。
##   wind_speed_kmh: float         夜间风速，默认取 Tuning.wind_speed_kmh。
##   night_temp_c: float           夜间气温，默认取 Tuning.temp_at_night_c。
##   terrain_shelter: float        微地形避风度 -1..1。
##   has_cold_pit: bool            是否挖出冷气坑。
##   has_raised_bed: bool          睡床是否抬离地面（高床/床架）。
##   has_snow_wall: bool           浅雪雪沟是否用切下的雪块砌墙。
##   has_reflector_wall: bool      倒棚是否砌了反射墙。
##   vent_count: int               通风管数量；未给时按 has_vent 折算 1 或 0。
##   has_vent: bool                兼容旧输入的通风管开关。
##   vent_snow_clogged: bool       通风管是否被夜间降雪堵塞。
##   bedding_quality: float        地面垫层质量 0..1。
##   roof_thickness_meters: float  顶厚（m）。
##   completion_ratio: float       施工完成度 0..1。
##   snow_depth_meters: float      现场雪深（m）。
##   slope_deg: float              建造坡度（度）。
##   wood_left: float              可用支撑木数量。
##   fire_lit: bool                是否点过火。雪庇护所内该输入被忽略（禁止明火）。
##   fire_held: bool               倒棚火是否维持住。
##   fire_exposure: float          火位迎风暴露 0（背风）..1（迎风）。
##   fuel_hours: float             通宵备柴可燃烧小时数；未给时按 firewood_logs 折算。
##   firewood_logs: float          通宵备柴根数（需要 Tuning.fire_fuel_hours_per_log）。
##   night_hours: float            名义夜长，默认取 Tuning.night_duration_hours。
##   prewarmed: bool               睡前篝火是否完成入夜前暖身（pre-warm）。
##
## 火规则（D2/D3）：
##   * 雪庇护所内不允许生火；fire_lit/fuel_hours 不参与整夜供热，只接受 prewarmed 的入夜修正。
##   * 倒棚是开放结构，反射火 + 备柴决定能否烧到天亮；备柴不足或火被风吹灭会写进 heat note。

const PRESET_RAISED_CAVE := "RaisedCave"
const PRESET_BASIC_CAVE := "BasicCave"
const PRESET_SNOW_TRENCH := "SnowTrench"
const PRESET_LEAN_TO := "LeanTo"
const PRESET_NONE := "None"

const OUTCOME_SAFE := "SAFE"
const OUTCOME_COLD := "COLD"
const OUTCOME_DANGEROUS := "DANGEROUS"

const SCORE_KEYS := ["site", "structure", "insulation", "isolation", "air", "heat"]

const MINUTES_PER_DAY := 24 * 60


static func evaluate(input: Dictionary, tuning: Tuning) -> Dictionary:
	if tuning == null:
		return _missing_tuning_report()

	var t: Tuning = tuning

	# ---------------------------------------------------------------- 输入解析
	var raw_type := _input_string(input, "shelter_type", PRESET_NONE)
	var resolved := _resolve_preset(raw_type)
	var shelter_type: String = str(resolved.get("type", PRESET_NONE))
	var known_preset: bool = bool(resolved.get("known", true))
	var is_snow := _is_snow_shelter(shelter_type)
	var is_lean_to := shelter_type == PRESET_LEAN_TO

	var wind_angle_diff := clampf(_input_float(input, "wind_angle_diff", 180.0), 0.0, 180.0)
	var wind_speed := maxf(_input_float(input, "wind_speed_kmh", t.wind_speed_kmh), 0.0)
	var night_temp := _input_float(input, "night_temp_c", t.temp_at_night_c)
	var terrain_shelter := clampf(_input_float(input, "terrain_shelter", 0.0), -1.0, 1.0)
	var snow_depth := maxf(_input_float(input, "snow_depth_meters", 0.0), 0.0)
	var roof_thickness := maxf(_input_float(input, "roof_thickness_meters", 0.0), 0.0)
	var completion := clampf(_input_float(input, "completion_ratio", 0.0), 0.0, 1.0)
	var slope_deg := maxf(_input_float(input, "slope_deg", 0.0), 0.0)
	var wood_left := maxf(_input_float(input, "wood_left", 0.0), 0.0)
	var bedding_quality := clampf(_input_float(input, "bedding_quality", 0.0), 0.0, 1.0)
	var has_cold_pit := _input_bool(input, "has_cold_pit", false)
	var has_raised_bed := _input_bool(input, "has_raised_bed", false)
	var has_snow_wall := _input_bool(input, "has_snow_wall", false)
	var has_reflector_wall := _input_bool(input, "has_reflector_wall", false)
	var vent_clogged := _input_bool(input, "vent_snow_clogged", false)
	var vent_count := _input_int(
		input,
		"vent_count",
		1 if _input_bool(input, "has_vent", false) else 0
	)
	var fire_lit := _input_bool(input, "fire_lit", false)
	var fire_held := _input_bool(input, "fire_held", false)
	var fire_exposure := clampf(_input_float(input, "fire_exposure", 0.0), 0.0, 1.0)
	var prewarmed := _input_bool(
		input,
		"prewarmed",
		_input_bool(input, "pre_sleep_fire", false)
	)
	var night_hours := maxf(_input_float(input, "night_hours", t.night_duration_hours), 0.01)
	var fuel_hours := _input_float(input, "fuel_hours", -1.0)
	if fuel_hours < 0.0:
		var firewood_logs := maxf(_input_float(input, "firewood_logs", 0.0), 0.0)
		fuel_hours = firewood_logs * t.fire_fuel_hours_per_log
	fuel_hours = maxf(fuel_hours, 0.0)

	# 0° 正迎风 → windward=1；180° 完全背风 → windward=0。180° 是角度制几何常量。
	var windward := clampf(1.0 - wind_angle_diff / 180.0, 0.0, 1.0)
	var gust_factor := clampf(wind_speed / maxf(t.wind_full_effect_kmh, 0.001), 0.0, 1.0)

	# ---------------------------------------------------------------- Site
	var site := 0.0
	if shelter_type == PRESET_NONE:
		site = t.none_site_score
	else:
		site = 1.0 - windward * (
			t.site_wind_base_penalty + t.site_wind_gust_penalty * gust_factor
		) + terrain_shelter * t.terrain_shelter_bonus
	site = clampf(site, 0.0, 1.0)

	# ---------------------------------------------------------------- Structure
	var structure := 0.0
	var wall_variant := false
	var invalid_depth := false
	var missing_wall := false
	var slope_ratio := clampf(slope_deg / maxf(t.max_build_slope_deg, 0.001), 0.0, 1.0)
	var slope_penalty := slope_ratio * t.structure_slope_penalty
	var brace_ratio := clampf(
		wood_left / maxf(float(_preset_wood_cost(shelter_type, t)), 1.0), 0.0, 1.0
	)

	if shelter_type == PRESET_NONE:
		structure = t.none_structure_score
	elif is_lean_to:
		structure = t.lean_to_base_structure * (
			t.lean_to_completion_weight * completion
			+ t.lean_to_brace_weight * brace_ratio
		) + t.structure_wood_bonus * brace_ratio - slope_penalty
		structure = clampf(structure, 0.0, 1.0)
	else:
		var min_depth := _preset_min_depth(shelter_type, t)

		if shelter_type == PRESET_SNOW_TRENCH:
			if snow_depth < t.snow_depth_trench_standard_m:
				if snow_depth >= t.snow_depth_trench_wall_min_m:
					if has_snow_wall:
						wall_variant = true
						min_depth = t.snow_depth_trench_wall_min_m
					else:
						missing_wall = true
				else:
					invalid_depth = true
		elif snow_depth < min_depth:
			invalid_depth = true

		var depth_margin := clampf(
			(snow_depth - min_depth) / maxf(t.structure_depth_margin_range_m, 0.001) + 0.5,
			0.0,
			1.0
		)
		var roof_quality := _roof_quality(roof_thickness, t)
		structure = _preset_base_structure(shelter_type, t) * (
			t.structure_depth_weight * depth_margin
			+ t.structure_roof_weight * roof_quality
			+ t.structure_completion_weight * completion
		) + t.structure_wood_bonus * brace_ratio - slope_penalty

		if invalid_depth:
			structure = minf(structure, t.structure_invalid_depth_cap)
		elif missing_wall:
			structure = minf(structure, t.structure_missing_wall_cap)
		structure = clampf(structure, 0.0, 1.0)

	# ---------------------------------------------------------------- Insulation
	var insulation := clampf(
		lerpf(t.insulation_bare_score, t.insulation_full_score, bedding_quality),
		0.0,
		1.0
	)

	# ---------------------------------------------------------------- Isolation
	var isolation := t.isolation_none_base
	if shelter_type == PRESET_RAISED_CAVE:
		isolation = t.isolation_raised_cave_base
	elif shelter_type == PRESET_BASIC_CAVE:
		isolation = t.isolation_basic_cave_base
	elif shelter_type == PRESET_SNOW_TRENCH:
		isolation = t.isolation_snow_trench_base
	elif shelter_type == PRESET_LEAN_TO:
		isolation = t.isolation_lean_to_base
	if is_snow:
		if has_cold_pit:
			isolation += t.isolation_cold_pit_bonus
		if has_raised_bed:
			isolation += t.isolation_raised_bed_bonus
	isolation = clampf(isolation, 0.0, 1.0)

	# ---------------------------------------------------------------- Air
	var air := t.air_open_score
	if is_snow:
		if vent_count <= 0:
			air = t.air_no_vent_score
		elif vent_count == 1:
			air = t.air_one_vent_score
		elif vent_count == 2:
			air = t.air_two_vent_score - windward * t.air_two_vent_windward_penalty
		else:
			air = maxf(
				t.air_over_vent_floor,
				t.air_two_vent_score - float(vent_count - 2) * t.air_over_vent_step
			)
		if vent_clogged and vent_count > 0:
			air = minf(air, t.air_clogged_cap)
	air = clampf(air, 0.0, 1.0)

	# ---------------------------------------------------------------- Heat
	var heat := 0.0
	var chill_c := night_temp
	var fire_ignored := false
	var effective_fire_held := fire_held and fire_exposure <= t.fire_blowout_dot
	var fire_reaches_dawn := false
	var fire_burn_hours := 0.0
	var fire_out_clock := ""

	if is_snow:
		# 雪庇护所：火焰输入一律忽略，只有 prewarmed 修正入夜状态。
		fire_ignored = fire_lit
		var heat_reference := _heat_reference_depth(shelter_type, t)
		var wall_thickness := clampf(
			snow_depth / maxf(t.heat_wall_min_reference_m, heat_reference),
			0.0,
			t.heat_wall_thickness_max
		)
		var volume := _preset_volume(shelter_type, t)
		var volume_penalty := clampf(
			(volume - t.heat_volume_free_m3) / maxf(t.heat_volume_span_m3, 0.001),
			0.0,
			1.0
		) * t.heat_volume_penalty
		var wind_factor := t.heat_wind_factor_base + t.heat_wind_factor_scale * site
		heat = _preset_base_thermal(shelter_type, t) * (
			t.heat_wall_factor_base + t.heat_wall_factor_scale * wall_thickness
		) * (1.0 - volume_penalty) * wind_factor
		chill_c = night_temp - wind_speed * t.wind_chill_per_kmh * (
			1.0 - site * t.heat_wind_chill_site_reduction
		)
		heat -= clampf(
			(-chill_c - t.heat_chill_start_c) / maxf(t.heat_chill_range_c, 0.001),
			0.0,
			1.0
		) * t.heat_chill_penalty
		if prewarmed:
			heat += t.prewarm_heat_bonus
	elif is_lean_to:
		var burn_ratio := clampf(fuel_hours / night_hours, 0.0, 1.0)
		if fire_lit:
			if effective_fire_held:
				fire_burn_hours = minf(fuel_hours, night_hours)
				fire_reaches_dawn = fuel_hours >= night_hours
				var lee_factor := t.heat_wind_factor_base + t.heat_wind_factor_scale * (
					1.0 - fire_exposure
				)
				var fire_value := t.fire_thermal_bonus * lee_factor
				if has_reflector_wall:
					fire_value += t.fire_reflector_wall_bonus
				heat = t.heat_lean_to_base + fire_value * burn_ratio
				if not fire_reaches_dawn:
					fire_out_clock = _format_clock(
						t.night_minutes + int(round(fuel_hours * 60.0))
					)
			else:
				heat = t.heat_lean_to_base + (
					t.fire_thermal_bonus * t.fire_blowout_fuel_factor
				)
		else:
			heat = t.heat_lean_to_base
	else:
		# None（以及未知预设）：没有保温形制。
		heat = t.heat_none_base
		if prewarmed:
			heat += t.prewarm_heat_bonus
	heat = clampf(heat, 0.0, 1.0)

	# ---------------------------------------------------------------- 六维评分
	var scores := {
		"site": _pct(site),
		"structure": _pct(structure),
		"insulation": _pct(insulation),
		"isolation": _pct(isolation),
		"air": _pct(air),
		"heat": _pct(heat),
	}

	var weight_sum := (
		t.weight_site + t.weight_structure + t.weight_insulation
		+ t.weight_isolation + t.weight_air + t.weight_heat
	)
	var weighted_average := (
		float(scores["site"]) * t.weight_site
		+ float(scores["structure"]) * t.weight_structure
		+ float(scores["insulation"]) * t.weight_insulation
		+ float(scores["isolation"]) * t.weight_isolation
		+ float(scores["air"]) * t.weight_air
		+ float(scores["heat"]) * t.weight_heat
	) / maxf(weight_sum, 0.001)

	var min_key: String = "site"
	var min_score: int = int(scores["site"])
	for key in SCORE_KEYS:
		var axis_score: int = int(scores[key])
		if axis_score < min_score:
			min_score = axis_score
			min_key = str(key)

	# ---------------------------------------------------------------- 结论
	var outcome := OUTCOME_COLD
	var outcome_title := "SURVIVED HYPOTHERMIC (轻度失温熬过)"
	if float(scores["air"]) < t.air_suffocation_threshold:
		outcome = OUTCOME_DANGEROUS
		outcome_title = "SUFFOCATED (窒息)"
	elif (
		float(scores["insulation"]) < t.insulation_hypothermia_threshold
		or float(scores["site"]) < t.site_hypothermia_threshold
		or float(scores["heat"]) < t.heat_hypothermia_threshold
	):
		outcome = OUTCOME_DANGEROUS
		outcome_title = "PERISHED IN FROST (严重失温致死)"
	elif float(min_score) < t.cold_min_axis:
		outcome = OUTCOME_DANGEROUS
		outcome_title = "SHELTER FAILED (庇护所失效)"
	elif float(min_score) >= t.safe_min_axis and weighted_average >= t.safe_min_weighted_average:
		outcome = OUTCOME_SAFE
		outcome_title = "SURVIVED COZY (舒适安全过夜)"

	# ---------------------------------------------------------------- 归因
	var notes: Array[String] = []
	notes.append(_site_note(
		shelter_type, wind_angle_diff, wind_speed, site, is_lean_to, t
	))
	notes.append(_structure_note(
		shelter_type, known_preset, wall_variant, invalid_depth, missing_wall,
		snow_depth, roof_thickness, completion, structure, _min_depth_for_note(shelter_type, t),
		wood_left, t
	))
	notes.append(_insulation_note(bedding_quality, t))
	notes.append(_isolation_note(
		shelter_type, has_cold_pit, has_raised_bed, isolation
	))
	notes.append(_air_note(shelter_type, vent_count, vent_clogged, is_snow))
	notes.append(_heat_note(
		is_snow, is_lean_to, fire_lit, effective_fire_held,
		fire_exposure, fuel_hours, night_hours, fire_reaches_dawn, fire_out_clock,
		fire_ignored, prewarmed, has_reflector_wall, snow_depth, t
	))

	var details := {
		"preset": shelter_type,
		"unknown_preset": not known_preset,
		"wall_variant": wall_variant,
		"invalid_snow_depth": invalid_depth,
		"missing_snow_wall": missing_wall,
		"weighted_average": weighted_average,
		"min_axis": min_key,
		"min_score": min_score,
		"fire_ignored_in_snow_shelter": fire_ignored,
		"fire_reaches_dawn": fire_reaches_dawn,
		"fire_burn_hours": fire_burn_hours,
		"fire_out_clock": fire_out_clock,
		"fuel_hours": fuel_hours,
		"night_hours": night_hours,
		"chill_c": chill_c,
	}

	return {
		"scores": scores,
		"notes": notes,
		"outcome": outcome,
		"outcome_title": outcome_title,
		"details": details,
	}


# -----------------------------------------------------------------------------
# 归因文案
# -----------------------------------------------------------------------------

static func _site_note(
	shelter_type: String,
	wind_angle_diff: float,
	wind_speed: float,
	_site: float,
	is_lean_to: bool,
	t: Tuning
) -> String:
	if shelter_type == PRESET_NONE:
		return "露天没有挡风结构，夜间 %.0f km/h 主风直接吹拂，风寒最重。" % wind_speed

	var opening := "棚口" if is_lean_to else "入口"
	if wind_angle_diff < t.windward_entrance_angle_deg:
		return "夜间主风 %.0f km/h，%s与主风向只差 %.0f°，正迎风造成穿堂风与积雪倒灌。" % [
			wind_speed, opening, wind_angle_diff
		]
	if wind_angle_diff < t.lee_entrance_angle_deg:
		return "夜间主风 %.0f km/h，%s与主风向夹角 %.0f°，侧风偶尔切入，风冷渗透中等。" % [
			wind_speed, opening, wind_angle_diff
		]
	return "夜间主风 %.0f km/h，%s背对主风（夹角 %.0f°），主体处在背风侧，风冷侵入很小。" % [
		wind_speed, opening, wind_angle_diff
	]


static func _structure_note(
	shelter_type: String,
	known_preset: bool,
	wall_variant: bool,
	invalid_depth: bool,
	missing_wall: bool,
	snow_depth: float,
	roof_thickness: float,
	completion: float,
	_structure: float,
	min_depth: float,
	wood_left: float,
	t: Tuning
) -> String:
	if shelter_type == PRESET_NONE:
		if not known_preset:
			return "未知庇护所类型按 None 结算，没有承重结构，直接暴露在风雪中。"
		return "未选择庇护所（None），没有承重结构，直接暴露在风雪中。"

	if shelter_type == PRESET_LEAN_TO:
		var lean_note := "木架完工度 %.0f%%、支撑木 %d 根，棚背与骨架%s。" % [
			completion * 100.0,
			int(round(wood_left)),
			"完整" if completion >= t.completion_note_threshold else "仍在赶工"
		]
		if completion < t.completion_note_threshold:
			lean_note += " 完工度不足 %.0f%%，覆盖与反射墙未收尾。" % (
				t.completion_note_threshold * 100.0
			)
		return lean_note

	var label := _preset_label(shelter_type)
	if invalid_depth:
		return "雪深 %.2f m 低于%s要求的 %.2f m 门槛，结构无法成立。" % [
			snow_depth, label, min_depth
		]
	if wall_variant:
		return "雪深仅 %.2f m（%.1f–%.1f m 浅雪区），用切下的雪块砌墙补足高度，顶厚 %.2f m，结构勉强成立。" % [
			snow_depth,
			t.snow_depth_trench_wall_min_m,
			t.snow_depth_trench_wall_max_m,
			roof_thickness,
		]
	if missing_wall:
		return "雪深仅 %.2f m 且未砌墙，沟壁与顶盖难以自承重。" % snow_depth

	var snow_note := ""
	if roof_thickness < t.roof_thickness_min_m:
		snow_note = "顶厚仅 %.2f m（下限 %.2f m），承重与隔热都不足，有塌顶风险。" % [
			roof_thickness, t.roof_thickness_min_m
		]
	elif roof_thickness < t.roof_thickness_good_m:
		snow_note = "顶厚 %.2f m 刚过下限，后半夜体温会削弱穹顶。" % roof_thickness
	else:
		snow_note = "雪深 %.2f m、顶厚 %.2f m，雪深余量与穹顶承重充足。" % [
			snow_depth, roof_thickness
		]
	if completion < t.completion_note_threshold:
		snow_note += " 完工度仅 %.0f%%，入口封堵未完成。" % (completion * 100.0)
	return snow_note


static func _insulation_note(bedding_quality: float, t: Tuning) -> String:
	if bedding_quality <= t.bedding_bare_threshold:
		return "几乎没有垫层，身体直接接触雪面，传导散热迅速抽走核心热量。"
	if bedding_quality >= t.bedding_good_threshold:
		return "铺设了厚实的松针/干草垫层（%.0f%%），切断了冰雪的传导散热。" % (
			bedding_quality * 100.0
		)
	return "垫层单薄（%.0f%%），后半夜被压实后背部结霜，体感寒冷刺骨。" % (
		bedding_quality * 100.0
	)


static func _isolation_note(
	shelter_type: String,
	has_cold_pit: bool,
	has_raised_bed: bool,
	_isolation: float
) -> String:
	if shelter_type == PRESET_RAISED_CAVE:
		if has_cold_pit and has_raised_bed:
			return "高床与冷气坑把睡眠区抬离沉积冷空气，底层冷湖被有效隔离。"
		if has_cold_pit:
			return "挖了冷气坑，但睡床未抬高，重冷空气仍可能漫上睡面。"
		return "高床缺少冷气坑，重冷空气仍会贴着床沿积聚。"
	if shelter_type == PRESET_BASIC_CAVE:
		return "床面与入口同高，冷空气沉在床位附近，冷热分层有限。"
	if shelter_type == PRESET_SNOW_TRENCH:
		return "沟底平铺，缺少冷热分层，冷空气整夜贴着睡垫。"
	if shelter_type == PRESET_LEAN_TO:
		return "开放结构没有冷气池；靠背风地势、垫层与火抵消地面冷空气。"
	return "没有任何隔离，地面冷空气直接包裹身体。"


static func _air_note(
	shelter_type: String,
	vent_count: int,
	vent_clogged: bool,
	is_snow: bool
) -> String:
	if not is_snow and shelter_type != PRESET_NONE:
		return "开放结构通风充分，不存在 CO₂ 积聚问题。"
	if shelter_type == PRESET_NONE:
		return "露天不存在密闭空间，CO₂ 不会积聚，但也留不住热量。"
	if vent_count <= 0:
		return "未设通风管，CO₂ 与湿气在密闭雪洞内积聚，窒息风险致命。"
	if vent_clogged:
		return "通风管被夜间新增降雪部分堵塞，换气受阻，出现缺氧头痛。"
	if vent_count == 1:
		return "单根通风管保持畅通，排出湿气与 CO₂，热损失可控。"
	if vent_count == 2:
		return "两根通风管形成对流，换气充分但会带走一部分热量。"
	return "通风过度，庇护所无法维持稳定的热包络。"


static func _heat_note(
	is_snow: bool,
	is_lean_to: bool,
	fire_lit: bool,
	effective_fire_held: bool,
	fire_exposure: float,
	fuel_hours: float,
	night_hours: float,
	fire_reaches_dawn: bool,
	fire_out_clock: String,
	fire_ignored: bool,
	prewarmed: bool,
	has_reflector_wall: bool,
	snow_depth: float,
	t: Tuning
) -> String:
	if is_snow:
		if fire_ignored:
			return "雪庇护所内禁止明火，fire_lit 输入已忽略；睡前篝火只修正入夜状态（%s），不整夜供热。" % (
				"已暖身" if prewarmed else "未暖身"
			)
		if prewarmed:
			return "睡前篝火只修正入夜状态（pre-warm +%.0f%%），雪洞内不生火，后半夜靠雪体隔热与体温。" % (
				t.prewarm_heat_bonus * 100.0
			)
		return "积雪 %.2f m 的雪体提供主要保温；洞内不生火，整夜仅靠体温与垫层。" % snow_depth

	if is_lean_to:
		if not fire_lit:
			return "没有生火，倒棚整夜只靠体温与垫层，后半夜会明显失温。"
		if not effective_fire_held:
			if fire_exposure > t.fire_blowout_dot:
				return "反射火被迎风阵风吹灭（暴露度 %.2f > 吹灭阈值 %.2f），未能烧到天亮。" % [
					fire_exposure, t.fire_blowout_dot
				]
			return "反射火未能维持到天亮，后半夜熄火。"
		if fire_reaches_dawn:
			var held_note := "反射火可以烧到天亮：备柴 %.1f h ≥ 夜长 %.1f h" % [
				fuel_hours, night_hours
			]
			if has_reflector_wall:
				held_note += "，反射墙把热量送回棚内。"
			else:
				held_note += "，但没有反射墙，热量散失更快。"
			return held_note
		if fuel_hours <= 0.0:
			return "备柴耗尽，入夜时火就熄了，后半夜只能靠体温硬扛。"
		var short_note := "备柴只够烧 %.1f h，约 %s 熄火，后半夜只能靠体温硬扛" % [
			fuel_hours, fire_out_clock
		]
		if has_reflector_wall:
			short_note += "，反射墙只延缓了降温。"
		else:
			short_note += "，也没有反射墙保温。"
		return short_note

	if prewarmed:
		return "睡前篝火暖过身子，但露天（None）没有保温形制，核心热量仍持续散失。"
	return "露天（None）没有任何保温形制，核心热量持续散失。"


# -----------------------------------------------------------------------------
# 预设与评分工具
# -----------------------------------------------------------------------------

static func _resolve_preset(raw: String) -> Dictionary:
	var key := raw.strip_edges().to_lower()
	if key == "raisedcave" or key == "raised_cave" or key == "raised":
		return {"type": PRESET_RAISED_CAVE, "known": true}
	if key == "basiccave" or key == "basic_cave" or key == "basic":
		return {"type": PRESET_BASIC_CAVE, "known": true}
	if key == "snowtrench" or key == "snow_trench" or key == "trench":
		return {"type": PRESET_SNOW_TRENCH, "known": true}
	if key == "leanto" or key == "lean_to" or key == "lean-to":
		return {"type": PRESET_LEAN_TO, "known": true}
	if key == "" or key == "none" or key == "no_shelter":
		return {"type": PRESET_NONE, "known": true}
	return {"type": PRESET_NONE, "known": false}


static func _is_snow_shelter(shelter_type: String) -> bool:
	return (
		shelter_type == PRESET_RAISED_CAVE
		or shelter_type == PRESET_BASIC_CAVE
		or shelter_type == PRESET_SNOW_TRENCH
	)


static func _preset_label(shelter_type: String) -> String:
	if shelter_type == PRESET_RAISED_CAVE:
		return "高床雪洞"
	if shelter_type == PRESET_BASIC_CAVE:
		return "基础雪洞"
	if shelter_type == PRESET_SNOW_TRENCH:
		return "雪沟"
	if shelter_type == PRESET_LEAN_TO:
		return "倒棚"
	return "None"


static func _preset_min_depth(shelter_type: String, t: Tuning) -> float:
	if shelter_type == PRESET_RAISED_CAVE:
		return t.snow_depth_raised_cave_min_m
	if shelter_type == PRESET_BASIC_CAVE:
		return t.snow_depth_cave_min_m
	if shelter_type == PRESET_SNOW_TRENCH:
		return t.snow_depth_trench_standard_m
	return 0.0


static func _heat_reference_depth(shelter_type: String, t: Tuning) -> float:
	if shelter_type == PRESET_SNOW_TRENCH:
		return t.snow_depth_trench_standard_m
	return _preset_min_depth(shelter_type, t)


static func _min_depth_for_note(shelter_type: String, t: Tuning) -> float:
	return _preset_min_depth(shelter_type, t)


static func _preset_wood_cost(shelter_type: String, t: Tuning) -> int:
	if shelter_type == PRESET_RAISED_CAVE:
		return t.raised_cave_wood_cost
	if shelter_type == PRESET_BASIC_CAVE:
		return t.basic_cave_wood_cost
	if shelter_type == PRESET_SNOW_TRENCH:
		return t.snow_trench_wood_cost
	if shelter_type == PRESET_LEAN_TO:
		return t.lean_to_wood_cost
	return 0


static func _preset_base_thermal(shelter_type: String, t: Tuning) -> float:
	if shelter_type == PRESET_RAISED_CAVE:
		return t.raised_cave_base_thermal
	if shelter_type == PRESET_BASIC_CAVE:
		return t.basic_cave_base_thermal
	if shelter_type == PRESET_SNOW_TRENCH:
		return t.snow_trench_base_thermal
	if shelter_type == PRESET_LEAN_TO:
		return t.lean_to_base_thermal
	return 0.0


static func _preset_base_structure(shelter_type: String, t: Tuning) -> float:
	if shelter_type == PRESET_RAISED_CAVE:
		return t.raised_cave_base_structure
	if shelter_type == PRESET_BASIC_CAVE:
		return t.basic_cave_base_structure
	if shelter_type == PRESET_SNOW_TRENCH:
		return t.snow_trench_base_structure
	if shelter_type == PRESET_LEAN_TO:
		return t.lean_to_base_structure
	return 0.0


static func _preset_volume(shelter_type: String, t: Tuning) -> float:
	if shelter_type == PRESET_RAISED_CAVE:
		return t.raised_cave_volume_m3
	if shelter_type == PRESET_BASIC_CAVE:
		return t.basic_cave_volume_m3
	if shelter_type == PRESET_SNOW_TRENCH:
		return t.snow_trench_volume_m3
	if shelter_type == PRESET_LEAN_TO:
		return t.lean_to_volume_m3
	return 0.0


static func _roof_quality(roof_thickness: float, t: Tuning) -> float:
	if roof_thickness >= t.roof_thickness_good_m:
		return 1.0
	if roof_thickness >= t.roof_thickness_min_m:
		var span := maxf(t.roof_thickness_good_m - t.roof_thickness_min_m, 0.001)
		var ratio := (roof_thickness - t.roof_thickness_min_m) / span
		return lerpf(t.roof_quality_at_min, 1.0, clampf(ratio, 0.0, 1.0))
	return clampf(roof_thickness / maxf(t.roof_thickness_min_m, 0.001), 0.0, 1.0) * (
		t.roof_quality_below_min_max
	)


static func _pct(value: float) -> int:
	return int(round(clampf(value, 0.0, 1.0) * 100.0))


static func _format_clock(total_minutes: int) -> String:
	var wrapped := ((total_minutes % MINUTES_PER_DAY) + MINUTES_PER_DAY) % MINUTES_PER_DAY
	return "%02d:%02d" % [int(wrapped / 60.0), wrapped % 60]


static func _input_float(input: Dictionary, key: String, fallback: float) -> float:
	var value: Variant = input.get(key, fallback)
	if value == null:
		return fallback
	return float(value)


static func _input_int(input: Dictionary, key: String, fallback: int) -> int:
	var value: Variant = input.get(key, fallback)
	if value == null:
		return fallback
	return int(value)


static func _input_bool(input: Dictionary, key: String, fallback: bool) -> bool:
	var value: Variant = input.get(key, fallback)
	if value == null:
		return fallback
	return bool(value)


static func _input_string(input: Dictionary, key: String, fallback: String) -> String:
	var value: Variant = input.get(key, fallback)
	if value == null:
		return fallback
	return str(value)


static func _missing_tuning_report() -> Dictionary:
	var scores := {}
	for key in SCORE_KEYS:
		scores[key] = 0
	var notes: Array[String] = []
	for _key in SCORE_KEYS:
		notes.append("缺少 Tuning 调参资源，无法进行夜间结算。")
	return {
		"scores": scores,
		"notes": notes,
		"outcome": OUTCOME_DANGEROUS,
		"outcome_title": "MISSING TUNING (缺少调参资源)",
		"details": {"error": "null_tuning"},
	}
