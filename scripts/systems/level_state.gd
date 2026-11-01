class_name LevelState
extends RefCounted

## D12 当前关卡与本局抽取结果（静态，生命周期同 TerrainHeight.SEED）。
## 必须在重载 main.tscn 之前调用 begin()：地形、雪深、森林、资源都在 _ready 时读取。
## 抽取只依赖 (关卡, 种子)，同一组合永远得到同一局（简报页与会话日志显示种子）。

const LEVEL_PATHS := [
	"res://resources/levels/level_free.tres",
	"res://resources/levels/level_01.tres",
	"res://resources/levels/level_02.tres",
	"res://resources/levels/level_03.tres",
	"res://resources/levels/level_04.tres",
	"res://resources/levels/level_05.tres",
]
## 关卡数（不含自由模式）。
const LEVEL_COUNT := 5
## [GAME] 解锁下一关所需结局（CORE_GAMEPLAY §8.4）。
const UNLOCK_OUTCOMES := ["SAFE", "COLD"]
## 种子范围：6 位以内，方便玩家抄写复现。
const SEED_MAX := 999999

static var level: LevelDef
static var game_seed: int = 0
## 本局抽取：valley_seed / wind_rotation_deg / weather / snow_depth_scale / start_minutes / wind_speed_offset_kmh / snow_patchiness / snag_density_scale
static var roll: Dictionary = {}

## 是否在关卡模式（已调用 begin）。未进入时游戏保持旧行为：山谷按重开轮换、天气按 Tuning 抽取。
static func active() -> bool:
	return level != null

## 场景加载前调用（MainLevel._init）：把本局抽取写进地形 / 雪深的静态旋钮。
## 未进入关卡时只把雪深旋钮复位，不碰 TerrainHeight.SEED（保留旧的山谷轮换）。
static func apply_world() -> void:
	if not active():
		TerrainHeight.SNOW_SCALE = 1.0
		TerrainHeight.SNOW_PATCHINESS = 0.0
		return
	TerrainHeight.SEED = int(roll.get("valley_seed", TerrainHeight.SEED))
	TerrainHeight.SNOW_SCALE = float(roll.get("snow_depth_scale", 1.0))
	TerrainHeight.SNOW_PATCHINESS = float(roll.get("snow_patchiness", 0.0))

## 立枯木密度倍率（ForestScatter / ResourceSpawner 读取）。
static func snag_density_scale() -> float:
	return float(roll.get("snag_density_scale", 1.0)) if active() else 1.0

## 退出关卡模式（测试用；回到旧行为）。
static func reset() -> void:
	level = null
	game_seed = 0
	roll = {}
	apply_world()

static func load_level(index: int) -> LevelDef:
	if index < 0 or index > LEVEL_COUNT:
		return null
	return load(LEVEL_PATHS[index]) as LevelDef

## 进入一局：seed < 0 时随机生成。返回抽取结果。
static func begin(index: int, p_seed: int = -1) -> Dictionary:
	level = load_level(index)
	if level == null:
		level = load_level(0)
	game_seed = p_seed if p_seed >= 0 else randi_range(1, SEED_MAX)
	roll = roll_for(level, game_seed)
	return roll

## 纯函数：同一 (def, seed) 永远返回同一结果。
static func roll_for(def: LevelDef, p_seed: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([def.index, p_seed])
	var valleys: Array = Array(def.valley_seeds) if not def.valley_seeds.is_empty() else TerrainHeight.VALLEY_SEEDS
	var valley: int = valleys[rng.randi_range(0, valleys.size() - 1)]
	var rots := def.wind_rotation_choices_deg
	var rot := rots[rng.randi_range(0, rots.size() - 1)] if not rots.is_empty() else 0.0
	rot += rng.randf_range(-def.wind_jitter_deg, def.wind_jitter_deg)
	var scales := def.snow_depth_scale_choices
	var depth_scale := scales[rng.randi_range(0, scales.size() - 1)] if not scales.is_empty() else 1.0
	return {
		"valley_seed": valley,
		"wind_rotation_deg": fposmod(rot, 360.0),
		"weather": _pick_weather(def, rng.randf()),
		"snow_depth_scale": depth_scale,
		"snow_patchiness": def.snow_patchiness,
		"snag_density_scale": def.snag_density_scale,
		"start_minutes": def.start_minutes,
		"wind_speed_offset_kmh": def.wind_speed_offset_kmh,
	}

static func _pick_weather(def: LevelDef, r01: float) -> String:
	var c := maxf(def.weather_weight_clear, 0.0)
	var o := maxf(def.weather_weight_overcast, 0.0)
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

## 命令行：--level=N（0 或 free = 自由模式）、--seed=S。缺省返回 -1。
static func parse_args(args: PackedStringArray) -> Dictionary:
	var out := {"level": -1, "seed": -1}
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
	return out

static func unlocks_next(outcome: String) -> bool:
	return outcome in UNLOCK_OUTCOMES

## 解锁规则：给定已解锁的最高关与本局（关卡, 结局），返回新的最高关。
## 自由模式在通过第 5 关后开放，用 LEVEL_COUNT + 1 表示。
static func unlocked_after(highest_unlocked: int, played_index: int, outcome: String) -> int:
	if played_index <= 0 or not unlocks_next(outcome):
		return highest_unlocked
	return maxi(highest_unlocked, played_index + 1)

static func is_unlocked(index: int, highest_unlocked: int) -> bool:
	if index == 0:
		return highest_unlocked > LEVEL_COUNT
	return index >= 1 and index <= maxi(highest_unlocked, 1)
