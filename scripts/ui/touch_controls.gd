class_name TouchControls
extends CanvasLayer

## 触屏控制层（2026-11-03）：左手虚拟摇杆 + 按情境变化的按钮 + 竖屏提示。
## 按钮表、布局和文字改写都在 TouchMode；这里只管手指、绘制和把按键发给游戏。
## 多点触控要自己跟踪（Button 只认一根手指，摇杆和按住按钮要同时用）。

const INK := Color(0.035, 0.05, 0.075, 0.62)
const CREAM := Color(0.96, 0.91, 0.80)
const AMBER := Color(1.0, 0.62, 0.20)
const STICK_R := 86.0
const FPS_CHECK_SECONDS := 6.0
const FPS_DROP_BELOW := 22.0
## [TUNE] 手机上的默认镜头距离比例。
const TOUCH_ZOOM := 1.0

var director: GameDirector
var _canvas: Control
var _buttons: Array = []
var _rects: Array = []
var _sig := ""
var _ctx: Dictionary = {}
## 手指 index → 按下的按钮 id（"" = 摇杆）
var _touch: Dictionary = {}
var _held: Dictionary = {}
var _stick_idx := -1
var _stick_origin := Vector2.ZERO
var _stick_now := Vector2.ZERO
var portrait := false
var _portrait_paused := false
var _fps_t := 0.0
var _portrait_label: Label
var _portrait_shade: ColorRect
var _portrait_cover: ColorRect

func _ready() -> void:
	layer = 30
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("touch_controls")
	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_controls)
	add_child(_canvas)
	_portrait_cover = ColorRect.new()
	_portrait_cover.color = Color(0.02, 0.035, 0.06, 1.0)
	_portrait_cover.set_anchors_preset(Control.PRESET_FULL_RECT)
	_portrait_cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_portrait_cover.visible = false
	add_child(_portrait_cover)
	_portrait_label = Label.new()
	_portrait_label.text = Loc.t("Please rotate your phone to landscape")
	_portrait_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_portrait_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_portrait_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_portrait_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_portrait_label.add_theme_font_size_override("font_size", 34)
	_portrait_label.add_theme_color_override("font_color", CREAM)
	_portrait_shade = ColorRect.new()
	_portrait_shade.color = Color(0.02, 0.03, 0.05, 1.0)
	_portrait_shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_portrait_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_portrait_shade.visible = false
	add_child(_portrait_shade)
	_portrait_label.visible = false
	add_child(_portrait_label)
	_apply_hud_layout()
	# 手机上不等 GraphicsSettings 的 30 帧：否则第一屏的字小到看不见
	if director and director.graphics:
		get_tree().root.content_scale_factor = director.graphics._ui_factor()
	get_window().size_changed.connect(_on_resized)
	_on_resized()

func _on_resized() -> void:
	if director and director.graphics:
		director.graphics.refresh_ui_scale()
	var s := get_window().size
	var was := portrait
	portrait = s.y > s.x
	if portrait and not was:
		_release_all()
	_sig = ""
	_canvas.queue_redraw()

## 手机上的 HUD：右上放天气卡和缩小的罗盘，左下留给摇杆，键盘说明不显示。
func _apply_hud_layout() -> void:
	if director == null or director.hud == null:
		return
	var card := director.hud.get_node_or_null("TopRightCard") as Control
	if card:
		card.offset_left = -216.0
		card.offset_right = -10.0
		card.offset_top = 10.0
		card.offset_bottom = 110.0
		var hint := card.get_node_or_null("VBox/HintLabel") as Control
		if hint:
			hint.modulate.a = 0.0
			hint.custom_minimum_size = Vector2.ZERO
			hint.set("autowrap_mode", TextServer.AUTOWRAP_OFF)
			hint.set("clip_text", true)
			hint.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var instr := director.hud.get_node_or_null("Instructions") as Control
	if instr:
		instr.modulate.a = 0.0
	# 体温卡顶到左上，缩小一点，给下面的目标和背包让位
	var warm := director.hud.get_parent().get_node_or_null("HUDWarmth") as Control
	if warm:
		warm.scale = Vector2(0.86, 0.86)
		warm.position = Vector2(10, 8)
	# 放置时的剖面图：缩小放到屏幕上方中间，不压按钮
	if director._cutaway_panel:
		var cp := director._cutaway_panel
		cp.set_anchors_preset(Control.PRESET_TOP_LEFT)
		cp.scale = Vector2(0.6, 0.6)
		cp.position = Vector2(420, 70)
	# 手机屏幕小：默认拉近一些，人物看得清
	if director.rig:
		director.rig.set_default_zoom(TOUCH_ZOOM)
	var compass := director.hud.get_node_or_null("Compass") as Control
	if compass:
		compass.scale = Vector2(0.56, 0.56)
		compass.offset_left = -114.0
		compass.offset_right = -114.0 + 186.0
		compass.offset_top = 0.0
		compass.offset_bottom = 186.0
		compass.anchor_top = 0.0
		compass.anchor_bottom = 0.0
		compass.position.y = 150.0

func _context() -> Dictionary:
	var d := director
	var st := "other"
	match d.state:
		GameDirector.State.BRIEFING: st = "briefing"
		GameDirector.State.PLAYING: st = "playing"
		GameDirector.State.PAUSED: st = "paused"
		GameDirector.State.NIGHT: st = "night"
		GameDirector.State.REPORT: st = "report"
	return {"state": st, "inside": d._in_shelter, "near_fire": d._nearest_fire(d.tuning.fire_warm_radius_m) != null, "intel": d.ui.intel_open(), "building": d.build.active, "focused": d.session.focused(),
		"waiting": d.night != null and d.night.waiting(), "has_next": d.state == GameDirector.State.REPORT and d._next_stage().x >= 0,
		"free_play": not LevelState.active() or LevelState.level.is_free(), "credits": d.ui.credits_open(), "web": OS.has_feature("web")}

func _process(delta: float) -> void:
	if director == null or director.ui == null:
		return
	_portrait_label.visible = portrait
	_portrait_shade.visible = portrait
	_portrait_cover.visible = portrait
	if portrait:
		# 竖屏：世界停住，转回来后在菜单里继续
		if not _portrait_paused and director.state == GameDirector.State.PLAYING and not director.ui.intel_open():
			_portrait_paused = true
			_send_key(KEY_ESCAPE)
		_set_buttons([])
		return
	_portrait_paused = false
	_ctx = _context()
	var list: Array = TouchMode.buttons_for(_ctx)
	_set_buttons(list)
	if _stick_idx >= 0 and not TouchMode.stick_on(_ctx):
		_end_stick()
	_watch_fps(delta)

## 帧率长期太低就自动降一档画质（只降不升，不写存档）。
func _watch_fps(delta: float) -> void:
	if director.state != GameDirector.State.PLAYING:
		_fps_t = 0.0
		return
	_fps_t += delta
	if _fps_t >= FPS_CHECK_SECONDS:
		_fps_t = 0.0
		if Engine.get_frames_per_second() < FPS_DROP_BELOW and director.graphics.level > 0:
			director.graphics.step_down()

func _set_buttons(list: Array) -> void:
	var size := _canvas.get_rect().size
	var sig := "%s|%s" % [size, ",".join(list.map(func(b): return "%s:%s" % [b["id"], b["label"]]))]
	if sig == _sig:
		return
	_sig = sig
	var ids := list.map(func(b): return b["id"])
	for f in _touch.keys():
		if _touch[f] != "" and not ids.has(_touch[f]):
			_release_button(_touch[f])
			_touch.erase(f)
	_buttons = list
	_rects = TouchMode.layout(list, size)
	var rects: Array[Rect2] = []
	for r in _rects:
		rects.append(r)
	if director.ui:
		director.ui.touch_rects = rects
	_canvas.queue_redraw()

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var e := event as InputEventScreenTouch
		if e.pressed:
			_on_down(e.index, e.position)
		else:
			_on_up(e.index)
	elif event is InputEventScreenDrag:
		var e := event as InputEventScreenDrag
		if e.index == _stick_idx:
			_stick_now = e.position
			_push_stick()
			get_viewport().set_input_as_handled()

func _on_down(idx: int, pos: Vector2) -> void:
	if portrait:
		return
	for i in _buttons.size():
		if (_rects[i] as Rect2).grow(6.0).has_point(pos):
			_touch[idx] = _buttons[i]["id"]
			_press_button(_buttons[i])
			get_viewport().set_input_as_handled()
			_canvas.queue_redraw()
			return
	# 面板里能点的行（夜里的行动）
	for n in get_tree().get_nodes_in_group("touch_tap"):
		var c := n as Control
		if c.is_visible_in_tree() and c.get_global_rect().has_point(pos):
			_send_key(c.get_meta("touch_key") as Key)
			get_viewport().set_input_as_handled()
			return
	if _stick_idx < 0 and TouchMode.stick_on(_ctx) and pos.x < _canvas.get_rect().size.x * 0.5:
		_stick_idx = idx
		_stick_origin = pos
		_stick_now = pos
		_touch[idx] = ""
		get_viewport().set_input_as_handled()
		_canvas.queue_redraw()

func _on_up(idx: int) -> void:
	if idx == _stick_idx:
		_end_stick()
		_touch.erase(idx)
		return
	if _touch.has(idx):
		var id = _touch[idx]
		_touch.erase(idx)
		_release_button(id)
		_canvas.queue_redraw()
		get_viewport().set_input_as_handled()

func _press_button(b: Dictionary) -> void:
	_held[b["id"]] = b
	if b.has("action"):
		Input.action_press(b["action"])
	elif b.has("hold_key"):
		HoldAssist.touch_fire = true
		_key_event(b["hold_key"], true)
	elif b.has("call"):
		call(b["call"])
	elif b.has("key") and b["key"] != KEY_NONE:
		_send_key(b["key"])

func _release_button(id: String) -> void:
	var b: Dictionary = _held.get(id, {})
	_held.erase(id)
	if b.has("action"):
		Input.action_release(b["action"])
	elif b.has("hold_key"):
		HoldAssist.touch_fire = false
		_key_event(b["hold_key"], false)

func _release_all() -> void:
	for id in _held.keys():
		_release_button(id)
	_touch.clear()
	_end_stick()

## 直接交给视口（走和键盘一样的 _unhandled_input）。延后一步，不在处理触摸事件的中途嵌套分发。
func _key_event(k: Key, pressed: bool) -> void:
	var e := InputEventKey.new()
	e.keycode = k
	e.physical_keycode = k
	e.pressed = pressed
	get_viewport().push_input.call_deferred(e)

func _send_key(k: Key) -> void:
	_key_event(k, true)
	_key_event(k, false)

func _push_stick() -> void:
	var v := TouchMode.stick_vector(_stick_now - _stick_origin, STICK_R)
	_set_axis("move_left", maxf(-v.x, 0.0))
	_set_axis("move_right", maxf(v.x, 0.0))
	_set_axis("move_up", maxf(-v.y, 0.0))
	_set_axis("move_down", maxf(v.y, 0.0))
	_canvas.queue_redraw()

func _set_axis(action: String, strength: float) -> void:
	if strength > 0.0:
		Input.action_press(action, strength)
	else:
		Input.action_release(action)

func _end_stick() -> void:
	if _stick_idx >= 0:
		_touch.erase(_stick_idx)
	_stick_idx = -1
	for a in ["move_left", "move_right", "move_up", "move_down"]:
		Input.action_release(a)
	_canvas.queue_redraw()

func _draw_controls() -> void:
	var font := ThemeDB.fallback_font
	if not portrait and TouchMode.stick_on(_ctx):
		var size := _canvas.get_rect().size
		var c := _stick_origin if _stick_idx >= 0 else Vector2(STICK_R + 40.0, size.y - STICK_R - 40.0)
		_canvas.draw_circle(c, STICK_R, Color(INK, 0.35))
		_canvas.draw_arc(c, STICK_R, 0.0, TAU, 48, Color(CREAM, 0.5), 2.5, true)
		var off := (_stick_now - _stick_origin).limit_length(STICK_R) if _stick_idx >= 0 else Vector2.ZERO
		_canvas.draw_circle(c + off, 36.0, Color(CREAM, 0.5 if _stick_idx >= 0 else 0.25))
	for i in _buttons.size():
		var b: Dictionary = _buttons[i]
		var r: Rect2 = _rects[i]
		var pressed: bool = _held.has(b["id"])
		var round_btn: bool = b["slot"] == "big_r" or b["slot"] == "big_l"
		var primary := bool(b.get("primary", false))
		var fill := Color(AMBER, 0.85) if pressed else (Color(AMBER, 0.32) if primary else INK)
		var edge := AMBER if primary else Color(CREAM, 0.55)
		if round_btn:
			var c := r.get_center()
			var rad := r.size.x * 0.5
			_canvas.draw_circle(c, rad, fill)
			_canvas.draw_arc(c, rad, 0.0, TAU, 48, edge, 2.5, true)
		else:
			var s := StyleBoxFlat.new()
			s.bg_color = fill
			s.border_color = edge
			s.set_border_width_all(2)
			s.set_corner_radius_all(10)
			_canvas.draw_style_box(s, r)
		var fs := 22 if round_btn or primary else 18
		var label := String(b["label"])
		while fs > 11 and font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > r.size.x - 10.0:
			fs -= 1
		var tw := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		var at := r.get_center() + Vector2(-tw.x * 0.5, font.get_ascent(fs) * 0.5 - 2.0)
		_canvas.draw_string_outline(font, at, label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0.02, 0.03, 0.06, 0.8))
		_canvas.draw_string(font, at, label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, CREAM)

## 网页版：把这台手机上的试玩记录存成一个文件，方便发回来。
func save_log() -> void:
	var text := SessionLog.export_recent()
	if text == "":
		director.ui.toast(Loc.t("No play log yet."), 3.0)
		return
	if OS.has_feature("web"):
		JavaScriptBridge.download_buffer(text.to_utf8_buffer(), "snow_shelter_log.jsonl", "text/plain")
	director.ui.toast(Loc.t("Play log saved."), 3.0)
