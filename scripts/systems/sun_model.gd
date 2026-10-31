class_name SunModel
extends RefCounted

## 太阳位置（纯函数，可测试）：由纬度、赤纬、真太阳时算高度角与方位角。
## 方位角：自北顺时针（90 = 东，180 = 南，270 = 西）。
## 世界约定：-Z = 北，+X = 东（与罗盘一致）。
## 玩法意义：影子长度 / 方向就是时钟——上午长、正午最短、傍晚再变长（Hard ≠ Obscure）。

## 返回 Vector2(高度角°, 方位角°)。minutes = 当天分钟数（0..1440）。
static func position(minutes: float, lat_deg: float, decl_deg: float, noon_minutes: float) -> Vector2:
	var lat := deg_to_rad(lat_deg)
	var dec := deg_to_rad(decl_deg)
	var h := deg_to_rad((minutes - noon_minutes) / 60.0 * 15.0)   # 时角，下午为正
	var sin_el := sin(lat) * sin(dec) + cos(lat) * cos(dec) * cos(h)
	var el := asin(clampf(sin_el, -1.0, 1.0))
	var az := atan2(sin(h), cos(h) * sin(lat) - tan(dec) * cos(lat)) + PI
	return Vector2(rad_to_deg(el), fposmod(rad_to_deg(az), 360.0))

## 指向太阳的世界单位向量。
static func direction(minutes: float, lat_deg: float, decl_deg: float, noon_minutes: float) -> Vector3:
	var p := position(minutes, lat_deg, decl_deg, noon_minutes)
	var el := deg_to_rad(p.x)
	var az := deg_to_rad(p.y)
	return Vector3(sin(az) * cos(el), sin(el), -cos(az) * cos(el)).normalized()

## 日落时刻（分钟）：几何日落 cos H0 = -tan(lat)·tan(dec)。
static func sunset_minutes(lat_deg: float, decl_deg: float, noon_minutes: float) -> float:
	var c := -tan(deg_to_rad(lat_deg)) * tan(deg_to_rad(decl_deg))
	var h0 := rad_to_deg(acos(clampf(c, -1.0, 1.0)))
	return noon_minutes + h0 / 15.0 * 60.0

static func sunrise_minutes(lat_deg: float, decl_deg: float, noon_minutes: float) -> float:
	return 2.0 * noon_minutes - sunset_minutes(lat_deg, decl_deg, noon_minutes)

## 平地上 1 m 高物体的影长（m）；太阳在地平线下返回 INF。
static func shadow_length_per_meter(elevation_deg: float) -> float:
	if elevation_deg <= 0.05:
		return INF
	return 1.0 / tan(deg_to_rad(elevation_deg))
