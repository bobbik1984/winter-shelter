extends RefCounted

## D16 / B1–B3：建造特写的状态机与判定。完整流程（真实按键、不足不扣料、恢复）见 tools/input_smoke_test.gd。

var _passed := 0
var _failures: Array[String] = []

func _check(ok: bool, msg: String) -> void:
	if ok:
		_passed += 1
	else:
		_failures.append(msg)

func run() -> Dictionary:
	_passed = 0
	_failures = []
	var s := BuildSession.new()
	_check(not s.focused(), "一开始不在特写")
	_check(s.begin() and s.state == BuildSession.State.FOCUSED and s.focused(), "放样后进入特写")
	_check(s.step_back() and s.state == BuildSession.State.PAUSED and not s.focused(), "B 退回远景 = 暂停")
	_check(not s.step_back(), "已经退回了，再退没有效果")
	_check(s.begin() and s.focused(), "回到工地继续")
	s.complete()
	_check(s.focused() and s.state == BuildSession.State.COMPLETE, "完工后短暂停留，仍算特写")
	_check(not s.begin() and not s.step_back(), "完工停留时不能再进入或暂停")
	s.reset()
	_check(s.state == BuildSession.State.IDLE and not s.begin(true), "已完工的工地不再进入特写")
	# 同一时间一个未完工工地
	_check(BuildSession.b_key_action(false, false, false) == "place", "没有工地：B = 选址")
	_check(BuildSession.b_key_action(true, false, true) == "resume", "未完工且在旁边：B = 继续")
	_check(BuildSession.b_key_action(true, false, false) == "far", "未完工但太远：不能新建第二个")
	_check(BuildSession.b_key_action(true, true, true) == "done", "已完工：不能再建")
	# 角色遮挡
	var site_r := Rect2(100, 100, 100, 100)
	_check(BuildSession.blocks_site(Rect2(150, 150, 40, 80), site_r, 9.0, 11.0), "角色在工地前面且相交：挡住")
	_check(not BuildSession.blocks_site(Rect2(150, 150, 40, 80), site_r, 13.0, 11.0), "角色在工地后面：挡不住")
	_check(not BuildSession.blocks_site(Rect2(400, 150, 40, 80), site_r, 9.0, 11.0), "屏幕上不相交：挡不住")
	# 机位
	var flat := func(_x: float, _z: float) -> float: return 0.0
	var ridge := func(x: float, _z: float) -> float: return 6.0 if x > 3.0 and x < 5.0 else 0.0
	var aim := Vector3(0, 0.4, 0)
	var cam := Vector3(10, 2.5, 0)
	_check(BuildSession.view_clear(cam, aim, flat), "平地：机位干净")
	_check(not BuildSession.view_clear(cam, aim, ridge), "视线穿过山脊：不行")
	var zs := BuildSession.zoom_candidates(0.4, 0.6, 1.6)
	_check(is_equal_approx(zs[0], 0.4) and zs[1] > 0.4 and zs[2] < 0.4, "先试理想距离，再交替拉远 / 推近")
	# 2026-11-03 第四次评审：地形挡住远景。平地不抬；脚下的坡比视线还陡时推近没用，抬高才行。
	var yaw := Basis(Vector3.UP, deg_to_rad(135.0))
	var base := deg_to_rad(35.0)
	var dir := yaw * Vector3(0, 0, 1)   # 相机一侧的水平方向
	_check(is_zero_approx(BuildSession.view_lift(Vector3.ZERO, 23.0, base, yaw, flat, 30.0)), "平地不抬：移轴构图不变")
	# 朝相机一侧上升的坡（坡度 ≈ 0.9，比 35° 的视线陡）
	var slope := func(x: float, z: float) -> float: return maxf(0.0, Vector2(x, z).dot(Vector2(dir.x, dir.z))) * 0.9
	var lift := BuildSession.view_lift(Vector3.ZERO, 23.0, base, yaw, slope, 30.0)
	_check(lift > 0.0 and lift < 30.0, "挡视线的坡：抬高就能看见（%.0f°）" % lift)
	var a := base + deg_to_rad(lift)
	var cam2: Vector3 = yaw * Vector3(0.0, 23.0 * sin(a), 23.0 * cos(a))
	_check(BuildSession._ray_above_ground(cam2, Vector3.UP * 0.9, slope), "抬高后的视线确实在地面之上")
	_check(not BuildSession._ray_above_ground(yaw * Vector3(0.0, 23.0 * sin(base), 23.0 * cos(base)), Vector3.UP * 0.9, slope), "不抬确实被挡")
	var wall := func(_x: float, _z: float) -> float: return 100.0
	_check(is_equal_approx(BuildSession.view_lift(Vector3.ZERO, 23.0, base, yaw, wall, 30.0), 30.0), "再怎么抬也不够时停在上限")
	# 2026-11-03 触屏：文字改写、摇杆、按钮不出屏不重叠
	_check(TouchMode.rewrite("Hold [E] to build") == "Hold [Use] to build", "键盘提示换成按钮名字")
	_check(TouchMode.rewrite("[B] Step back") == "Step back", "按钮名字本身就在文字里时去掉键名")
	_check(TouchMode.rewrite("Stand next to it and press [B].") == "Stand next to it and press [Build].", "句子里的 [B] 不能被删掉")
	_check(TouchMode.rewrite("按住 [E] 施工   ·   [B] 退后", true) == "按住 [动作] 施工   ·   退后", "中文同样改写")
	_check(TouchMode.rewrite("Map 1  ·  [N] new map") == "Map 1  ·  new map", "换图不是睡觉")
	_check(TouchMode.rewrite("[N] rest when ready") == "[Sleep] rest when ready", "睡觉按钮")
	_check(TouchMode.rewrite("no keys, 100%") == "no keys, 100%", "没有键名的文字不变")
	_check(TouchMode.stick_vector(Vector2(2, 0), 86.0) == Vector2.ZERO, "摇杆死区")
	_check(is_equal_approx(TouchMode.stick_vector(Vector2(0, -300), 86.0).length(), 1.0), "摇杆推到底 = 全速")
	_check(TouchMode.stick_vector(Vector2(0, -86), 86.0).y < 0.0, "往上推 = 前进")
	for cs in [360.0, 390.0, 430.0, 768.0]:
		var fac := TouchMode.ui_factor(cs)
		var canvas: Vector2 = Vector2(cs * 2.16, cs) * (1080.0 / cs) / fac
		for ctx in [{"state": "briefing", "free_play": true}, {"state": "playing"}, {"state": "playing", "at_bed": true, "has_target": true, "use_label": "Enter"},
				{"state": "playing", "site_done": true, "after_dark": true}, {"state": "playing", "inside": true},
				{"state": "playing", "building": true}, {"state": "playing", "focused": true},
				{"state": "paused", "web": true}, {"state": "night"}, {"state": "night", "fire_place": true, "fire_watch": true}, {"state": "report", "has_next": true, "web": true}, {"state": "playing", "intel": true}]:
			var bs := TouchMode.buttons_for(ctx)
			var rs := TouchMode.layout(bs, canvas)
			var ok := true
			for i in rs.size():
				if not Rect2(Vector2.ZERO, canvas).encloses(rs[i]) or rs[i].size.x < 60.0 or rs[i].size.y < 44.0:
					ok = false
				for j in range(i + 1, rs.size()):
					if rs[i].intersects(rs[j]):
						ok = false
			_check(ok, "CSS 高 %d，%s：按钮都在屏幕内、够大、不重叠" % [int(cs), str(ctx)])
	# 2026-11-20 D18 / U1：三意图触屏与防误睡约束
	var explore_ids := TouchMode.buttons_for({"state": "playing"}).map(func(b): return b["id"])
	_check(not ("sleep" in explore_ids), "野外白天探索不常驻睡觉键，防连点误睡（%s）" % str(explore_ids))
	_check("build" in explore_ids and "probe" in explore_ids and "use" in explore_ids, "探索保留移动外的探测、动作与建造入口")
	var done_ids := TouchMode.buttons_for({"state": "playing", "site_done": true, "at_bed": true}).map(func(b): return b["id"])
	_check(not ("build" in done_ids) and "sleep" in done_ids, "完工且在铺位旁：隐藏无效建造键并出现睡觉键（%s）" % str(done_ids))
	var dark_ids := TouchMode.buttons_for({"state": "playing", "after_dark": true}).map(func(b): return b["id"])
	_check("sleep" in dark_ids, "日落后即使在野外也提供睡觉键")
	var bed_bs := TouchMode.buttons_for({"state": "playing", "at_bed": true, "has_target": true, "use_label": "Enter"})
	var bed_rs := TouchMode.layout(bed_bs, Vector2(1088.0, 504.0))
	var use_r := Rect2()
	var sleep_r := Rect2()
	for i in bed_bs.size():
		if bed_bs[i]["id"] == "use":
			use_r = bed_rs[i]
		elif bed_bs[i]["id"] == "sleep":
			sleep_r = bed_rs[i]
	_check(use_r.position.x - (sleep_r.position.x + sleep_r.size.x) >= 100.0, "睡觉键与采集主键之间保留明显防误触间距")
	_check(TouchMode.primary_label("deadwood") == "Chop wood" and TouchMode.primary_label("birch") == "Peel bark"
		and TouchMode.primary_label("bough") == "Get bedding" and TouchMode.primary_label("fire") == "Hot drink", "情境主键按对象显示动词+目标")
	_check(TouchMode.primary_label("site", false) == "Work site" and TouchMode.primary_label("site", true, true) == "Drop pile"
		and TouchMode.primary_label("site", true, false, true) == "Enter" and TouchMode.primary_label("site", true, false, false) == "Use", "工地主键区分施工/卸货/进洞/帐篷")
	_check(TouchMode.primary_label("") == "Use", "无目标时回退默认动作标签")
	# 2026-11-07 夜里：睡着时有"醒来"按钮；有火时有"守火"开关；醒着等选择时没有
	var nb := TouchMode.buttons_for({"state": "night", "fire_place": true, "fire_watch": true})
	var ids := nb.map(func(b): return b["id"])
	_check("wake" in ids and "watch" in ids and "speed" in ids, "夜里睡着：醒来、守火、快进按钮都在（%s）" % str(ids))
	_check(nb.filter(func(b): return b["id"] == "wake")[0]["key"] == KEY_W and nb.filter(func(b): return b["id"] == "watch")[0]["key"] == KEY_F, "醒来 = W，守火 = F（和键盘同一条路径）")
	_check(not ("watch" in TouchMode.buttons_for({"state": "night"}).map(func(b): return b["id"])), "没有火时不显示守火")
	_check(TouchMode.buttons_for({"state": "night", "waiting": true}).is_empty(), "醒着等选择时不显示这些按钮（行动在醒来面板里点）")
	return {"passed": _passed, "failures": _failures}
