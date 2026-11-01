class_name Records
extends RefCounted

## 最好记录与关卡进度，存 user://records.cfg。
## - 每种庇护所的最好一夜（结局优先，其次加权均分）：自由模式键 = 庇护所（全天模式加 "@day"）；
##   关卡键 = "L<N>:<庇护所>"（D12 §8.4）。
## - [progress] highest_unlocked（已解锁的最高关；LEVEL_COUNT + 1 = 自由模式已开放）、last_level（上次选的关）。

## 存档路径（测试可改到临时文件）。
static var path: String = "user://records.cfg"
const OUTCOME_RANK := {"DANGEROUS": 0, "COLD": 1, "SAFE": 2}
const PROGRESS := "progress"

static func _cfg() -> ConfigFile:
	var cfg := ConfigFile.new()
	cfg.load(path)
	return cfg

## 记录键：关卡模式（非自由）用 "L<N>:<庇护所>"。
static func key_for(preset: String, level_index: int, full_day: bool) -> String:
	if level_index >= 1:
		return "L%d:%s" % [level_index, preset]
	return preset + ("@day" if full_day else "")

static func save(key: String, outcome: String, score: int) -> void:
	var cfg := _cfg()
	var best_o := String(cfg.get_value(key, "outcome", ""))
	var best_s := int(cfg.get_value(key, "score", -1))
	var better: bool = best_o == "" or OUTCOME_RANK.get(outcome, 0) > OUTCOME_RANK.get(best_o, 0) \
		or (outcome == best_o and score > best_s)
	cfg.set_value(key, "nights", int(cfg.get_value(key, "nights", 0)) + 1)
	if better:
		cfg.set_value(key, "outcome", outcome)
		cfg.set_value(key, "score", score)
	cfg.save(path)

# ------------------------------------------------------------------ 关卡进度

## 已解锁的最高关（新存档 = 1）。开发参数 --unlock-all 视为全部解锁（不写盘）。
static func highest_unlocked() -> int:
	if "--unlock-all" in OS.get_cmdline_user_args():
		return LevelState.LEVEL_COUNT + 1
	return maxi(int(_cfg().get_value(PROGRESS, "highest_unlocked", 1)), 1)

## 记一局关卡结果；返回新的最高解锁关（规则见 LevelState.unlocked_after）。
static func record_level_result(level_index: int, outcome: String) -> int:
	var cfg := _cfg()
	var before := maxi(int(cfg.get_value(PROGRESS, "highest_unlocked", 1)), 1)
	var after := LevelState.unlocked_after(before, level_index, outcome)
	if after != before:
		cfg.set_value(PROGRESS, "highest_unlocked", after)
		cfg.save(path)
	return after

static func last_level() -> int:
	return int(_cfg().get_value(PROGRESS, "last_level", 1))

static func set_last_level(index: int) -> void:
	var cfg := _cfg()
	cfg.set_value(PROGRESS, "last_level", index)
	cfg.save(path)

## 开局默认关：上次选的关（若仍解锁），否则已解锁的最高关（最多第 5 关）。
static func default_level() -> int:
	var hi := highest_unlocked()
	var last := last_level()
	if LevelState.is_unlocked(last, hi):
		return last
	return clampi(hi, 1, LevelState.LEVEL_COUNT)

# ------------------------------------------------------------------ 显示

static func _names() -> Dictionary:
	return {"RaisedCave": Loc.t("Raised cave"), "BasicCave": Loc.t("Snow cave"), "SnowTrench": Loc.t("Trench"), "LeanTo": Loc.t("Lean-to"), "None": Loc.t("No shelter")}

## 自由模式：每种庇护所的最好一夜。
static func text() -> String:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return ""
	var names := _names()
	var parts: Array[String] = []
	for k in names:
		if cfg.has_section(k):
			parts.append("%s: %s" % [names[k], cfg.get_value(k, "outcome", "—")])
	return Loc.t("Your best nights — ") + "   ·   ".join(parts) if not parts.is_empty() else ""

## 某一关的最好一夜（"" = 还没玩过）。
static func level_best(level_index: int) -> String:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return ""
	var names := _names()
	var best_k := ""
	var best_o := ""
	var best_s := -1
	for k in names:
		var sec := "L%d:%s" % [level_index, k]
		if not cfg.has_section(sec):
			continue
		var o := String(cfg.get_value(sec, "outcome", ""))
		var s := int(cfg.get_value(sec, "score", -1))
		if best_k == "" or OUTCOME_RANK.get(o, 0) > OUTCOME_RANK.get(best_o, 0) or (o == best_o and s > best_s):
			best_k = k
			best_o = o
			best_s = s
	if best_k == "":
		return ""
	return Loc.t("Best on this level: %s (%s)") % [best_o, names[best_k]]
