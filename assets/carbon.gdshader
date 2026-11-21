shader_type canvas_item;
render_mode unshaded;

uniform vec2 canvas_size = vec2(720.0, 1280.0);

void fragment() {
	vec2 pixel = UV * canvas_size;
	vec2 yarn = vec2(pixel.x + pixel.y, pixel.y - pixel.x) * 0.7071;
	float diagonal = smoothstep(0.1, 0.86, 0.5 + 0.5 * cos(yarn.x * 0.88));
	float weave = 0.65 + 0.35 * (0.5 + 0.5 * cos(yarn.y * 2.15 + floor(yarn.x / 7.14) * 2.1));
	float vignette = 1.0 - smoothstep(0.05, 0.77, length((UV - vec2(0.50, 0.45)) * vec2(1.25, 0.90)));
	float broad_light = exp(-abs(UV.x + 0.56 * UV.y - 0.82) * 5.2);
	vec3 graphite = vec3(0.040, 0.044, 0.051)
		+ vec3(0.025, 0.027, 0.031) * vignette
		+ vec3(0.011, 0.013, 0.016) * broad_light
		+ vec3(0.024, 0.026, 0.030) * diagonal * weave * (0.35 + 0.65 * vignette);
	COLOR = vec4(graphite, 1.0);
}
