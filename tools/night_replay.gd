extends SceneTree
## 夜晚重算：读 chapter_bot --dump 存下的夜晚输入（JSON），用当前的 NightCurve 规则重跑，不用重玩白天。
## 调平衡用：godot --headless --path . -s res://tools/night_replay.gd -- --dir=<目录> [--set=night_wake_cold_w=48,…]
## 每夜一行：smart（能做的都做）、sleep（醒了什么都不做）的结局 / 最低体温 / 被迫醒来次数 / 睡眠小时 / 夜晚得分。

func _initialize() -> void:
	var dir := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--dir="):
			dir = a.substr(6)
	var t: Tuning = (load("res://resources/tuning.tres") as Tuning).duplicate()
	# --set=名=值,名=值：只在这次重算里改 Tuning（试平衡，不改文件）
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--set="):
			for kv in a.substr(6).split(","):
				var p := kv.split("=")
				t.set(p[0], float(p[1]))
				print("SET ", p[0], " = ", t.get(p[0]))
	var files := Array(DirAccess.get_files_at(dir)).filter(func(f): return String(f).ends_with(".json"))
	files.sort()
	var tally := {}
	for f in files:
		var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join(f)))
		var inp: Dictionary = data["input"]
		var sm := NightCurve.run(inp, t, "smart")
		var lz := NightCurve.run(inp, t, "sleep")
		var vg := NightCurve.run(inp, t, "vigilant")
		print("ch=%d st=%d %-5s %-11s smart=%s/%d/%d slept=%d%% score=%d | vigilant=%s/%d/%d+%d slept=%d%% score=%d | lazy=%s/%d score=%d | fire=%s exp=%.2f" % [
			int(data["ch"]), int(data["st"]), String(data["care"]), String(inp.get("shelter_type", "?")),
			sm["outcome"], int(sm["min_warmth"]), int(sm["wakes"]), int(100 * float(sm.get("sleep_frac", 0))), int(sm.get("score", -1)),
			vg["outcome"], int(vg["min_warmth"]), int(vg["wakes"]), int(vg.get("planned_wakes", 0)), int(100 * float(vg.get("sleep_frac", 0))), int(vg.get("score", -1)),
			lz["outcome"], int(lz["min_warmth"]), int(lz.get("score", -1)),
			str(sm["had_fire"]), float(inp.get("fire_exposure", -1.0))])
		for k in [["smart", sm], ["vigilant", vg], ["lazy", lz]]:
			var key := String(k[0]) + "/" + String(data["care"])
			var r: Dictionary = k[1]
			if not tally.has(key):
				tally[key] = {"n": 0, "SAFE": 0, "COLD": 0, "DANGEROUS": 0, "score": 0.0}
			tally[key]["n"] += 1
			tally[key][String(r["outcome"])] += 1
			tally[key]["score"] += float(r.get("score", 0))
	for key in tally:
		var c: Dictionary = tally[key]
		print("TOTAL %-15s nights=%d SAFE=%d COLD=%d DANGEROUS=%d mean_score=%.0f" % [key, c["n"], c["SAFE"], c["COLD"], c["DANGEROUS"], c["score"] / maxf(c["n"], 1)])
	quit(0)
