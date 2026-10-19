shader_type spatial;
// Agua estilizada y barata (compatible con GL Compatibility / móvil):
// color por profundidad horneada en una textura, espuma en la orilla y olas suaves.
render_mode blend_mix, cull_back, diffuse_lambert, specular_schlick_ggx, depth_draw_opaque;

uniform sampler2D water_data : filter_linear, repeat_disable;
uniform float world_size = 256.0;
uniform vec4 deep_color : source_color = vec4(0.06, 0.29, 0.48, 1.0);
uniform vec4 shallow_color : source_color = vec4(0.22, 0.74, 0.78, 1.0);
uniform vec4 fresh_color : source_color = vec4(0.24, 0.6, 0.55, 1.0);
uniform vec4 foam_color : source_color = vec4(0.96, 0.98, 1.0, 1.0);
uniform float wave_height = 0.07;
uniform float night = 0.0;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float w = sin(wpos.x * 0.32 + TIME * 1.1) * cos(wpos.z * 0.27 + TIME * 0.85);
	VERTEX.y += w * wave_height;
}

void fragment() {
	vec2 uv = (wpos.xz + world_size * 0.5) / world_size;
	float outside = step(1.0, max(abs(uv.x - 0.5), abs(uv.y - 0.5)) * 2.0);
	vec4 d = texture(water_data, clamp(uv, vec2(0.0), vec2(1.0)));
	float depth = mix(d.r, 1.0, outside);
	float shore = d.g * (1.0 - outside);
	float fresh = d.b * (1.0 - outside);
	vec3 col = mix(shallow_color.rgb, deep_color.rgb, smoothstep(0.0, 0.55, depth));
	col = mix(col, fresh_color.rgb, fresh * 0.65);
	float band = sin(TIME * 1.4 - shore * 9.0 + wpos.x * 0.15 + wpos.z * 0.1) * 0.5 + 0.5;
	float foam = shore * smoothstep(0.35, 0.95, band) + smoothstep(0.82, 1.0, shore);
	col = mix(col, foam_color.rgb, clamp(foam, 0.0, 0.85));
	float sp = sin(wpos.x * 1.6 + TIME * 1.2) * sin(wpos.z * 1.8 - TIME * 1.05);
	col += vec3(0.05) * smoothstep(0.65, 1.0, sp) * (1.0 - night);
	ALBEDO = col;
	ALPHA = mix(0.5, 0.93, smoothstep(0.0, 0.3, depth));
	ROUGHNESS = 0.18;
	SPECULAR = 0.55;
}
