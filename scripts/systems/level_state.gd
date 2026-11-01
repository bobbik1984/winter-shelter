class_name LevelState
extends RefCounted

## D12 / D13 当前章节、阶与本局抽取结果（静态，生命周期同 TerrainHeight.SEED）。
## 必须在重载 main.tscn 之前调用 begin()：地形、雪深、森林、资源都在 _ready 时读取。
## 结构：5 章 × 10 阶（CORE_GAMEPLAY §9.1）。每阶默认一张固定的图：种子 = f(章, 阶, 第 k 张图)，
## 玩家在简报页按 [N] 才换第 k+1 张。抽取只依赖 (章, 种子, 阶)，同一组合永远得到同一局。

const LEVEL_PATHS := [
	"res://resources/levels/level_free.tres",
	"res://resources/levels/level_01.tres",
	"res://resources/levels/level_02.tres",
	"res://resources/levels/level_03.tres",
	"res://resources/levels/level_04.tres",
	"res://resources/levels/level_05.tres",
]
## 章数（不含自由模式）。历史原因叫 LEVEL_COUNT：一章 = 原 D12 的一关。
const LEVEL_COUNT := 5
## 每章的阶数；通过本章第 CHAPTER_GATE_STAGE 阶开放下一章（用户定，D13）。
const STAGES := 10
const CHAPTER_GATE_STAGE := 5
## [GAME] 解锁所需结局（CORE_GAMEPLAY §8.4）。
const UNLOCK_OUTCOMES := ["SAFE", "COLD"]
## 种子范围：6 位以内，方便玩家抄写复现。
const SEED_MAX := 999999

## 真实游戏启动时自动进入关卡模式（MainLevel._init）。测试工具设为 false 以保留固定基准（山谷 7、不旋转、天气按 Tuning）。
static var auto_begin: bool = true
## 章节选择顺序（自由模式排最后）。
const ORDER := [1, 2, 3, 4, 5, 0]

static var level: LevelDef
static var stage: int = 1
static var map_index: int = 0
static var game_seed: int = 0
## 本局抽取（见 roll_for）。
static var roll: Dictionary = {}

static func active() -> bool:
	return level != null

## 第几阶的难度 0..1（第 1 阶 = 0，第 10 阶 = 1）。
static func difficulty_of(p_stage: int) -> float:
	return clampf(float(p_stage - 1) / float(STAGES - 1), 0.0, 1.0)

static func difficulty() -> float:
	return difficulty_of(stage) if active() else 0.0

## 全局阶号 1..50（自由模式 = 0）。
static func global_stage(ch: int = -1, st: int = -1) -> int:
	var c := ch if ch >= 0 else (level.index if active() else 0)
	var s := st if st >= 0 else stage
	return 0 if c <= 0 else (c - 1) * STAGES + s

## 每阶第 k 张图的种子（确定性）。
static func stage_seed(ch: int, st: int, k: int) -> int:
	return posmod(hash([ch, st, k, 7919]), SEED_MAX) + 1

## 场景加载前调用（MainLevel._init）：把本局抽取写进地形 / 雪深 / 布局的静态旋钮。
## 未进入关卡时全部复位，不碰 TerrainHeight.SEED（保留旧的山谷轮换）。
static func apply_world() -> void:
	if not active():
		TerrainHeight.SNOW_SCALE = 1.0
		TerrainHeight.SNOW_PATCHINESS = 0.0
		TerrainHeight.ROTATION_DEG = 0.0
		TerrainHeight.RECIPE = TerrainRecipe.new()
		MapLayout.DIFFICULTY = 0.0
		MapLayout.ROOTBALL_BONUS = 0
		return
	TerrainHeight.SEED = int(roll.get("valley_seed", TerrainHeight.SEED))
	TerrainHeight.SNOW_SCALE = float(roll.get("snow_depth_scale", 1.0))
	TerrainHeight.SNOW_PATCHINESS = float(roll.get("snow_patchiness", 0.0))
	TerrainHeight.ROTATION_DEG = float(roll.get("wind_rotation_deg", 0.0))
	TerrainHeight.RECIPE = roll.get("recipe", TerrainRecipe.new())
	MapLayout.DIFFICULTY = float(roll.get("difficulty", 0.0))
	MapLayout.ROOTBALL_BONUS = int(roll.get("rootball_bonus", 0))

## 立枯木密度倍率（ForestScatter / ResourceSpawner 读取）。
static func snag_density_scale() -> float:
	return float(roll.get("snag_density_scale", 1.0)) if active() else 1.0

## 本局目标路线。"自己判断"的章节（storm_mix）按**本图实测雪深**选，只在玩家能用的庇护所里选：
## 高床雪洞深度 ≥ 2% 图面 → 高床雪洞；雪洞深度 ≥ 2% → 雪洞；雪沟深度 ≥ 50% → 雪沟；否则倒棚。
## 其它章节 = 本章写定的目标。
const TARGET_MIN_FRACTION := 0.02

static func target_presets() -> PackedStringArray:
	if not active():
		return PackedStringArray()
	if level.theme != "storm_mix":
		return level.target_presets
	var f := SnowField.map_facts(load("res://resources/tuning.tres") as Tuning)
	var avail := available_presets(Records.learned_shelters())
	var ranked: Array[String] = []
	if float(f["frac_raised"]) >= TARGET_MIN_FRACTION: ranked.append("RaisedCave")
	if float(f["frac_cave"]) >= TARGET_MIN_FRACTION: ranked.append("BasicCave")
	if float(f["frac_trench"]) >= 0.5: ranked.append("SnowTrench")
	ranked.append("LeanTo")
	for p in ranked:
		if p in avail:
			return PackedStringArray([p])
	return PackedStringArray([ranked[0]])

## 建造面板可用的庇护所 = 已学会 ∪ 本章引入（按 BuildMode.PRESETS 顺序）。不在关卡模式时全部可用。
static func available_presets(learned: PackedStringArray) -> PackedStringArray:
	if not active():
		return PackedStringArray(BuildMode.PRESETS)
	var out := PackedStringArray()
	for p in BuildMode.PRESETS:
		if p in learned or p in level.introduced_presets:
			out.append(p)
	return out

## 本局装备。不在关卡模式时 = 旧默认（雪铲 + 保暖层，无防潮垫，空背包）。
static func gear() -> Dictionary:
	if not active():
		return {"shovel": true, "pot": true, "layer": true, "pad": false, "hides": false, "wood": 0, "bark": 0, "bedding": 0}
	return {"shovel": level.has_shovel, "pot": level.has_pot, "layer": level.has_extra_layer, "pad": level.has_sleeping_pad,
		"hides": level.has_hides, "wood": level.start_wood, "bark": level.start_bark, "bedding": level.start_bedding}

## 退出关卡模式（测试用；回到旧行为）。
static func reset() -> void:
	level = null
	stage = 1
	map_index = 0
	game_seed = 0
	roll = {}
	apply_world()

static func load_level(index: int) -> LevelDef:
	if index < 0 or index > LEVEL_COUNT:
		return null
	return load(LEVEL_PATHS[index]) as LevelDef

## 进入一局：章 index、阶 p_stage、第 p_map 张图。p_seed < 0 时用该阶第 p_map 张图的固定种子。
static func begin(index: int, p_seed: int = -1, p_stage: int = 1, p_map: int = 0) -> Dictionary:
	level = load_level(index)
	if level == null:
		level = load_level(0)
	stage = clampi(p_stage, 1, STAGES)
	map_index = maxi(p_map, 0)
	game_seed = p_seed if p_seed >= 0 else stage_seed(level.index, stage, map_index)
	roll = roll_for(level, game_seed, difficulty_of(stage))
	return roll

## 纯函数：同一 (def, seed, 难度) 永远返回同一结果。
static func roll_for(def: LevelDef, p_seed: int, d: float = 0.0) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([def.index, p_seed])
	var valleys: Array = Array(def.valley_seeds) if not def.valley_seeds.is_empty() else TerrainHeight.VALLEY_SEEDS
	var valley: int = valleys[rng.randi_range(0, valleys.size() - 1)]
	var rots := def.wind_rotation_choices_deg
	var rot := rots[rng.randi_range(0, rots.size() - 1)] if not rots.is_empty() else 0.0
	rot += rng.randf_range(-def.wind_jitter_deg, def.wind_jitter_deg)
	var scales := def.snow_depth_scale_choices
	var depth_scale := scales[rng.randi_range(0, scales.size() - 1)] if not scales.is_empty() else 1.0
	var weather := _pick_weather(def, rng.randf(), d)
	# 地形配方（D13 §9.4）：形态从本章候选里抽；起伏 / 树密度按难度插值；形态参数在预设附近抖动
	var shapes := def.shape_choices if not def.shape_choices.is_empty() else PackedStringArray(["ridge_valley"])
	var shape: String = shapes[rng.randi_range(0, shapes.size() - 1)]
	var recipe := TerrainRecipe.preset(shape) if shape != "ridge_valley" else TerrainRecipe.new()
	recipe.roughness = lerpf(def.roughness, def.roughness_hard, d) * (recipe.roughness if shape != "ridge_valley" else 1.0)
	recipe.tree_density = lerpf(def.tree_density, def.tree_density_hard, d) * (recipe.tree_density if shape != "ridge_valley" else 1.0)
	if def.feature_jitter > 0.0:
		recipe.feature_i += rng.randf_range(-3.0, 3.0) * def.feature_jitter
		recipe.feature_h *= 1.0 + rng.randf_range(-0.15, 0.15) * def.feature_jitter
	return {
		"valley_seed": valley,
		"wind_rotation_deg": fposmod(rot, 360.0),
		"weather": weather,
		"snow_depth_scale": depth_scale,
		"snow_patchiness": lerpf(def.snow_patchiness, def.snow_patchiness_hard, d),
		"snag_density_scale": lerpf(def.snag_density_scale, def.snag_density_scale_hard, d),
		"start_minutes": start_minutes_for(def, d),
		"wind_speed_offset_kmh": lerpf(def.wind_speed_offset_kmh, def.wind_speed_offset_kmh_hard, d),
		"night_temp_offset_c": lerpf(def.night_temp_offset_c, def.night_temp_offset_c_hard, d),
		"rootball_bonus": int(round(lerpf(float(def.rootball_bonus), float(def.rootball_bonus_hard), d))),
		"difficulty": d,
		"recipe": recipe,
	}

## 开局时刻：第 1 阶 = start_minutes；若设了 start_minutes_stage2，则第 2 → 10 阶从它线性到 start_minutes_hard。
static func start_minutes_for(def: LevelDef, d: float) -> int:
	var d2 := difficulty_of(2)
	if def.start_minutes_stage2 >= 0 and d >= d2 - 0.0001:
		var k := clampf((d - d2) / (1.0 - d2), 0.0, 1.0)
		return int(round(lerpf(float(def.start_minutes_stage2), float(def.start_minutes_hard), k)))
	return int(round(lerpf(float(def.start_minutes), float(def.start_minutes_hard), d)))

static func _pick_weather(def: LevelDef, r01: float, d: float = 0.0) -> String:
	var c := maxf(def.weather_weight_clear, 0.0)
	var o := maxf(def.weather_weight_overcast + def.overcast_bonus_hard * d, 0.0)
	var s := maxf(def.weather_weight_storm, 0.0)
	var total := c + o + s
	if total <= 0.0:
		return "clear"
	var r := r01 * total
	if r < c:
		return "clear"
	if r < c + o:
		return "overcast"
	return "storm"

## 命令行：--level=N（章；0 或 free = 自由模式）、--stage=S（1..10）、--seed=S。缺省返回 -1。
static func parse_args(args: PackedStringArray) -> Dictionary:
	var out := {"level": -1, "seed": -1, "stage": -1}
	for a in args:
		if a.begins_with("--level="):
			var v := a.substr(8)
			if v == "free":
				out["level"] = 0
			elif v.is_valid_int() and int(v) >= 0 and int(v) <= LEVEL_COUNT:
				out["level"] = int(v)
		elif a.begins_with("--seed="):
			var sv := a.substr(7)
			if sv.is_valid_int() and int(sv) >= 0:
				out["seed"] = int(sv)
		elif a.begins_with("--stage="):
			var st := a.substr(8)
			if st.is_valid_int() and int(st) >= 1 and int(st) <= STAGES:
				out["stage"] = int(st)
	return out

static func unlocks_next(outcome: String) -> bool:
	return outcome in UNLOCK_OUTCOMES

## 解锁规则（纯函数）：在第 ch 章第 st 阶拿到 outcome 后开放什么。
## 返回 {stage: 本章新开放的阶（0 = 无）, chapter: 新开放的章（0 = 无）, free: 是否开放自由模式}。
static func unlocks_after(ch: int, st: int, outcome: String) -> Dictionary:
	var out := {"stage": 0, "chapter": 0, "free": false}
	if ch < 1 or not unlocks_next(outcome):
		return out
	if st < STAGES:
		out["stage"] = st + 1
	if st >= CHAPTER_GATE_STAGE:
		if ch < LEVEL_COUNT:
			out["chapter"] = ch + 1
		else:
			out["free"] = true
	return out
