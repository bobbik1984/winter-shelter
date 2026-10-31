shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

// M1 雪面：迎光暖金、背光群青、按坡度/高度/雪深分层。
// 顶点色 R 通道编码归一化雪深，由 terrain_builder.gd 写入。

varying float snow_depth;
varying vec3 world_normal;
varying vec3 world_pos;
varying float slope_v;
varying float height_v;

void vertex() {
	snow_depth = COLOR.r;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	slope_v = 1.0 - clamp(world_normal.y, 0.0, 1.0);
	height_v = clamp(VERTEX.y / 8.0, 0.0, 1.0);
}

void fragment() {
	float up = clamp(world_normal.y, 0.0, 1.0);
	float sun_face = clamp(dot(world_normal, normalize(vec3(-0.55, 0.50, -0.36))), 0.0, 1.0);

	vec3 snow_warm = vec3(0.98, 0.88, 0.72);
	vec3 snow_cool = vec3(0.42, 0.55, 0.78);
	vec3 snow_deep = vec3(0.55, 0.68, 0.90);
	vec3 rock = vec3(0.14, 0.15, 0.18);

	// 朝向太阳的坡面偏暖；背光面偏群青。
	vec3 base = mix(snow_cool, snow_warm, smoothstep(0.12, 0.82, sun_face));
	// 陡坡露出深色岩层；深雪更冷更蓝。
	base = mix(base, rock, smoothstep(0.50, 0.84, slope_v));
	base = mix(base, snow_deep, smoothstep(0.25, 0.95, snow_depth) * 0.45);
	// 高处脊线略亮，低洼处略暗，让起伏可读。
	base *= mix(0.72, 1.08, smoothstep(0.0, 0.85, height_v));

	float ripple = sin(world_pos.x * 1.7 + sin(world_pos.z * 1.3) * 1.4) * 0.5 + 0.5;
	base += vec3(0.018, 0.020, 0.024) * ripple;

	ALBEDO = base;
	ROUGHNESS = mix(0.92, 0.48, smoothstep(0.15, 0.85, snow_depth));
	SPECULAR = mix(0.18, 0.42, up);
	AO = mix(0.62, 1.0, up) * mix(0.80, 1.0, smoothstep(0.0, 1.0, snow_depth));
}
