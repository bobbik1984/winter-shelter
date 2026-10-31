shader_type sky;

// 夕阳天空：读场景第一盏 DirectionalLight3D 的方向，
// 地平线在朝向太阳的一侧更暖，背向太阳一侧偏冷紫蓝。
// 取代 ProceduralSkyMaterial（透视/移轴相机需要真实天空；D1 的 Canvas 背景只适用于纯正交）。

uniform vec3 zenith_color : source_color = vec3(0.12, 0.24, 0.48);
uniform vec3 horizon_cool : source_color = vec3(0.62, 0.70, 0.86);
uniform vec3 horizon_warm : source_color = vec3(0.98, 0.70, 0.44);
uniform vec3 ground_color : source_color = vec3(0.34, 0.42, 0.58);
uniform float sky_curve = 0.42;
uniform float warm_spread = 2.4;
uniform float sun_size = 0.012;
uniform float sun_glow = 0.35;

void sky() {
	vec3 dir = EYEDIR;
	vec3 sun = normalize(LIGHT0_DIRECTION);
	vec2 h_dir = normalize(dir.xz + vec2(1e-5));
	vec2 h_sun = normalize(sun.xz + vec2(1e-5));
	float toward = max(dot(h_dir, h_sun), 0.0);
	vec3 horizon = mix(horizon_cool, horizon_warm, pow(toward, warm_spread));

	float up = clamp(dir.y, 0.0, 1.0);
	vec3 col = mix(horizon, zenith_color, pow(up, sky_curve));
	// 太阳附近的光晕
	float sd = max(dot(dir, sun), 0.0);
	col += LIGHT0_COLOR * pow(sd, 24.0) * sun_glow * (1.0 - up * 0.6);
	col += LIGHT0_COLOR * smoothstep(1.0 - sun_size, 1.0 - sun_size * 0.6, sd) * 2.0;

	if (dir.y < 0.0) {
		col = mix(horizon, ground_color, clamp(-dir.y * 3.0, 0.0, 1.0));
	}
	COLOR = col;
}
