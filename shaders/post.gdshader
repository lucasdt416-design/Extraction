shader_type canvas_item;

// The lens: a soft vignette, a little colour fringing toward the corners,
// and fine grain so flat areas don't look computer-clean.

uniform sampler2D screen : hint_screen_texture, filter_linear;
uniform float vignette = 0.3;
uniform float fringe = 0.0016;
uniform float grain = 0.022;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 offset = SCREEN_UV - 0.5;
	float r2 = dot(offset, offset);
	vec2 shift = offset * r2 * fringe * 4.0;
	vec3 color = vec3(
		texture(screen, SCREEN_UV + shift).r,
		texture(screen, SCREEN_UV).g,
		texture(screen, SCREEN_UV - shift).b);
	color *= 1.0 - vignette * smoothstep(0.12, 0.62, r2);
	color += (hash(SCREEN_UV * 913.0 + fract(TIME) * 17.0) - 0.5) * grain;
	COLOR = vec4(color, 1.0);
}
