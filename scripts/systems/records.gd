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

# ------------------------------------------------------------------ 章节 / 阶进度（D13）

## 记录键：章节模式用 "C<章>-<阶>:<庇护所>"；自由模式沿用旧键（全天模式加 "@day"）。
static func key_for(preset: String, chapter: int, full_day: bool, stage: int = 1) -> String:
	if chapter >= 1:
		return "C%d-%d:%s" % [chapter, stage, preset]
	return preset + ("@day" if full_day else "")

## 每章已开放的最高阶 {章: 阶}，未开放的章不在表里。新存档 = {1: 1}。
## 迁移：旧存档只有 highest_unlocked（D12 的第 N 关）→ 前 N 章各开放第 1 阶；> 5 时自由模式已开放。
static func chapter_progress() -> Dictionary:
	var cfg := _cfg()
	if cfg.has_section_key(PROGRESS, "chapters"):
		return cfg.get_value(PROGRESS, "chapters", {1: 1})
	var hi := maxi(int(cfg.get_value(PROGRESS, "highest_unlocked", 1)), 1)
	var out := {}
	for c in range(1, mini(hi, LevelState.LEVEL_COUNT) + 1):
		out[c] = 1
	return out

static func free_open() -> bool:
	if "--unlock-all" in OS.get_cmdline_user_args():
		return true
	var cfg := _cfg()
	if cfg.has_section_key(PROGRESS, "free_open"):
		return bool(cfg.get_value(PROGRESS, "free_open", false))
	return int(cfg.get_value(PROGRESS, "highest_unlocked", 1)) > LevelState.LEVEL_COUNT

## 第 ch 章最高已开放的阶（0 = 本章未开放）。
static func chapter_highest(ch: int) -> int:
	if "--unlock-all" in OS.get_cmdline_user_args():
		return LevelState.STAGES
	return int(chapter_progress().get(ch, 0))

static func stage_unlocked(ch: int, st: int) -> bool:
	if ch == 0:
		return free_open()
	return st >= 1 and st <= chapter_highest(ch)

## 记一局章节结果；返回新开放的内容 {stage, chapter, free}（只含这次新开放的）。
static func record_stage_result(ch: int, st: int, outcome: String) -> Dictionary:
	var u := LevelState.unlocks_after(ch, st, outcome)
	var news := {"stage": 0, "chapter": 0, "free": false}
	if ch < 1:
		return news
	var prog := chapter_progress()
	var cfg := _cfg()
	if int(u["stage"]) > int(prog.get(ch, 0)):
		prog[ch] = int(u["stage"])
		news["stage"] = int(u["stage"])
	if int(u["chapter"]) > 0 and not prog.has(int(u["chapter"])):
		prog[int(u["chapter"])] = 1
		news["chapter"] = int(u["chapter"])
	if bool(u["free"]) and not free_open():
		cfg.set_value(PROGRESS, "free_open", true)
		news["free"] = true
	cfg.set_value(PROGRESS, "chapters", prog)
	cfg.save(path)
	return news

## 每阶"第 k 张图"（用户按 [N] 换新图时 +1）。
static func map_index(ch: int, st: int) -> int:
	return int(_cfg().get_value("maps", "%d-%d" % [ch, st], 0))

static func next_map(ch: int, st: int) -> int:
	var cfg := _cfg()
	var k := int(cfg.get_value("maps", "%d-%d" % [ch, st], 0)) + 1
	cfg.set_value("maps", "%d-%d" % [ch, st], k)
	cfg.save(path)
	return k

static func last_selection() -> Vector2i:
	var cfg := _cfg()
	if cfg.has_section_key(PROGRESS, "last_stage"):
		return cfg.get_value(PROGRESS, "last_stage", Vector2i(1, 1))
	return Vector2i(int(cfg.get_value(PROGRESS, "last_level", 1)), 1)

static func set_last_selection(ch: int, st: int) -> void:
	var cfg := _cfg()
	cfg.set_value(PROGRESS, "last_stage", Vector2i(ch, st))
	cfg.save(path)

## 开局默认：上次选的章 / 阶（仍开放），否则第 1 章第 1 阶。
static func default_selection() -> Vector2i:
	var last := last_selection()
	if stage_unlocked(last.x, maxi(last.y, 1)):
		return Vector2i(last.x, maxi(last.y, 1))
	return Vector2i(1, 1)

# ------------------------------------------------------------------ 庇护所学习（D13 §9.2）

## [GAME] 新存档就会的庇护所：雪沟（现实中有雪铲时最快、对地形要求最低的应急雪庇护所）。
const STARTING_SHELTERS := ["SnowTrench"]

static func learned_shelters() -> PackedStringArray:
	if "--unlock-all" in OS.get_cmdline_user_args():
		return PackedStringArray(BuildMode.PRESETS)
	return PackedStringArray(_cfg().get_value(PROGRESS, "learned_shelters", STARTING_SHELTERS))

## 用某种庇护所熬过一夜（COLD / SAFE）= 学会它。返回 true = 这次新学会。
static func learn_shelter(preset: String, outcome: String) -> bool:
	if not LevelState.unlocks_next(outcome) or not (preset in BuildMode.PRESETS):
		return false
	var cfg := _cfg()
	var have := PackedStringArray(cfg.get_value(PROGRESS, "learned_shelters", STARTING_SHELTERS))
	if preset in have:
		return false
	have.append(preset)
	cfg.set_value(PROGRESS, "learned_shelters", have)
	cfg.save(path)
	return true

# ------------------------------------------------------------------ 显示

static func preset_names() -> Dictionary:
	return {"RaisedCave": Loc.t("Raised cave"), "BasicCave": Loc.t("Snow cave"), "SnowTrench": Loc.t("Trench"), "LeanTo": Loc.t("Lean-to"), "TreeWell": Loc.t("Tree well"), "None": Loc.t("No shelter")}

## 自由模式：每种庇护所的最好一夜。
static func text() -> String:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return ""
	var names := preset_names()
	var parts: Array[String] = []
	for k in names:
		if cfg.has_section(k):
			parts.append("%s: %s" % [names[k], cfg.get_value(k, "outcome", "—")])
	return Loc.t("Your best nights — ") + "   ·   ".join(parts) if not parts.is_empty() else ""

## 某一阶的最好一夜（"" = 还没玩过）。
static func stage_best(ch: int, st: int) -> String:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return ""
	var names := preset_names()
	var best_k := ""
	var best_o := ""
	var best_s := -1
	for k in names:
		var sec := "C%d-%d:%s" % [ch, st, k]
		if not cfg.has_section(sec):
			continue
		var o := String(cfg.get_value(sec, "outcome", ""))
		var sc := int(cfg.get_value(sec, "score", -1))
		if best_k == "" or OUTCOME_RANK.get(o, 0) > OUTCOME_RANK.get(best_o, 0) or (o == best_o and sc > best_s):
			best_k = k
			best_o = o
			best_s = sc
	if best_k == "":
		return ""
	return Loc.t("Best on this stage: %s (%s)") % [best_o, names[best_k]]
