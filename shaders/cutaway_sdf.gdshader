shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_always;

// 雪洞剖面：整个雪丘 / 洞腔 / 冷气坑 / 下倾隧道 / 睡台 / 通风孔都是一套距离场（SDF），
// 在全屏四边形上做光线步进。剖切面 z = 0 是解析平面，所以切口永远平滑；
// 切口上画 poché 描边，靠近洞壁的地方透出烛光暖色。
// 几何公式在 scripts/world/shelter_cutaway_rig.gd 里有 GDScript 镜像（标注线 / 厚度尺寸线用）。
// 改这里的 floor_y / ceil_y / hill_mid 必须同步改那边。

uniform float roof_m = 0.45;                 // 顶厚（来自 Tuning）
uniform vec3 lantern_pos = vec3(0.18, 0.70, -1.08);
uniform float candle = 1.0;
uniform vec3 key_dir = vec3(-0.45, 0.78, 0.50);

const float CAV_BACK = -2.05;
const float CAV_END = 2.35;
const vec3 SNOW = vec3(0.86, 0.92, 1.0);

float smax(float a, float b, float k) {
	float h = max(k - abs(a - b), 0.0) / k;
	return max(a, b) + h * h * k * 0.25;
}
float smin_(float a, float b, float k) { return -smax(-a, -b, k); }

float sd_box(vec3 p, vec3 b) {
	vec3 q = abs(p) - b;
	return length(max(q, 0.0)) + min(max(q.x, max(q.y, q.z)), 0.0);
}
float sd_capsule(vec3 p, vec3 a, vec3 b, float r) {
	vec3 pa = p - a;
	vec3 ba = b - a;
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return length(pa - ba * h) - r;
}

// 外雪丘高度（比旧版低：顶厚由洞腔外扩的壳决定，不再靠一座 1.5 m 厚的大山）
float hill_mid(vec2 xz) {
	float x = xz.x;
	float z = xz.y;
	float nx = (x - 0.10) / 4.05;
	float nz = (z + 0.30) / 3.85;
	float dome = max(0.0, 1.0 - nx * nx * 0.78 - nz * nz * 0.58);
	float shoulder_l = smoothstep(-4.2, -1.6, x) * (1.0 - smoothstep(-0.6, 1.4, x)) * 0.20;
	float shoulder_r = (1.0 - smoothstep(1.8, 4.0, x)) * 0.12;
	float ripple = sin(x * 2.2 + z * 1.6) * 0.03;
	return -0.36 + pow(dome, 0.74) * 1.75 + shoulder_l + shoulder_r + ripple;
}

float floor_y(float x) {
	float f = mix(-0.04, -0.18, clamp((x + 3.8) / 2.45, 0.0, 1.0));   // 下倾隧道
	f = mix(f, -0.50, smoothstep(-1.62, -1.30, x));                    // 冷气坑
	f = mix(f, 0.50, smoothstep(-0.22, -0.02, x));                     // 高床雪台
	return f;
}

float ceil_y(float x, float z) {
	float zn = clamp(abs(z) / 2.05, 0.0, 1.0);
	float taper = sqrt(max(0.06, 1.0 - zn * zn * 0.90));
	float tx = clamp((x + 3.8) / 2.65, 0.0, 1.0);
	float tunnel = 0.30 + sin(tx * 3.14159 * 0.78) * 0.38 + tx * 0.18;
	float cx = clamp((x - 0.42) / 1.95, -1.0, 1.0);
	float dome = -0.05 + pow(max(0.0, 1.0 - cx * cx), 0.56) * 1.62;
	return mix(tunnel, dome, smoothstep(-1.75, -0.95, x)) * taper;
}

// 洞腔（未缩放）：<0 在洞内。左侧 -x 方向敞开 = 入口隧道；+z 方向敞开 = 被剖开的前面。
float cavity(vec3 p) {
	float c = p.y - ceil_y(p.x, p.z);
	float f = floor_y(p.x) - p.y;
	float back = CAV_BACK - p.z;
	float endw = p.x - CAV_END;
	return smax(smax(c, f, 0.18), smax(back, endw, 0.18), 0.18);
}

// 雪体（只含雪，不含陈设）。返回值已乘 0.6 以保证步进安全。
float solid_only(vec3 p) {
	float cd = cavity(p);
	float shell = max(cd - roof_m, -3.5 - p.x);
	float hill = p.y - hill_mid(p.xz);
	float m = smin_(shell, hill, 0.35);
	float box = max(max(-4.15 - p.x, p.x - 3.95), max(max(-0.95 - p.y, -3.45 - p.z), p.z - 0.3));
	float s = max(m, box);
	s = smax(s, -cd, 0.05);
	float vent = max(length(p.xz - vec2(0.25, 0.0)) - 0.13, 1.0 - p.y);
	s = smax(s, -vent, 0.04);
	return s * 0.6;
}

// x = 距离, y = 材质 id：1 雪 / 2 睡袋 / 3 背包 / 4 松针垫 / 5 烛灯金属 / 6 火焰
vec2 map(vec3 p) {
	vec2 r = vec2(solid_only(p), 1.0);
	float bedding = sd_box(p - vec3(1.12, 0.54, -0.88), vec3(0.94, 0.035, 0.52)) - 0.02;
	if (bedding < r.x) r = vec2(bedding, 4.0);
	float bag = sd_capsule(p, vec3(0.52, 0.665, -0.88), vec3(1.70, 0.665, -0.88), 0.165);
	bag = min(bag, sd_box(p - vec3(0.36, 0.70, -0.88), vec3(0.14, 0.09, 0.24)) - 0.05);
	if (bag < r.x) r = vec2(bag, 2.0);
	float pack = sd_box(p - vec3(0.28, 0.76, -1.36), vec3(0.17, 0.23, 0.13)) - 0.04;
	if (pack < r.x) r = vec2(pack, 3.0);
	float lamp = sd_box(p - (lantern_pos + vec3(0.0, -0.10, 0.0)), vec3(0.05, 0.04, 0.05)) - 0.01;
	lamp = min(lamp, sd_box(p - (lantern_pos + vec3(0.0, 0.10, 0.0)), vec3(0.045, 0.012, 0.045)));
	if (lamp < r.x) r = vec2(lamp, 5.0);
	float flame = length(p - lantern_pos) - 0.048;
	if (flame < r.x) r = vec2(flame, 6.0);
	return r;
}

vec3 calc_normal(vec3 p) {
	const vec2 e = vec2(1.0, -1.0) * 0.0035;
	return normalize(e.xyy * map(p + e.xyy).x + e.yyx * map(p + e.yyx).x +
		e.yxy * map(p + e.yxy).x + e.xxx * map(p + e.xxx).x);
}

float soft_shadow(vec3 ro, vec3 rd, float tmax, float k) {
	float res = 1.0;
	float t = 0.04;
	for (int i = 0; i < 28; i++) {
		float h = map(ro + rd * t).x;
		res = min(res, k * h / t);
		t += clamp(h, 0.03, 0.4);
		if (res < 0.01 || t > tmax) break;
	}
	return clamp(res, 0.0, 1.0);
}

float ambient_occ(vec3 p, vec3 n) {
	float occ = 0.0;
	float sca = 1.0;
	for (int i = 0; i < 5; i++) {
		float h = 0.04 + 0.16 * float(i);
		occ += (h - map(p + n * h).x) * sca;
		sca *= 0.8;
	}
	return clamp(1.0 - 1.6 * occ, 0.0, 1.0);
}

vec3 mat_albedo(float id, vec3 p) {
	if (id < 1.5) {
		float n = 0.5 + 0.5 * sin(p.x * 3.1 + p.z * 2.3) * sin(p.z * 2.7 - p.x * 1.1);
		return mix(SNOW * 0.93, SNOW, n);
	}
	if (id < 2.5) return vec3(0.56, 0.27, 0.12);
	if (id < 3.5) return vec3(0.50, 0.37, 0.20);
	if (id < 4.5) return vec3(0.22, 0.28, 0.16);
	return vec3(0.62, 0.68, 0.76);
}

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

void fragment() {
	// —— 由屏幕像素重建世界空间射线（正交 / 透视通用）——
	vec2 ndc = SCREEN_UV * 2.0 - 1.0;
	vec4 va = INV_PROJECTION_MATRIX * vec4(ndc, 0.0, 1.0);
	vec4 vb = INV_PROJECTION_MATRIX * vec4(ndc, 1.0, 1.0);
	va.xyz /= va.w;
	vb.xyz /= vb.w;
	vec3 v_o = (-va.z < -vb.z) ? va.xyz : vb.xyz;
	vec3 v_t = (-va.z < -vb.z) ? vb.xyz : va.xyz;
	vec3 ro = (INV_VIEW_MATRIX * vec4(v_o, 1.0)).xyz;
	vec3 rd = normalize(mat3(INV_VIEW_MATRIX) * normalize(v_t - v_o));

	if (rd.z > -0.0001) discard;

	// —— 剖切面 z = 0 ——
	float t_plane = -ro.z / rd.z;
	vec3 pp = ro + rd * t_plane;
	float d_plane = solid_only(pp) / 0.6;       // 未缩放：<0 即切口在雪里
	float fw = fwidth(d_plane);

	vec3 hit = pp;
	vec3 col;
	bool hit_any = false;

	if (d_plane < 0.0) {
		// 切口：压实雪层断面 + poché
		hit_any = true;
		float strata = 0.5 + 0.5 * sin(pp.y * 21.0 + sin(pp.x * 2.3) * 1.3);
		// 注意：unshaded 的 ALBEDO 是线性空间，0.05 显示出来约等于 sRGB 0.25。
		vec3 base = vec3(0.035, 0.075, 0.17);
		base = mix(base, base * 0.86, smoothstep(0.55, 0.95, strata) * 0.55);
		base *= mix(0.78, 1.0, smoothstep(0.0, 0.45, -d_plane));
		float prox = exp(-length(pp - lantern_pos) * 0.5);
		float warm = exp(-max(cavity(pp), 0.0) * 4.2) * prox * candle;
		col = mix(base, vec3(0.95, 0.42, 0.10), clamp(warm * 1.1, 0.0, 0.8));
	} else {
		// —— 光线步进（从剖切面向里走）——
		float t = t_plane + 0.002;
		float tmax = t_plane + 11.0;
		float id = 0.0;
		for (int i = 0; i < 120; i++) {
			vec3 p = ro + rd * t;
			vec2 h = map(p);
			if (h.x < 0.0015) {
				hit_any = true;
				id = h.y;
				break;
			}
			t += h.x;
			if (t > tmax) break;
		}
		if (hit_any) {
			hit = ro + rd * t;
			vec3 n = calc_normal(hit);
			vec3 alb = mat_albedo(id, hit);
			vec3 L = normalize(key_dir);
			float sh = soft_shadow(hit + n * 0.02, L, 8.0, 10.0);
			float ndl = max(dot(n, L), 0.0);
			float ao = ambient_occ(hit, n);
			vec3 sky_amb = mix(vec3(0.20, 0.27, 0.42), vec3(0.50, 0.62, 0.86), n.y * 0.5 + 0.5);
			// 洞内天光被雪体遮挡：用大尺度 AO 压暗
			float open_sky = soft_shadow(hit + n * 0.03, vec3(0.0, 1.0, 0.0), 4.0, 3.0);
			vec3 lit = sky_amb * mix(0.42, 1.0, open_sky) * ao;
			lit += vec3(0.10, 0.14, 0.24) * (1.0 - open_sky);
			lit += vec3(1.0, 0.96, 0.90) * 0.85 * ndl * sh;

			vec3 to_c = lantern_pos - hit;
			float dist_c = length(to_c);
			vec3 Lc = to_c / dist_c;
			float c_sh = soft_shadow(hit + n * 0.02, Lc, dist_c - 0.05, 8.0);
			float flick = 1.0 + 0.035 * sin(TIME * 9.0) + 0.02 * sin(TIME * 23.0);
			float c_att = 1.0 / (1.0 + dist_c * dist_c * 0.55);
			// 包裹光：雪的次表面散射让背光面也泛暖
			float wrap = clamp((dot(n, Lc) + 0.45) / 1.45, 0.0, 1.0);
			lit += vec3(1.0, 0.62, 0.26) * 6.5 * wrap * c_att * mix(0.25, 1.0, c_sh) * ao * candle * flick;

			col = alb * lit;
			if (id > 5.5) col = vec3(1.0, 0.78, 0.38) * 2.2;
		}
	}

	if (!hit_any) discard;

	// poché 描边：只画在剖切面上（沿雪丘外廓、拱顶内廓、冷气坑、通风井）
	{
		float ol = 1.0 - smoothstep(0.0, 1.0, abs(d_plane) / (fw * 2.4 + 1e-5));
		col = mix(col, vec3(0.003, 0.008, 0.025), ol * 0.97);
	}

	ALBEDO = col;
	vec4 clip = PROJECTION_MATRIX * (VIEW_MATRIX * vec4(hit, 1.0));
	DEPTH = clip.z / clip.w;
}
