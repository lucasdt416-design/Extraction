shader_type canvas_item;

// The lens: a soft vignette, a little colour fringing toward the corners,
// fine grain so flat areas don't look computer-clean, and the grade -- cool
// teal shade, warm light, a firmer S-curve -- that gives the raid its look.

uniform sampler2D screen : hint_screen_texture, filter_linear;
uniform float vignette = 0.3;
uniform float fringe = 0.0016;
uniform float grain = 0.022;
uniform vec3 shade_tint = vec3(0.88, 0.99, 1.08);
uniform vec3 light_tint = vec3(1.02, 1.0, 0.96);
uniform float curve = 0.22;
uniform float vibrance = 0.18;

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
	// Split tone by brightness.
	float luma = dot(color, vec3(0.2126, 0.7152, 0.0722));
	color *= mix(shade_tint, light_tint, smoothstep(0.15, 0.75, luma));
	// S-curve for contrast, about the middle grey.
	vec3 eased = color * color * (3.0 - 2.0 * color);
	color = mix(color, clamp(eased, 0.0, 1.0), curve * step(color, vec3(1.0)));
	// Vibrance: lifts dull colours more than strong ones.
	float strongest = max(color.r, max(color.g, color.b));
	float weakest = min(color.r, min(color.g, color.b));
	float sat = strongest - weakest;
	luma = dot(color, vec3(0.2126, 0.7152, 0.0722));
	color = mix(vec3(luma), color, 1.0 + vibrance * (1.0 - sat));
	color *= 1.0 - vignette * smoothstep(0.12, 0.62, r2);
	color += (hash(SCREEN_UV * 913.0 + fract(TIME) * 17.0) - 0.5) * grain;
	COLOR = vec4(color, 1.0);
}
