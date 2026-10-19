shader_type spatial;
// Barra de progreso/salud orientada a la cámara (sin texturas, muy barata).
render_mode unshaded, cull_disabled, shadows_disabled, depth_draw_never;

uniform float progress : hint_range(0.0, 1.0) = 0.5;
uniform vec4 fill_color : source_color = vec4(0.35, 0.85, 0.35, 1.0);
uniform vec4 back_color : source_color = vec4(0.06, 0.05, 0.04, 0.78);
uniform vec4 border_color : source_color = vec4(0.95, 0.88, 0.7, 0.9);

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	vec2 uv = UV;
	float bx = 0.025;
	float by = 0.18;
	vec4 c = back_color;
	bool border = uv.x < bx || uv.x > 1.0 - bx || uv.y < by || uv.y > 1.0 - by;
	if (border) {
		c = border_color;
	} else if ((uv.x - bx) / (1.0 - 2.0 * bx) < progress) {
		c = fill_color;
	}
	ALBEDO = c.rgb;
	ALPHA = c.a;
}
