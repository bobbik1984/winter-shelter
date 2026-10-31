extends PanelContainer

## 0–100 Body Warmth HUD：奶油色说明书风格，显示数值、体温暖度条、速率箭头、衣物标记与效率。

@onready var value_label: Label = $Margin/VBox/TopRow/ValueLabel
@onready var clothing_label: Label = $Margin/VBox/ClothingLabel
@onready var warmth_bar: ProgressBar = $Margin/VBox/WarmthBar
@onready var rate_label: Label = $Margin/VBox/BottomRow/RateLabel
@onready var efficiency_label: Label = $Margin/VBox/BottomRow/EfficiencyLabel

var warmth: WarmthController

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
	efficiency_label.text = "EFF %d%%" % int(round(warmth.get_action_efficiency() * 100.0))
	clothing_label.visible = warmth.has_extra_clothing
