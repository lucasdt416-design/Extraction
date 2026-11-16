shader_type spatial;

// Walls, floors and ground. Mapped in world space, so a box of any size gets
// correctly scaled detail with no UVs: panel seams, a painted band along the
// foot of walls, grime that gathers at the ground and streaks from the top,
// per-panel tone variation, and broad patchiness on floors.

uniform vec3 base_color : source_color = vec3(0.8);
uniform vec3 band_color : source_color = vec3(0.3);
uniform float band_height = 0.0;      // 0 = no band
uniform float panel_size = 2.0;       // metres between seams
uniform float seam_strength = 0.55;
uniform float roughness_base = 0.65;
uniform float metallic_base = 0.05;
uniform float wear = 1.0;
uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
// Photographed surface detail (CC0, from the Vesper Reach kit): fine colour
// variation and real relief, so a flat box catches light like poured concrete.
uniform sampler2D detail_albedo : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D detail_normal : hint_normal, repeat_enable, filter_linear_mipmap_anisotropic;
uniform float detail_scale = 0.4;
uniform float detail_strength = 0.5;
uniform float relief = 0.8;

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec3 an = abs(world_normal);
	bool is_floor = an.y > 0.5;
	vec2 uv = is_floor ? world_pos.xz : (an.x > 0.5 ? world_pos.zy : world_pos.xy);

	float broad = texture(noise_tex, uv * 0.021).r;
	float mid = texture(noise_tex, uv * 0.13).r;
	float fine = texture(noise_tex, uv * 0.9).r;

	vec2 cell = uv / panel_size;
	vec2 f = fract(cell);
	vec2 edge = min(f, 1.0 - f) * panel_size;
	float seam = 1.0 - smoothstep(0.004, 0.02, min(edge.x, edge.y));
	float bevel = smoothstep(0.02, 0.05, min(edge.x, edge.y));
	float tone = hash(floor(cell));

	vec3 color = base_color;
	if (is_floor) {
		// Broad stains and lighter worn patches.
		color *= mix(0.78, 1.08, broad);
		color *= mix(0.92, 1.04, mid);
	} else {
		if (band_height > 0.0) {
			color = mix(band_color, color, smoothstep(band_height - 0.006, band_height + 0.006, world_pos.y));
		}
		color *= 0.95 + tone * 0.09;
		// Dirt kicked up from the ground, and rain streaks down from the top.
		float splash = 1.0 - smoothstep(0.0, 0.7 + mid * 0.8, world_pos.y);
		color *= 1.0 - splash * 0.32 * wear;
		float streak = texture(noise_tex, vec2(uv.x * 0.35, 0.37)).r;
		color *= 1.0 - smoothstep(0.55, 0.9, streak) * 0.14 * wear * mid;
	}
	color *= mix(1.0, 0.94 + fine * 0.1, wear);
	color *= 1.0 - seam * seam_strength;
	color *= 0.97 + bevel * 0.03;

	// Two scales of the photographed detail, so it neither tiles up close nor
	// turns to mush at a distance.
	vec3 near_detail = texture(detail_albedo, uv * detail_scale).rgb;
	vec3 far_detail = texture(detail_albedo, uv * detail_scale * 0.23 + 0.37).rgb;
	vec3 detail = mix(near_detail, far_detail, 0.4);
	float grain = dot(detail, vec3(0.333));
	color *= mix(vec3(1.0), detail * 2.0, detail_strength);

	// The mesh's own tangents know nothing about this world-space mapping, so
	// build the frame from the same axes the texture was projected along.
	vec3 t_world = is_floor ? vec3(1.0, 0.0, 0.0) : (an.x > 0.5 ? vec3(0.0, 0.0, 1.0) : vec3(1.0, 0.0, 0.0));
	vec3 b_world = is_floor ? vec3(0.0, 0.0, 1.0) : vec3(0.0, -1.0, 0.0);
	TANGENT = normalize((VIEW_MATRIX * vec4(t_world, 0.0)).xyz);
	BINORMAL = normalize((VIEW_MATRIX * vec4(b_world, 0.0)).xyz);
	vec3 bump = texture(detail_normal, uv * detail_scale).rgb;
	// Panel seams are grooves: tilt the surface towards the nearest one.
	vec2 toward = (f - 0.5) * 2.0;
	vec2 groove = (abs(toward.x) > abs(toward.y) ? vec2(sign(toward.x), 0.0) : vec2(0.0, sign(toward.y)))
		* (1.0 - smoothstep(0.0, 0.035, min(edge.x, edge.y))) * seam_strength;
	bump.xy = clamp(bump.xy + groove * 0.45, 0.0, 1.0);
	NORMAL_MAP = bump;
	NORMAL_MAP_DEPTH = relief;

	ALBEDO = color;
	ROUGHNESS = clamp(roughness_base + (mid - 0.5) * 0.3 * wear + seam * 0.2 + (0.5 - grain) * 0.35, 0.05, 1.0);
	METALLIC = metallic_base;
}
