shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

// 45° 正交剖面雪洞专属 Shader（对标参考图右上角 SHELTER DESIGN CUTAWAY VIEW）：
// - 外雪丘表面 (is_interior_surface=0, is_cut_face=0)：清冷天光蓝白积雪 + 微风雪脊明暗起伏；
// - 剖切横截面 (is_cut_face=1)：冷静的冰岩蓝压实雪层断面 + 水平压实层理纹 + 内外缘冰晶高光边（绝不惨白过曝）；
// - 内腔拱壁与阶梯雪床 (is_interior_surface=1)：冷气坑深邃暮蓝阴影 + 高床与拱顶 2700K 暖烛光次表面散射。

uniform vec3 lantern_local_pos = vec3(0.15, 0.88, -1.05);
uniform float lantern_warmth : hint_range(0.0, 1.0) = 1.0;
uniform float is_interior_surface : hint_range(0.0, 1.0) = 0.0;
uniform float is_cut_face : hint_range(0.0, 1.0) = 0.0;

varying vec3 local_pos;
varying vec3 local_n;

void vertex() {
	local_pos = VERTEX;
	local_n = NORMAL;
}

void fragment() {
	// 1. 外层雪丘：带微起伏纹路的冷调积雪
	float drift_wave = sin(local_pos.x * 3.2 + local_pos.z * 2.4) * 0.5 + 0.5;
	float height_tint = clamp((local_pos.y + 0.5) / 3.2, 0.0, 1.0);
	vec3 outer_snow = mix(vec3(0.54, 0.67, 0.83), vec3(0.76, 0.85, 0.95), height_tint * 0.75 + drift_wave * 0.25);

	// 2. 1.5m 压实雪层横截面（Cut Face）：冷冰蓝色调 + 压实雪层纹理（比外雪顶略深，形成清晰断面体积感）
	float strata = sin(local_pos.y * 18.0 + sin(local_pos.x * 2.2) * 1.6) * 0.5 + 0.5;
	float block_joint = smoothstep(0.92, 0.99, abs(sin(local_pos.x * 3.8 + floor(local_pos.y * 3.0) * 1.3)));
	vec3 cut_base = mix(vec3(0.46, 0.58, 0.74), vec3(0.58, 0.70, 0.85), strata * 0.65 + height_tint * 0.35);
	cut_base = mix(cut_base, vec3(0.38, 0.50, 0.66), block_joint * 0.28);

	// 3. 内腔拱顶与冷气槽：深暮蓝冰壁底色
	float pit_darkness = clamp((local_pos.y + 0.55) / 1.4, 0.0, 1.0);
	vec3 inner_ice = mix(vec3(0.20, 0.31, 0.48), vec3(0.36, 0.50, 0.68), pit_darkness);

	vec3 col = mix(outer_snow, inner_ice, is_interior_surface);
	col = mix(col, cut_base, is_cut_face);

	// 4. 洞内 2700K 烛灯暖光：仅温暖内腔拱壁与高床，不冲白正前横截面
	float dist = length(local_pos - lantern_local_pos);
	float warm_atten = clamp(1.0 - dist / 2.45, 0.0, 1.0);
	warm_atten = warm_atten * warm_atten * lantern_warmth;
	vec3 candle_glow = vec3(0.98, 0.64, 0.24);

	float interior_weight = is_interior_surface * (1.0 - is_cut_face);
	float cut_inner_rim = is_cut_face * clamp(1.0 - dist / 1.55, 0.0, 1.0) * 0.22;
	col = mix(col, candle_glow, clamp(warm_atten * interior_weight * 0.82 + cut_inner_rim, 0.0, 0.85));

	ALBEDO = col;
	EMISSION = candle_glow * (warm_atten * interior_weight * 0.36);
	ROUGHNESS = mix(0.86, 0.74, is_cut_face);
	SPECULAR = 0.18;
}
