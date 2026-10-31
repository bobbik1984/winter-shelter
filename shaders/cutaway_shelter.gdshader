shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

// 45° 正交剖面雪洞 Shader（对应参考图右上角 SHELTER DESIGN CUTAWAY VIEW）：
// - 外壁呈现冷蓝白积雪质感；
// - 剖切断面与拱顶内壁呈现通透冰蓝过渡；
// - 洞内烛灯点亮时（lantern_warmth > 0），内腔底部与拱壁叠加 2700K 暖橙次表面散射光晕。

uniform vec3 lantern_local_pos = vec3(0.0, 0.85, 0.0);
uniform float lantern_warmth : hint_range(0.0, 1.0) = 1.0;
uniform float is_interior_surface : hint_range(0.0, 1.0) = 0.0;
uniform float is_cut_face : hint_range(0.0, 1.0) = 0.0;

varying vec3 local_pos;
varying vec3 world_n;

void vertex() {
	local_pos = VERTEX;
	world_n = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 outer_snow = vec3(0.76, 0.85, 0.96);
	vec3 cut_rim = vec3(0.84, 0.91, 0.99);
	vec3 inner_ice = vec3(0.46, 0.62, 0.84);
	vec3 candle_glow = vec3(1.0, 0.66, 0.26);

	vec3 col = mix(outer_snow, inner_ice, is_interior_surface);
	col = mix(col, cut_rim, is_cut_face);

	float dist = length(local_pos - lantern_local_pos);
	float warm_atten = clamp(1.0 - dist / 2.6, 0.0, 1.0);
	warm_atten = warm_atten * warm_atten * lantern_warmth;

	// 内腔与剖面内缘吸收 2700K 暖烛光
	float interior_weight = max(is_interior_surface, is_cut_face * 0.35);
	col = mix(col, candle_glow, warm_atten * interior_weight * 0.78);

	ALBEDO = col;
	EMISSION = candle_glow * (warm_atten * interior_weight * 0.42);
	ROUGHNESS = mix(0.82, 0.65, is_cut_face);
	SPECULAR = 0.25;
}
