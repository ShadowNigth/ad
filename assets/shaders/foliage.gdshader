shader_type spatial;
// Vegetación con viento (palmeras, árboles, arbustos, hierba y flores).
// El peso del balanceo viene horneado en el alfa del color de vértice:
// 0 en la base y hasta 1 en la copa de los árboles (menos en plantas bajas).
// Mismo aspecto que el material de color de vértice del resto del mundo.
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_lambert, specular_disabled, world_vertex_coords;

uniform float wind_strength = 1.0;
uniform float wind_speed = 1.0;
uniform vec2 wind_dir = vec2(0.8, 0.6);

void vertex() {
	float w = COLOR.a * sqrt(max(COLOR.a, 0.0));
	float t = TIME * wind_speed;
	float phase = dot(VERTEX.xz, vec2(0.11, 0.07));
	float sway = sin(t * 1.3 + phase) * 0.6 + sin(t * 2.7 + phase * 1.7) * 0.25;
	vec2 offset = normalize(wind_dir) * sway * 0.22 * wind_strength * w;
	offset += vec2(sin(t * 6.1 + VERTEX.x * 2.3), cos(t * 5.3 + VERTEX.z * 2.1)) * 0.02 * wind_strength * w;
	VERTEX.xz += offset;
	// Color de vértice en sRGB -> lineal (igual que vertex_color_is_srgb).
	COLOR.rgb = mix(pow((COLOR.rgb + vec3(0.055)) * (1.0 / (1.0 + 0.055)), vec3(2.4)), COLOR.rgb * (1.0 / 12.92), lessThan(COLOR.rgb, vec3(0.04045)));
}

void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 1.0;
}
