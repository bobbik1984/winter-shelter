shader_type sky;

// 夕阳天空：太阳方向由 AtmosphereSetup / WeatherController 经 "sun_receivers" 组推送
// （LIGHT0_DIRECTION 在本工程实测拿不到值），
// 地平线在朝向太阳的一侧更暖，背向太阳一侧偏冷紫蓝。
// 取代 ProceduralSkyMaterial（透视/移轴相机需要真实天空；D1 的 Canvas 背景只适用于纯正交）。

uniform vec3 zenith_color : source_color = vec3(0.07, 0.15, 0.36);
uniform vec3 horizon_cool : source_color = vec3(0.62, 0.70, 0.86);
uniform vec3 horizon_warm : source_color = vec3(1.0, 0.64, 0.34);
uniform vec3 ground_color : source_color = vec3(0.34, 0.42, 0.58);
uniform float sky_curve = 0.55;
uniform float warm_spread = 2.4;
uniform float sun_size = 0.00028;
uniform float sun_glow = 0.75;
uniform vec3 sun_dir = vec3(0.70, 0.14, -0.70);
uniform vec3 sun_color : source_color = vec3(1.0, 0.80, 0.56);

// 移轴镜头修正：Godot 画天空背景时按对称视锥重建 EYEDIR，会忽略 Camera3D.frustum_offset，
// 导致天际线 / 太阳画在错误高度。相机 rig 推送真实镜头参数，这里按屏幕像素重建视线。
uniform float lens_fix = 0.0;
uniform float lens_half_t = 0.45;     // tan(vfov/2)
uniform float lens_aspect = 1.777;
uniform float lens_shift_t = 0.0;     // frustum_offset.y / near（tan 空间）
uniform mat3 lens_basis = mat3(1.0);

void sky() {
	vec3 dir = EYEDIR;
	if (lens_fix > 0.5 && !AT_CUBEMAP_PASS) {
		vec2 ndc = vec2(SCREEN_UV.x * 2.0 - 1.0, 1.0 - SCREEN_UV.y * 2.0);
		vec3 v = vec3(ndc.x * lens_half_t * lens_aspect, ndc.y * lens_half_t + lens_shift_t, -1.0);
		dir = normalize(lens_basis * v);
	}
	vec3 sun = normalize(sun_dir);
	vec2 h_dir = normalize(dir.xz + vec2(1e-5));
	vec2 h_sun = normalize(sun.xz + vec2(1e-5));
	float toward = max(dot(h_dir, h_sun), 0.0);
	vec3 horizon = mix(horizon_cool, horizon_warm, pow(toward, warm_spread));

	float up = clamp(dir.y, 0.0, 1.0);
	vec3 col = mix(horizon, zenith_color, pow(up, sky_curve));
	// 太阳附近的光晕
	float sd = max(dot(dir, sun), 0.0);
	col += sun_color * (pow(sd, 18.0) * 0.6 + pow(sd, 400.0) * 1.5) * sun_glow * (1.0 - up * 0.6);
	col += vec3(1.0, 0.90, 0.70) * smoothstep(1.0 - sun_size, 1.0 - sun_size * 0.5, sd) * 3.0;

	// 日落后：天空整体转入暮色 / 夜色；太阳越低地平线暖带越浓
	float day = smoothstep(-0.12, 0.10, sun.y);
	float dusk = 1.0 - smoothstep(0.02, 0.30, sun.y);
	col = mix(col, col * vec3(1.05, 0.82, 0.70), dusk * pow(toward, 1.5) * (1.0 - up) * 0.6);
	vec3 night = mix(vec3(0.05, 0.07, 0.14), vec3(0.01, 0.02, 0.05), pow(up, 0.5));
	col = mix(night, col, day);
	if (dir.y < 0.0) {
		col = mix(mix(night, horizon, day), ground_color * mix(0.15, 1.0, day), clamp(-dir.y * 3.0, 0.0, 1.0));
	}
	COLOR = col;
}
