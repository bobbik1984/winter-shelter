class_name TouchMode
extends RefCounted

## 触屏模式（2026-11-03，手机网页版）：判定是否启用、把键盘提示改写成按钮名字、
## 按情境给出按钮表。都是纯逻辑，方便 headless 测试；画面和手指在 TouchControls。
## 按钮只发现有的动作和按键（和手柄 GameInput 同一思路），所以玩法规则不受影响。

static var enabled := false
## 测试用：--touch-css=390 假装手机的 CSS 高度（桌面窗口没有 CSS 像素的概念）。
static var css_override := 0.0
static var _regex_strip: RegEx

## 启动时调一次。命令行 --touch / --no-touch 优先，便于在桌面上测试。
static func detect(args: PackedStringArray = OS.get_cmdline_user_args()) -> bool:
	for a in args:
		if a.begins_with("--touch-css="):
			css_override = float(a.substr(12))
	if "--no-touch" in args:
		enabled = false
	elif "--touch" in args:
		enabled = true
	else:
		enabled = (OS.has_feature("web") or OS.has_feature("mobile")) and DisplayServer.is_touchscreen_available()
	return enabled

# ---------------------------------------------------------------- 文字

## 有对应按钮、句子里还要提到它的键：换成按钮名字。其余键提示直接去掉，后面的文字本身就是按钮名。
const NAMED_EN := {"[E]": "[Use]", "[Space]": "[Probe]", "[F]": "[Fire]", "[N]": "[Sleep]", "[I]": "[Intel]", "[H]": "[Intel]", "[B]": "[Build]"}
const NAMED_ZH := {"[E]": "[动作]", "[Space]": "[探测]", "[F]": "[生火]", "[N]": "[睡觉]", "[I]": "[情报]", "[H]": "[情报]", "[B]": "[建造]"}

## 把一句带键盘提示的文字改写给触屏玩家看。
static func rewrite(s: String, zh: bool = false) -> String:
	if "[" not in s:
		return s
	var out := s
	# "[N] new map" 里的 N 不是睡觉
	out = out.replace("[N] new map", "new map").replace("[N] 换一张图", "换一张图")
	# 特写和放置时 B 是退后 / 取消，按钮上就写着这个词；其它句子里的 [B] 才是"建造"按钮
	for phrase in ["Step back", "cancel", "退后", "取消"]:
		out = out.replace("[B] " + phrase, phrase)
	if _regex_strip == null:
		_regex_strip = RegEx.new()
		_regex_strip.compile("\\[(R|Tab|T|2|C|Q|Esc|L|M|Enter|F3|F9|F10|F11|-|=|V|Wheel|←|→|↑|↓|WASD)\\]\\s*")
	out = _regex_strip.sub(out, "", true)
	var named: Dictionary = NAMED_ZH if zh else NAMED_EN
	for k in named:
		out = out.replace(k, named[k])
	return out

## 界面放大倍数：把画布高度压到约等于 CSS 高度 × 1.4，最小的字约 10 CSS 像素。
static func ui_factor(css_height: float) -> float:
	return 1080.0 / clampf(css_height * 1.4, 500.0, 1080.0)

# ---------------------------------------------------------------- 按钮表

## ctx：state（briefing / playing / paused / night / report / other）、intel、building、focused、
## waiting、has_next、free_play、credits、web。返回 [{id, label, key | action | hold_key, slot, primary?}]。
## slot：big_r / big_l / arc（右侧弧）/ top（右上小钮）/ bar（底部居中一排）。
static func buttons_for(ctx: Dictionary) -> Array:
	var b: Array = []
	if bool(ctx.get("credits", false)):
		b.append(_key("close", Loc.t("Close"), KEY_C, "bar", true))
		return b
	if bool(ctx.get("intel", false)):
		# 白天的情报面板只有 Tab 往后翻（循环），所以只在简报页有"上一页"
		if ctx.get("state") == "briefing":
			b.append(_key("prev", "◀", KEY_LEFT, "bar"))
		b.append(_key("next", "▶", KEY_RIGHT if ctx.get("state") == "briefing" else KEY_TAB, "bar"))
		b.append(_key("close", Loc.t("Close"), KEY_ESCAPE, "bar", true))
		return b
	match String(ctx.get("state", "")):
		"briefing":
			b.append(_key("ch_prev", "◀ " + Loc.t("Chapter"), KEY_LEFT, "bar"))
			b.append(_key("ch_next", Loc.t("Chapter") + " ▶", KEY_RIGHT, "bar"))
			b.append(_key("st_prev", "▼ " + Loc.t("Stage"), KEY_DOWN, "bar"))
			b.append(_key("st_next", Loc.t("Stage") + " ▲", KEY_UP, "bar"))
			b.append(_key("map", Loc.t("New map"), KEY_N, "bar"))
			b.append(_key("lang", "中文 / EN", KEY_L, "bar"))
			b.append(_key("intel", Loc.t("Intel"), KEY_I, "bar"))
			b.append(_key("tent", Loc.t("Tent kit"), KEY_T, "bar"))
			if bool(ctx.get("free_play", false)):
				b.append(_key("full_day", Loc.t("Full day"), KEY_2, "bar"))
			b.append(_key("begin", Loc.t("Begin"), KEY_ENTER, "bar", true))
		"playing":
			if bool(ctx.get("inside", false)):
				b.append({"id": "out", "label": Loc.t("Step outside"), "action": "interact", "slot": "big_r", "primary": true})
				b.append(_key("sleep", Loc.t("Sleep"), KEY_N, "arc"))
				b.append(_key("menu", Loc.t("Menu"), KEY_ESCAPE, "top"))
				b.append(_key("intel", Loc.t("Intel"), KEY_I, "top"))
			elif bool(ctx.get("focused", false)):
				b.append({"id": "work", "label": Loc.t("Build"), "action": "interact", "slot": "big_r", "primary": true})
				b.append(_key("back", Loc.t("Step back"), KEY_B, "arc"))
				b.append(_key("respot", Loc.t("Other spot"), KEY_R, "arc"))
				b.append(_key("intel", Loc.t("Intel"), KEY_I, "top"))
			elif bool(ctx.get("building", false)):
				b.append({"id": "place", "label": Loc.t("Place"), "action": "interact", "slot": "big_r", "primary": true})
				b.append(_key("type", Loc.t("Type"), KEY_TAB, "arc"))
				b.append(_key("rotate", Loc.t("Rotate"), KEY_R, "arc"))
				b.append(_key("cancel", Loc.t("Cancel"), KEY_B, "arc"))
				b.append(_key("roof", Loc.t("Roof"), KEY_T, "top"))
				b.append(_key("vents", Loc.t("Vents"), KEY_2, "top"))
			else:
				b.append({"id": "use", "label": Loc.t("Use"), "action": "interact", "slot": "big_r", "primary": true})
				b.append({"id": "probe", "label": Loc.t("Probe"), "action": "probe", "slot": "big_l"})
				b.append(_key("build", Loc.t("Build"), KEY_B, "arc"))
				b.append({"id": "fire", "label": Loc.t("Add log") if bool(ctx.get("near_fire", false)) else Loc.t("Fire"), "hold_key": KEY_F, "slot": "arc"})
				b.append(_key("sleep", Loc.t("Sleep"), KEY_N, "arc"))
				b.append(_key("menu", Loc.t("Menu"), KEY_ESCAPE, "top"))
				b.append(_key("intel", Loc.t("Intel"), KEY_I, "top"))
		"paused":
			b.append(_key("resume", Loc.t("Resume"), KEY_ESCAPE, "bar", true))
			b.append(_key("restart", Loc.t("Restart"), KEY_R, "bar"))
			b.append(_key("gfx", Loc.t("Graphics"), KEY_F10, "bar"))
			b.append(_key("sound", Loc.t("Sound"), KEY_M, "bar"))
			b.append(_key("ui_down", Loc.t("Text") + " −", KEY_MINUS, "bar"))
			b.append(_key("ui_up", Loc.t("Text") + " +", KEY_EQUAL, "bar"))
			b.append(_key("credits", Loc.t("Credits"), KEY_C, "bar"))
			if bool(ctx.get("web", false)):
				b.append({"id": "log", "label": Loc.t("Save log"), "call": "save_log", "slot": "bar"})
		"night":
			if not bool(ctx.get("waiting", false)):
				b.append({"id": "speed", "label": Loc.t("Speed up"), "action": "probe", "slot": "big_r"})
				b.append(_key("wake", Loc.t("Wake up"), KEY_W, "big_l"))
				if bool(ctx.get("fire_place", false)):
					b.append(_key("watch", Loc.t("Fire watch: %s") % (Loc.t("on") if bool(ctx.get("fire_watch", false)) else Loc.t("off")), KEY_F, "bar"))
		"report":
			if bool(ctx.get("has_next", false)):
				b.append(_key("next_stage", Loc.t("Next stage"), KEY_ENTER, "bar", true))
			b.append(_key("retry", Loc.t("Try again"), KEY_R, "bar", not bool(ctx.get("has_next", false))))
			if bool(ctx.get("web", false)):
				b.append({"id": "log", "label": Loc.t("Save log"), "call": "save_log", "slot": "bar"})
	return b

static func _key(id: String, label: String, k: Key, slot: String, primary: bool = false) -> Dictionary:
	return {"id": id, "label": label, "key": k, "slot": slot, "primary": primary}

## 摇杆是否可用（只有能走路的时候）。
static func stick_on(ctx: Dictionary) -> bool:
	return ctx.get("state") == "playing" and not bool(ctx.get("focused", false)) and not bool(ctx.get("intel", false)) and not bool(ctx.get("inside", false))

## 手指偏移 → 移动向量：死区内为 0，半径处为 1，方向不变。屏幕上方 = 前进（负 y）。
static func stick_vector(offset: Vector2, radius: float, dead: float = 0.15) -> Vector2:
	var m := offset.length() / maxf(radius, 1.0)
	if m < dead:
		return Vector2.ZERO
	return offset.normalized() * minf((m - dead) / (1.0 - dead), 1.0)

## 按钮在画布上的矩形。size：画布大小；同一 slot 的按钮按出现顺序排。
static func layout(buttons: Array, size: Vector2) -> Array:
	var counts := {}
	for bn in buttons:
		counts[bn["slot"]] = int(counts.get(bn["slot"], 0)) + 1
	var seen := {}
	var out: Array[Rect2] = []
	const BIG := 124.0
	const M := 16.0
	# 底部一排：按总宽度均分，放不下就缩，最窄也要能点
	var bar_w := minf(190.0, (size.x - M * 2.0 - 8.0 * maxf(float(counts.get("bar", 1)) - 1.0, 0.0)) / maxf(float(counts.get("bar", 1)), 1.0))
	var bar_total := float(counts.get("bar", 0)) * bar_w + 8.0 * maxf(float(counts.get("bar", 0)) - 1.0, 0.0)
	for bn in buttons:
		var slot := String(bn["slot"])
		var i := int(seen.get(slot, 0))
		seen[slot] = i + 1
		match slot:
			"big_r": out.append(Rect2(size.x - M - BIG, size.y - M - BIG, BIG, BIG))
			"big_l": out.append(Rect2(size.x - M * 2.0 - BIG * 2.0, size.y - M - BIG * 0.8, BIG * 0.8, BIG * 0.8))
			"arc": out.append(Rect2(size.x - M - 112.0 - i * 120.0, size.y - M - BIG - 12.0 - 64.0, 112.0, 64.0))
			"top": out.append(Rect2(size.x - 216.0 - M - (i + 1) * 104.0, 10.0, 96.0, 56.0))
			_: out.append(Rect2((size.x - bar_total) * 0.5 + i * (bar_w + 8.0), size.y - 72.0, bar_w, 62.0))
	return out
