shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

// 45° 正交剖面雪洞专属 Shader（对标参考图右上角 SHELTER DESIGN CUTAWAY VIEW）：
// - 外雪丘表面 (is_interior_surface=0, is_cut_face=0)：清冷天光蓝白积雪 + 微风雪脊明暗起伏；
// - 剖切横截面 (is_cut_face=1)：冷静的冰岩蓝压实雪层断面 + 压实层理纹（与外雪顶及内腔深色洞壁形成清晰三层明暗对比）；
// - 内腔拱壁与阶梯雪床 (is_interior_surface=1)：深邃洞穴冷蓝阴影 + 高床与壁龛 2700K 暖烛光次表面散射。

uniform vec3 lantern_local_pos = vec3(0.18, 0.72, -1.05);
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
	float drift_wave = sin(local_pos.x * 2.8 + local_pos.z * 2.2) * 0.5 + 0.5;
	float height_tint = clamp((local_pos.y + 0.5) / 3.1, 0.0, 1.0);
	vec3 outer_snow = mix(vec3(0.52, 0.65, 0.82), vec3(0.78, 0.87, 0.96), height_tint * 0.72 + drift_wave * 0.28);

	// 2. 1.5m 压实雪层横截面（Cut Face）：冰岩蓝压实雪层断面 + 水平层理与砖缝细节
	float strata = sin(local_pos.y * 16.0 + sin(local_pos.x * 2.0) * 1.4) * 0.5 + 0.5;
	float block_joint = smoothstep(0.93, 0.99, abs(sin(local_pos.x * 3.4 + floor(local_pos.y * 2.8) * 1.5)));
	vec3 cut_base = mix(vec3(0.44, 0.56, 0.73), vec3(0.57, 0.69, 0.84), strata * 0.55 + height_tint * 0.45);
	cut_base = mix(cut_base, vec3(0.36, 0.48, 0.64), block_joint * 0.25);

	// 3. 内腔拱顶与冷气槽：深邃洞穴蓝灰阴影，凸显洞穴进深感
	float depth_shade = clamp((-local_pos.z) / 1.9, 0.0, 1.0);
	float floor_lift = clamp((local_pos.y + 0.55) / 1.8, 0.0, 1.0);
	vec3 inner_ice = mix(vec3(0.14, 0.22, 0.35), vec3(0.26, 0.38, 0.54), (1.0 - depth_shade * 0.55) * floor_lift);

	vec3 col = mix(outer_snow, inner_ice, is_interior_surface);
	col = mix(col, cut_base, is_cut_face);

	// 4. 洞内 2700K 烛灯暖光：集中在壁龛、睡台与内拱壁，营造 Brutal Outside, Cozy Inside
	float dist = length(local_pos - lantern_local_pos);
	float warm_atten = clamp(1.0 - dist / 2.25, 0.0, 1.0);
	warm_atten = pow(warm_atten, 1.65) * lantern_warmth;
	vec3 candle_glow = vec3(1.0, 0.64, 0.22);

	float interior_weight = is_interior_surface * (1.0 - is_cut_face);
	float cut_inner_rim = is_cut_face * clamp(1.0 - dist / 1.35, 0.0, 1.0) * 0.16;
	col = mix(col, candle_glow, clamp(warm_atten * interior_weight * 0.88 + cut_inner_rim, 0.0, 0.88));

	ALBEDO = col;
	EMISSION = candle_glow * (warm_atten * interior_weight * 0.42);
	ROUGHNESS = mix(0.88, 0.76, is_cut_face);
	SPECULAR = 0.16;
}
