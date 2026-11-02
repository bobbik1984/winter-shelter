class_name SitePile
extends RefCounted

## D16 / B4：工地旁的材料堆（CORE_GAMEPLAY §12.5）。干柴和枝条共用一堆：
## 建造从这里拿，夜里的火也烧这堆柴、多铺的垫层也算这堆枝条。桦皮（引火物）一直随身。
## 只有在这里才能放下东西——背包有上限，所以大庇护所和通宵的柴要跑几趟。

const STACKABLE := ["wood", "bedding"]

var stock := {"wood": 0, "bedding": 0}

func amount(item: String) -> int:
	return int(stock.get(item, 0))

func is_empty() -> bool:
	return amount("wood") == 0 and amount("bedding") == 0

## 把背包里能放的都放下。返回放下了什么（{wood, bedding}）。
func deposit(inv: Inventory) -> Dictionary:
	var moved := {}
	for k in STACKABLE:
		var n := inv.count(k)
		if n > 0:
			inv.add(k, -n)
			stock[k] = amount(k) + n
			moved[k] = n
	return moved

## 堆里 + 背包里一共有多少。
func total(item: String, inv: Inventory) -> int:
	return amount(item) + inv.count(item)

func has_all(cost: Dictionary, inv: Inventory) -> bool:
	for k in cost:
		if total(k, inv) < int(cost[k]):
			return false
	return true

## 原子扣除：先用堆里的，再用背包的；不够就什么都不扣。
func spend(cost: Dictionary, inv: Inventory) -> bool:
	if not has_all(cost, inv):
		return false
	for k in cost:
		var need := int(cost[k])
		var from_pile := mini(need, amount(k))
		if k in STACKABLE:
			stock[k] = amount(k) - from_pile
			need -= from_pile
		if need > 0:
			inv.add(k, -need)
	return true

func missing_text(cost: Dictionary, inv: Inventory) -> String:
	var parts: Array[String] = []
	for k in cost:
		var need := int(cost[k]) - total(k, inv)
		if need > 0:
			parts.append("%d %s" % [need, k])
	return ", ".join(parts)
