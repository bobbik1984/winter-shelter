extends PanelContainer

## 0–100 Body Warmth HUD：奶油色说明书风格，显示数值、体温暖度条、速率箭头、衣物标记与效率。

@onready var value_label: Label = $Margin/VBox/TopRow/ValueLabel
@onready var clothing_label: Label = $Margin/VBox/ClothingLabel
@onready var warmth_bar: ProgressBar = $Margin/VBox/WarmthBar
@onready var rate_label: Label = $Margin/VBox/BottomRow/RateLabel
@onready var efficiency_label: Label = $Margin/VBox/BottomRow/EfficiencyLabel

var warmth: WarmthController
## D18 / U1：触屏紧凑模式（收窄宽度、满效隐藏 EFF 100%、干燥时不占额外一行）。
var compact_mode: bool = false

func set_compact(on: bool) -> void:
	compact_mode = on
	var margin := get_node_or_null("Margin") as MarginContainer
	if on:
		offset_right = offset_left + 264.0
		offset_bottom = offset_top + 88.0
		custom_minimum_size = Vector2(264.0, 0.0)
		size = Vector2(264.0, 82.0)
		if margin:
			margin.add_theme_constant_override("margin_left", 10)
			margin.add_theme_constant_override("margin_right", 10)
			margin.add_theme_constant_override("margin_top", 6)
			margin.add_theme_constant_override("margin_bottom", 6)
		if value_label:
			value_label.add_theme_font_size_override("font_size", 18)
		if rate_label:
			rate_label.add_theme_font_size_override("font_size", 13)
	_refresh()

func _ready() -> void:
	warmth = get_tree().get_first_node_in_group("warmth_controller") as WarmthController
	if warmth == null:
		push_warning("[HUDWarmth] 找不到 warmth_controller；体温条将保持初始值。")
		return
	warmth.warmth_changed.connect(_on_warmth_changed)
	_refresh()

func _process(_delta: float) -> void:
	if warmth:
		_refresh()

func _on_warmth_changed(_value: float, _rate: float, _indicator: String) -> void:
	_refresh()

func _refresh() -> void:
	if warmth == null:
		return
	var value := clampf(warmth.body_warmth, 0.0, 100.0)
	value_label.text = "%d / 100" % int(round(value))
	warmth_bar.value = value
	rate_label.text = "%s  %s" % [warmth.get_rate_indicator(), warmth.get_context_label()]
	var eff_pct := int(round(warmth.get_action_efficiency() * 100.0))
	efficiency_label.text = "EFF %d%%" % eff_pct
	efficiency_label.visible = (not compact_mode) or eff_pct < 100
	# 文字与颜色由 GameDirector 按受潮程度写入（DRY / DAMP / WET）
