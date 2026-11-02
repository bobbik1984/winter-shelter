class_name SessionLog
extends RefCounted

## 试玩记录（PT01 / PT02 用）：每局把关键事件写成一行 JSON 到 user://sessions/<时间>.jsonl。
## 只存本机，不联网。字段：t = 现实秒，clock = 游戏时刻，ev = 事件名，其余为事件数据。
## 汇总：python3 tools/playtest_report.py <目录>

static var _file: FileAccess
static var _t0 := 0

## 测试工具关掉：不往玩家的试玩记录里写。
static var disabled := false

static func start(meta: Dictionary) -> void:
	if disabled:
		return
	DirAccess.make_dir_recursive_absolute("user://sessions")
	var stamp := Time.get_datetime_string_from_system().replace(":", "-")
	_file = FileAccess.open("user://sessions/%s.jsonl" % stamp, FileAccess.WRITE)
	_t0 = Time.get_ticks_msec()
	log_event("start", "", meta)

static func log_event(ev: String, clock: String, data: Dictionary = {}) -> void:
	if _file == null:
		return
	var row := {"t": snappedf((Time.get_ticks_msec() - _t0) / 1000.0, 0.1), "clock": clock, "ev": ev}
	row.merge(data)
	_file.store_line(JSON.stringify(row))
	_file.flush()

static func close() -> void:
	if _file:
		_file.close()
		_file = null
