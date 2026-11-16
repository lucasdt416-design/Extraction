shader_type spatial;
render_mode cull_disabled, diffuse_burley, world_vertex_coords;

// Blades of grass drawn as MultiMesh tufts (see scripts/world/grass.gd).
// They lean with a wind that rolls across the map in gusts, part round anyone
// walking through them, and are thrown flat by a blast.

uniform vec3 root_color : source_color = vec3(0.13, 0.21, 0.09);
uniform vec3 tip_color : source_color = vec3(0.40, 0.52, 0.22);
uniform vec3 dry_color : source_color = vec3(0.62, 0.52, 0.30);
uniform vec3 bloom_color : source_color = vec3(0.35, 0.95, 0.85);
uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
// xyz: where a body's feet are, w: how wide it parts the grass.
uniform vec4 pushers[8];
// xyz: centre of the last blast, w: its radius.  blast_force fades to 0.
uniform vec4 blast;
uniform float blast_force = 0.0;

varying float height;
varying float tint;
varying float bloom;
varying float blade;

void vertex() {
	height = UV.y;
	vec3 root = MODEL_MATRIX[3].xyz;
	tint = INSTANCE_CUSTOM.r;
	blade = UV.x;
	bloom = INSTANCE_CUSTOM.g;
	float bend = height * height;
	// Wind: slow gusts sweeping east, with a quick shiver on top.
	float gust = texture(noise_tex, root.xz * 0.012 + vec2(TIME * 0.045, TIME * 0.02)).r;
	float shiver = sin(TIME * 3.1 + root.x * 1.7 + root.z * 2.3) * 0.25;
	vec2 lean = vec2(1.0, 0.35) * (gust * gust * 0.55 + shiver * 0.06 * (0.4 + gust));
	float press = 0.0;
	for (int i = 0; i < 8; i++) {
		vec3 away = root - pushers[i].xyz;
		float reach = pushers[i].w;
		float close_by = (1.0 - smoothstep(reach * 0.35, reach, length(away.xz))) * step(abs(away.y), 1.4) * step(0.01, reach);
		lean += normalize(away.xz + vec2(0.0001)) * close_by * 0.5;
		press = max(press, close_by);
	}
	vec3 from_blast = root - blast.xyz;
	float shock = (1.0 - smoothstep(blast.w * 0.3, blast.w, length(from_blast))) * blast_force;
	lean += normalize(from_blast.xz + vec2(0.0001)) * shock * 0.9;
	press = max(press, shock);
	VERTEX.xz += lean * bend * 0.6;
	VERTEX.y -= (press * 0.55 + length(lean) * 0.25) * bend * (VERTEX.y - root.y);
	NORMAL = normalize(vec3(lean.x * 0.5, 1.0, lean.y * 0.5));
}

void fragment() {
	// Each tuft sits somewhere between green and sun-dried, and each blade in
	// it a shade apart, so a patch reads as many plants and not one colour.
	vec3 tip = mix(tip_color, dry_color, smoothstep(0.55, 1.0, tint) * 0.8);
	vec3 color = mix(root_color, tip, pow(height, 0.8));
	color *= 0.8 + blade * 0.4;
	ALBEDO = color * mix(0.6, 1.0, height);
	ROUGHNESS = 0.85;
	SPECULAR = 0.2;
	BACKLIGHT = tip_color * 0.35 * height;
	// A few stems carry a lit seed head.
	float head = bloom * smoothstep(0.78, 0.95, height);
	EMISSION = bloom_color * head * 2.6;
	ALBEDO = mix(ALBEDO, bloom_color * 0.4, head);
}
