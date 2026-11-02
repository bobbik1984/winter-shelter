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
	return {"passed": _passed, "failures": _failures}
