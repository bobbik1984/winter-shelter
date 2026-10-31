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
	w_normal = normalize(mat3(MODEL_MATRIX) * NORMAL);
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float up = normalize(w_normal).y;
	float n = vnoise(w_pos * noise_scale) - 0.5;
	float threshold = mix(1.0, -0.25, snow_amount);
	float cover = smoothstep(threshold, threshold + snow_softness, up + n * noise_strength);
	vec3 col = mix(base_color.rgb, snow_color.rgb, cover);
	ALBEDO = col;
	ROUGHNESS = mix(base_roughness, 0.74, cover);
	SPECULAR = mix(0.12, 0.3, cover);
}
