shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, shadows_disabled;

// Wire mesh for a perimeter fence. Up close it is a lattice you can see
// through; far off, where the wires would only shimmer, it fades to an even veil.

uniform vec3 wire : source_color = vec3(0.2, 0.23, 0.24);
uniform float cells = 9.0;

varying vec3 world_at;

void vertex() {
	world_at = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 along = vec2(world_at.x + world_at.z, world_at.y) * cells;
	vec2 diamond = abs(fract(vec2(along.x + along.y, along.x - along.y) * 0.5) - 0.5);
	float on_wire = step(min(diamond.x, diamond.y), 0.07);
	float away = smoothstep(7.0, 24.0, length(world_at - CAMERA_POSITION_WORLD));
	ALBEDO = wire;
	METALLIC = 0.7;
	ROUGHNESS = 0.5;
	ALPHA = mix(on_wire, 0.3, away);
}
