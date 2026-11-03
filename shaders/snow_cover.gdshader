shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// 统一积雪材质：任何网格（程序化云杉、AI 生成 .glb、远山）套上它，
// 都会按「世界空间法线朝向」自动积雪：朝上的面白、陡面/下垂面露出底色。
// 只依赖法线与世界坐标，不依赖 UV，因此对外部资产同样有效。

uniform vec4 base_color : source_color = vec4(0.07, 0.16, 0.11, 1.0);
uniform vec4 snow_color : source_color = vec4(0.90, 0.94, 1.0, 1.0);
// 0 = 无雪，1 = 几乎全覆盖。 [TUNE]
uniform float snow_amount : hint_range(0.0, 1.0) = 0.72;
// 积雪边缘的过渡宽度（法线点积空间）。
uniform float snow_softness : hint_range(0.01, 0.6) = 0.16;
// 噪声让雪线不规则（世界空间，单位 1/m）。
uniform float noise_scale = 1.7;
uniform float noise_strength : hint_range(0.0, 0.6) = 0.22;
uniform float base_roughness : hint_range(0.0, 1.0) = 0.92;
// 遮挡透视：挡在玩家前面的树按抖动镂空，保证玩家永远可见。
// focus_pos 由相机 rig 经 "occlusion_fade" 组每帧推送；occlusion_radius 为屏幕空间半径（tan 单位）。
uniform bool occlusion_fade = false;
uniform vec3 focus_pos = vec3(0.0);
uniform float occlusion_radius = 0.26;
// D16 建造特写：半径放大到盖满画面、强度到 1 = 镜头与工地之间的树完全消失（影子不受影响）。
uniform float occlusion_strength = 0.85;
// 风摆（T3.1）：树冠随高度二次方偏向下风，阵风调制；静态截图里也能读出风向。
uniform float sway_amount = 0.0;
uniform vec2 wind_dir = vec2(1.0, 0.0);
// 逆光可读性（V5）：边缘光让逆光下的枯木 / 岩石不至于糊成纯黑剪影。
uniform float rim_amount : hint_range(0.0, 1.0) = 0.0;

varying vec3 w_normal;
varying vec3 w_pos;

float hash13(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.1, 0.2, 0.3));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(mix(hash13(i), hash13(i + vec3(1, 0, 0)), f.x),
			mix(hash13(i + vec3(0, 1, 0)), hash13(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash13(i + vec3(0, 0, 1)), hash13(i + vec3(1, 0, 1)), f.x),
			mix(hash13(i + vec3(0, 1, 1)), hash13(i + vec3(1, 1, 1)), f.x), f.y),
		f.z);
}

void vertex() {
	if (sway_amount > 0.0) {
		vec2 origin = MODEL_MATRIX[3].xz;
		float phase = dot(origin, vec2(0.37, 0.21));
		float gust = 0.65 + 0.35 * sin(TIME * 0.55 + phase * 0.13);
		float h = max(VERTEX.y, 0.0);
		float s = (0.55 + 0.45 * sin(TIME * 1.7 + phase)) * gust * sway_amount * h * h * 0.006;
		VERTEX.xz += normalize(wind_dir) * s;
	}
	w_normal = normalize(mat3(MODEL_MATRIX) * NORMAL);
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// 阴影 pass（平行光正交投影）不镂空，否则地上的树影会变成网点；
	// 代价：正交相机模式下也不做透视镂空（俯视基本不遮挡）。
	bool ortho_pass = PROJECTION_MATRIX[3][3] > 0.5;
	if (occlusion_fade && !ortho_pass) {
		vec3 fv = (VIEW_MATRIX * vec4(focus_pos + vec3(0.0, 0.9, 0.0), 1.0)).xyz;
		if (-VERTEX.z < -fv.z - 1.2) {
			vec2 d = VERTEX.xy / -VERTEX.z - fv.xy / -fv.z;
			float k = (1.0 - smoothstep(occlusion_radius * 0.55, occlusion_radius, length(d))) * occlusion_strength;
			// 贴着镜头的树：离主体距离的 20% 以内全透、45% 以外不变（比例是纯几何，推拉镜头时一起缩放）
			k = max(k, 1.0 - smoothstep(-fv.z * 0.2, -fv.z * 0.45, -VERTEX.z));
			// 4x4 Bayer 抖动
			ivec2 c = ivec2(FRAGCOORD.xy) % 4;
			int idx = c.x + c.y * 4;
			float bayer[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
			if (k > (bayer[idx] + 0.5) / 16.0) discard;
		}
	}
	float up = normalize(w_normal).y;
	float n = vnoise(w_pos * noise_scale) - 0.5;
	float threshold = mix(1.0, -0.25, snow_amount);
	float cover = smoothstep(threshold, threshold + snow_softness, up + n * noise_strength);
	vec3 col = mix(base_color.rgb, snow_color.rgb, cover);
	ALBEDO = col;
	ROUGHNESS = mix(base_roughness, 0.74, cover);
	SPECULAR = mix(0.12, 0.3, cover);
	RIM = rim_amount;
	RIM_TINT = 0.6;
}
