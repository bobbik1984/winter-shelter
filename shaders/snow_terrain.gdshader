shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

// M1->M2 雪面与岩壁覆雪 Shader（主创定标版）：
// 1. 消除直线过曝白光带，采用自然暖クリーム色受光雪面 + 群青冰蓝背风雪面；
// 2. 加入程序化风蚀雪纹 (Sastrugi) 法线微扰动与冰晶闪点 (Sparkle)；
// 3. 陡坡自然裸露深灰层状山岩，且岩壁朝上微台地自动覆雪。

// 指向太阳的世界方向，由 AtmosphereSetup / WeatherController 通过 "sun_receivers" 组推送。
uniform vec3 sun_dir_world = vec3(-0.7, 0.16, -0.7);
// 低画质：跳过法线扰动的两次额外 fbm、detail 用一次 vnoise（GraphicsSettings 设置）。
uniform bool low_quality = false;
// 开发热力图（F3，T1.2）：按雪深着色，D5 门槛处画等值线。snow_depth 是归一化值（÷2.5 m）。
uniform bool debug_depth = false;
// 风的去向（世界 xz，单位向量）：风蚀雪纹沿它拉长（TerrainBuilder 从 WindData 设置，随 L3 地图旋转）。
uniform vec2 wind_blow = vec2(1.0, 0.0);
// 薄雪露地（L5 如实表现）：雪深低于 bare_full_m 时地面 / 枯草从雪里露出，高于 bare_none_m 完全覆盖（米）。
uniform float bare_full_m = 0.08;
uniform float bare_none_m = 0.45;

varying float snow_depth;
varying vec3 world_normal;
varying vec3 world_pos;
varying float slope_v;
varying float height_v;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	mat2 rot = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));
	for (int i = 0; i < 4; i++) {
		v += a * vnoise(p);
		p = rot * p * 2.05;
		a *= 0.5;
	}
	return v;
}

void vertex() {
	snow_depth = COLOR.r;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	slope_v = 1.0 - clamp(world_normal.y, 0.0, 1.0);
	height_v = clamp(VERTEX.y / 8.5, 0.0, 1.0);
}

void fragment() {
	// 1. 风蚀雪波纹（Sastrugi）：在"顺风 / 横风"坐标里拉长，风向变了纹理跟着转（wind_blow = (1,0) 时与旧版一致）
	vec2 wb = normalize(wind_blow);
	float w_along = dot(world_pos.xz, wb);
	float w_across = dot(world_pos.xz, vec2(-wb.y, wb.x));
	vec2 wind_uv = vec2(w_along * 0.28 + w_across * 0.14, w_across * 0.52 - w_along * 0.12);
	float drift_n = low_quality ? vnoise(wind_uv * 1.6) * 0.8 + 0.1 : fbm(wind_uv);
	float detail_n = low_quality ? vnoise(world_pos.xz * 1.35) : fbm(world_pos.xz * 1.35);

	// 2. 微法线扰动：让雪面呈现真实的风积凹凸起伏，告别塑料平滑感
	vec3 bumped_world_n = world_normal;
	if (!low_quality) {
		float eps = 0.25;
		float nx = fbm(wind_uv + vec2(eps, 0.0)) - drift_n;
		float nz = fbm(wind_uv + vec2(0.0, eps)) - drift_n;
		bumped_world_n = normalize(world_normal + vec3(-nx * 0.75, 0.0, -nz * 0.75));
		NORMAL = normalize((VIEW_MATRIX * vec4(bumped_world_n, 0.0)).xyz);
	}

	float up = clamp(bumped_world_n.y, 0.0, 1.0);
	vec3 sun_dir = normalize(sun_dir_world);
	// 逆光：太阳很低，用"朝太阳的水平分量 + 坡面朝上"判断受光，避免整片雪面发黑
	float sun_face = clamp(dot(bumped_world_n, normalize(sun_dir + vec3(0.0, 0.55, 0.0))), 0.0, 1.0);
	vec3 view_w = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
	float forward_scatter = pow(clamp(dot(-view_w, sun_dir), 0.0, 1.0), 6.0);

	// 3. 参考图冷暖色盘：受光面暖金奶油白，背风坡冰钴蓝，凹坑深群青
	vec3 snow_sunlit = vec3(0.95, 0.90, 0.82);
	vec3 snow_mid_cool = vec3(0.68, 0.80, 0.95);
	vec3 snow_deep_drift = vec3(0.50, 0.66, 0.90);

	vec3 snow_col = mix(snow_mid_cool, snow_sunlit, smoothstep(0.10, 0.78, sun_face));
	snow_col = mix(snow_col, snow_deep_drift, smoothstep(0.35, 0.92, snow_depth) * (1.0 - sun_face * 0.55));
	snow_col += (drift_n - 0.5) * vec3(0.045, 0.050, 0.065);

	// 3b. 薄雪露地：雪越薄，地面（深褐土 / 帚石楠）与枯草越多地露出来，斑块由噪声决定。
	//     让"这里雪很薄"不用探针也能看出来（第 3 / 4 关、风蚀脊顶）。
	float depth_m = snow_depth * 2.5;
	float thin = 1.0 - smoothstep(bare_full_m, bare_none_m, depth_m);
	float patch_n = low_quality ? vnoise(world_pos.xz * 0.9) : fbm(world_pos.xz * 0.9);
	float bare = smoothstep(0.42, 0.72, thin * (0.35 + 0.9 * patch_n));
	// 草丛：平滑值噪声的高值斑点（圆润、不规则；不能用 floor 网格，会出现方块像素）
	float tuft = smoothstep(0.74, 0.86, vnoise(world_pos.xz * 3.3 + vec2(17.0, 5.0))) * smoothstep(0.15, 0.5, thin);
	vec3 ground_col = mix(vec3(0.20, 0.18, 0.16), vec3(0.50, 0.43, 0.30), detail_n);
	snow_col = mix(snow_col, ground_col * mix(0.75, 1.15, sun_face), max(bare, tuft * 0.85));

	// 4. 陡坡岩层裸露与台地覆雪过渡（复刻参考图左侧与山脊的覆雪岩体）
	vec3 rock_dark = vec3(0.19, 0.21, 0.25);
	vec3 rock_warm = vec3(0.31, 0.28, 0.26);
	vec3 rock_col = mix(rock_dark, rock_warm, detail_n * sun_face);
	float rock_mask = smoothstep(0.34, 0.62, slope_v + (detail_n - 0.5) * 0.18 - snow_depth * 0.12);
	vec3 base = mix(snow_col, rock_col, rock_mask);

	// 5. 高频雪晶闪点 (Sparkle)
	float sparkle_grid = hash21(floor(world_pos.xz * 14.0));
	float sparkle = step(0.965, sparkle_grid) * (sun_face * 0.5 + forward_scatter * 1.5) * (1.0 - rock_mask) * (1.0 - bare) * 0.22;
	base += vec3(sparkle);
	// 朝太阳方向看去的雪面：暖金逆光辉
	base = mix(base, vec3(1.0, 0.82, 0.62), forward_scatter * 0.35 * (1.0 - rock_mask) * (1.0 - bare * 0.7));

	ALBEDO = clamp(base, vec3(0.08), vec3(0.96));
	if (debug_depth) {
		float m = snow_depth * 2.5;   // 还原为米
		vec3 c = vec3(1.0, 0.4, 0.15);
		if (m < 2.0) { c = vec3(1.0, 0.8, 0.2); }
		if (m < 1.5) { c = vec3(0.2, 0.85, 0.6); }
		if (m < 0.9) { c = vec3(0.3, 0.6, 1.0); }
		if (m < 0.3) { c = vec3(0.55, 0.55, 0.6); }
		float line = 1.0 - smoothstep(0.0, 0.04, abs(m - 0.3));
		line = max(line, 1.0 - smoothstep(0.0, 0.04, abs(m - 0.9)));
		line = max(line, 1.0 - smoothstep(0.0, 0.04, abs(m - 1.5)));
		line = max(line, 1.0 - smoothstep(0.0, 0.04, abs(m - 2.0)));
		ALBEDO = mix(c, vec3(0.05), line);
	}
	ROUGHNESS = max(mix(0.82, 0.96, rock_mask) - smoothstep(0.3, 0.9, snow_depth) * 0.12, bare * 0.95);
	SPECULAR = mix(0.28, 0.12, rock_mask);
	AO = mix(0.72, 1.0, up) * mix(0.85, 1.0, drift_n);
}
