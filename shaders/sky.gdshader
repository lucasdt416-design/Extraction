shader_type sky;

// Late afternoon over the plateau: a gradient sky, a sun with a wide halo,
// two layers of high cloud lit from the sun's side, and a pale ringed planet
// sitting low over the horizon.

uniform vec3 top_color : source_color = vec3(0.13, 0.31, 0.66);
uniform vec3 horizon_color : source_color = vec3(0.93, 0.76, 0.62);
uniform vec3 ground_color : source_color = vec3(0.30, 0.25, 0.23);
uniform vec3 sun_color : source_color = vec3(1.0, 0.86, 0.7);
uniform vec3 planet_dir = vec3(0.55, 0.32, -0.77);
uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;

float fbm(vec2 p) {
	return texture(noise_tex, p).r * 0.6 + texture(noise_tex, p * 2.7 + 0.3).r * 0.28 + texture(noise_tex, p * 6.1).r * 0.12;
}

void sky() {
	vec3 dir = EYEDIR;
	float up = max(dir.y, 0.0);
	vec3 color = mix(horizon_color, top_color, pow(up, 0.42));

	float to_sun = distance(dir, LIGHT0_DIRECTION);
	float halo = exp(-to_sun * 3.2);
	color += sun_color * halo * 0.55;
	color += sun_color * smoothstep(0.045, 0.035, to_sun) * 12.0;

	// The planet: a disc shaded by the sun, with a thin ring.
	vec3 pd = normalize(planet_dir);
	float pr = 0.17;
	float d = distance(dir, pd);
	if (d < pr * 2.4) {
		vec3 side = normalize(cross(pd, vec3(0.0, 1.0, 0.0)));
		vec3 upv = cross(side, pd);
		vec2 local = vec2(dot(dir - pd, side), dot(dir - pd, upv)) / pr;
		float disc = smoothstep(1.0, 0.97, length(local));
		vec3 n = vec3(local, sqrt(max(1.0 - dot(local, local), 0.0)));
		vec3 light = normalize(vec3(dot(LIGHT0_DIRECTION, side), dot(LIGHT0_DIRECTION, upv), 0.35));
		float lit = smoothstep(-0.15, 0.55, dot(n, light));
		float bands = 0.85 + 0.15 * sin(local.y * 14.0 + sin(local.x * 3.0));
		vec3 planet = mix(color * 0.92, vec3(0.93, 0.86, 0.80) * bands, lit * 0.75);
		color = mix(color, planet, disc * 0.8);
		vec2 ring_uv = vec2(local.x * 0.48 + local.y * 0.26, local.y - local.x * 0.2);
		float ring = length(vec2(ring_uv.x, ring_uv.y * 3.4));
		float ring_mask = smoothstep(0.72, 0.76, ring) * smoothstep(1.0, 0.96, ring);
		float behind = step(0.0, ring_uv.y) * disc;
		color = mix(color, vec3(0.95, 0.88, 0.8), ring_mask * 0.4 * (1.0 - behind));
	}

	// Clouds, projected onto a plane overhead and faded out at the horizon.
	vec2 plane = dir.xz / (dir.y + 0.16);
	float fade = smoothstep(0.02, 0.22, dir.y);
	float high = smoothstep(0.56, 0.86, fbm(plane * 0.11 + vec2(0.2, 0.7)));
	float wisps = smoothstep(0.58, 0.95, fbm(plane * vec2(0.05, 0.19) + vec2(0.6, 0.1)));
	vec3 cloud_lit = mix(vec3(0.80, 0.72, 0.74), vec3(1.0, 0.88, 0.76), clamp(halo * 1.6 + 0.3, 0.0, 1.0));
	color = mix(color, cloud_lit, clamp(high * 0.6 + wisps * 0.3, 0.0, 1.0) * fade);

	if (dir.y < 0.0) {
		color = mix(horizon_color * 0.8, ground_color, smoothstep(0.0, -0.25, dir.y));
	}
	COLOR = color;
}
