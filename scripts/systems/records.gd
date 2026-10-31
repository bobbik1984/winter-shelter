class_name Records
extends RefCounted

## 每种庇护所的最好一夜（结局优先，其次加权均分），存 user://records.cfg，简报页显示。

const RECORDS := "user://records.cfg"
const OUTCOME_RANK := {"DANGEROUS": 0, "COLD": 1, "SAFE": 2}

## 每种庇护所的最好一夜（结局优先，其次加权均分），简报页显示。
static func save(preset: String, outcome: String, score: int) -> void:
	var cfg := ConfigFile.new()
	cfg.load(RECORDS)
	var best_o := String(cfg.get_value(preset, "outcome", ""))
	var best_s := int(cfg.get_value(preset, "score", -1))
	var better: bool = best_o == "" or OUTCOME_RANK.get(outcome, 0) > OUTCOME_RANK.get(best_o, 0) \
		or (outcome == best_o and score > best_s)
	cfg.set_value(preset, "nights", int(cfg.get_value(preset, "nights", 0)) + 1)
	if better:
		cfg.set_value(preset, "outcome", outcome)
		cfg.set_value(preset, "score", score)
	cfg.save(RECORDS)

static func text() -> String:
	var cfg := ConfigFile.new()
	if cfg.load(RECORDS) != OK:
		return ""
	var names := {"RaisedCave": Loc.t("Raised cave"), "BasicCave": Loc.t("Snow cave"), "SnowTrench": Loc.t("Trench"), "LeanTo": Loc.t("Lean-to"), "None": Loc.t("No shelter")}
	var parts: Array[String] = []
	for k in names:
		if cfg.has_section(k):
			parts.append("%s: %s" % [names[k], cfg.get_value(k, "outcome", "—")])
	return Loc.t("Your best nights — ") + "   ·   ".join(parts) if not parts.is_empty() else ""
