class_name Loc
extends RefCounted

## i18n：localization/messages.csv → Godot TranslationServer。
## 英文源串兼作消息键；未知消息回退英文，触屏提示在翻译后改写。
## 用法：Loc.t("Need %d dry wood.") % n —— 先查表再格式化，所以 % 占位符必须与英文一致。
## 语言保存在 user://settings.cfg [ui] lang；运行时按 [L] 切换（GameDirector）。
## 报告与 UI 共用语言服务，不在代码中维护平行译文表。

const PATH := "user://settings.cfg"
static var lang: String = ""

const SUPPORTED_LOCALES := ["en", "zh"]
static var _applied_lang := ""

static func normalize_locale(locale: String) -> String:
	var language := locale.replace("-", "_").get_slice("_", 0).to_lower()
	return language if language in SUPPORTED_LOCALES else "en"

static func is_zh() -> bool:
	if lang == "":
		var cfg := ConfigFile.new()
		lang = normalize_locale(String(cfg.get_value("ui", "lang", OS.get_locale()))) if cfg.load(PATH) == OK else normalize_locale(OS.get_locale())
	lang = normalize_locale(lang)
	if _applied_lang != lang:
		TranslationServer.set_locale(lang)
		_applied_lang = lang
	return lang == "zh"

## 审核工具读取与运行时相同的引擎资源，不复制译文。
static func catalog(locale: String = "zh") -> Dictionary:
	var translation := TranslationServer.get_translation_object(normalize_locale(locale))
	var result := {}
	if translation:
		for key in translation.get_message_list():
			result[String(key)] = String(translation.get_message(key))
	return result

const CJK_FONT := "res://assets/fonts/DroidSansFallbackFull.ttf"
## 箭头、▣▼▸✓ 等符号：桌面靠系统字体，网页和手机没有系统字体后备，要随包带一个。
const SYMBOL_FONT := "res://assets/fonts/DejaVuSans.ttf"
static var _font_ready := false

## 给默认字体挂一个随包附带的 CJK 后备字体（Apache-2.0），没装中文字体的机器也能显示中文。
## 拉丁字符仍用默认字体；只有缺字时才落到后备字体。
static func ensure_cjk_font() -> void:
	if _font_ready:
		return
	_font_ready = true
	var base := ThemeDB.fallback_font
	if base == null:
		return
	var fb := base.fallbacks
	for path in [SYMBOL_FONT, CJK_FONT]:
		var f := load(path) as Font
		if f:
			fb.append(f)
	base.fallbacks = fb

static func set_lang(l: String) -> void:
	lang = normalize_locale(l)
	is_zh()
	var cfg := ConfigFile.new()
	cfg.load(PATH)
	cfg.set_value("ui", "lang", lang)
	cfg.save(PATH)

static func t(s: String) -> String:
	is_zh()
	var out := String(TranslationServer.translate(s))
	return TouchMode.rewrite(out, lang == "zh") if TouchMode.enabled else out
