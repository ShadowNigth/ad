shader_type sky;
// Cielo estilizado y barato: degradado de día/noche, disco del sol, luna con
// halo, estrellas que parpadean y nubes suaves que se desplazan con el viento.
// Los colores y la nubosidad los ajustan el ciclo de día/noche y el clima.

uniform vec3 sky_top : source_color = vec3(0.24, 0.52, 0.88);
uniform vec3 sky_horizon : source_color = vec3(0.68, 0.83, 0.94);
uniform vec3 ground_horizon : source_color = vec3(0.6, 0.74, 0.84);
uniform vec3 ground_bottom : source_color = vec3(0.12, 0.26, 0.44);
uniform float sky_curve = 0.12;
uniform float ground_curve = 0.05;
uniform vec3 sun_color : source_color = vec3(1.0, 0.95, 0.85);
uniform float sun_disc = 1.0;
uniform float moon_disc = 0.0;
uniform float stars = 0.0;
uniform float cloud_cover = 0.35;
uniform vec3 cloud_light : source_color = vec3(1.0, 1.0, 1.0);
uniform vec3 cloud_shadow : source_color = vec3(0.62, 0.68, 0.78);
uniform float cloud_speed = 1.0;
uniform int detail = 1;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p, int octaves) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		if (i >= octaves) {
			break;
		}
		v += a * noise(p);
		p = p * 2.03 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return v;
}

void sky() {
	vec3 dir = normalize(EYEDIR);
	float v_angle = acos(clamp(dir.y, -1.0, 1.0));
	vec3 col;
	if (dir.y >= 0.0) {
		float c = 1.0 - v_angle / (PI * 0.5);
		col = mix(sky_horizon, sky_top, clamp(1.0 - pow(1.0 - c, 1.0 / max(sky_curve, 0.001)), 0.0, 1.0));
	} else {
		float c = (v_angle - PI * 0.5) / (PI * 0.5);
		col = mix(ground_horizon, ground_bottom, clamp(1.0 - pow(1.0 - c, 1.0 / max(ground_curve, 0.001)), 0.0, 1.0));
	}
	float above = smoothstep(-0.02, 0.08, dir.y);
	// Estrellas: celdas en proyección estereográfica, con parpadeo.
	if (stars > 0.01 && dir.y > 0.0 && !AT_CUBEMAP_PASS) {
		vec2 sp = dir.xz / (dir.y + 1.0) * 160.0;
		vec2 cell = floor(sp);
		float h = hash(cell);
		if (h > 0.985) {
			vec2 f = fract(sp) - vec2(hash(cell + 3.1), hash(cell + 7.7)) * 0.6 - 0.2;
			float d = length(f);
			float tw = 0.6 + 0.4 * sin(TIME * (1.5 + h * 4.0) + h * 40.0);
			float bright = smoothstep(0.16, 0.0, d) * tw * (h - 0.985) / 0.015;
			col += vec3(0.9, 0.93, 1.0) * bright * stars * smoothstep(0.0, 0.25, dir.y);
		}
	}
	if (LIGHT0_ENABLED) {
		float sd = dot(dir, normalize(LIGHT0_DIRECTION));
		// Sol: disco brillante y halo.
		if (sun_disc > 0.001) {
			float disc = smoothstep(0.99935, 0.99965, sd);
			float glow = pow(max(sd, 0.0), 260.0) * 0.7 + pow(max(sd, 0.0), 10.0) * 0.12;
			col += sun_color * (disc * 5.0 + glow) * sun_disc * above;
		}
		// Luna: disco pálido con manchas y un halo frío.
		if (moon_disc > 0.001) {
			float mdisc = smoothstep(0.99945, 0.99972, sd);
			vec3 side = normalize(cross(normalize(LIGHT0_DIRECTION), vec3(0.0, 1.0, 0.0)) + vec3(0.0001));
			vec2 muv = vec2(dot(dir, side), dir.y - normalize(LIGHT0_DIRECTION).y) * 90.0;
			float spots = 0.82 + 0.18 * noise(muv * 1.7);
			float halo = pow(max(sd, 0.0), 400.0) * 0.35 + pow(max(sd, 0.0), 30.0) * 0.06;
			col += vec3(0.92, 0.94, 1.0) * (mdisc * 1.6 * spots + halo) * moon_disc * above;
		}
	}
	// Nubes en un plano proyectado, desvanecidas cerca del horizonte.
	if (cloud_cover > 0.01 && dir.y > 0.0) {
		vec2 uv = dir.xz / (dir.y + 0.12) * 0.9 + vec2(TIME * 0.006, TIME * 0.002) * cloud_speed;
		int oct = AT_CUBEMAP_PASS ? 2 : (detail > 0 ? 4 : 2);
		float n = fbm(uv * 1.4, oct);
		float thr = 1.0 - cloud_cover;
		float cov = smoothstep(thr - 0.08, thr + 0.22, n);
		float shade = smoothstep(thr, thr + 0.4, fbm(uv * 1.4 + vec2(0.06, 0.05), oct));
		vec3 cc = mix(cloud_light, cloud_shadow, shade * 0.8);
		col = mix(col, cc, cov * 0.9 * smoothstep(0.0, 0.22, dir.y));
	}
	COLOR = col;
}
