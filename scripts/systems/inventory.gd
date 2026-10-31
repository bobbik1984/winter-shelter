class_name Inventory
extends Node

## 极简背包（T2.2）：木材 / 桦树皮（引火物）/ 垫层 / 额外衣物。
## 变化通过 changed 信号通知 HUD 与角色背包外观。

signal changed()

@export var max_wood: int = 12
var wood: int = 0
var bark: int = 0
var bedding: int = 0
var has_extra_clothing: bool = false

func count(item: String) -> int:
	match item:
		"wood": return wood
		"bark": return bark
		"bedding": return bedding
	return 0

func add(item: String, amount: int) -> int:
	var before := count(item)
	match item:
		"wood": wood = clampi(wood + amount, 0, max_wood)
		"bark": bark = maxi(bark + amount, 0)
		"bedding": bedding = maxi(bedding + amount, 0)
	changed.emit()
	return count(item) - before

func has_all(cost: Dictionary) -> bool:
	for k in cost:
		if count(k) < int(cost[k]):
			return false
	return true

## 原子扣除：任何一项不足都不扣。
func spend(cost: Dictionary) -> bool:
	if not has_all(cost):
		return false
	for k in cost:
		add(k, -int(cost[k]))
	return true

func missing_text(cost: Dictionary) -> String:
	var parts: Array[String] = []
	for k in cost:
		var need := int(cost[k]) - count(k)
		if need > 0:
			parts.append("%d %s" % [need, k])
	return ", ".join(parts)
