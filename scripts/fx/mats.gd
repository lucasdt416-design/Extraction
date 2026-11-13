class_name Mats
extends RefCounted

# Material and texture factory. The level is built from boxes, so the look
# comes from here: generated panel and concrete textures mapped in world space
# (triplanar), which means a box of any size gets correctly scaled detail with
# no UV work and no image files.

static var _cache: Dictionary = {}

# kind: "panel" (seamed wall plating), "concrete" (floors, rough), "metal"
# (crates, props), "plain" (no texture).
static func surface(color: Color, kind: String = "panel", roughness: float = 0.7, metallic: float = 0.0) -> StandardMaterial3D:
	var key := "s%s%s%.2f%.2f" % [color.to_html(), kind, roughness, metallic]
	if _cache.has(key):
		return _cache[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	mat.metallic = metallic
	if kind != "plain":
		var maps: Array = _maps(kind)
		mat.albedo_texture = maps[0]
		mat.normal_enabled = true
		mat.normal_texture = maps[1]
		mat.normal_scale = 0.9 if kind == "panel" else 0.5
		mat.uv1_triplanar = true
		mat.uv1_world_triplanar = true
		var tile := 0.5 if kind == "panel" else (0.22 if kind == "concrete" else 1.0)
		mat.uv1_scale = Vector3(tile, tile, tile)
	_cache[key] = mat
	return mat

# Unshaded-looking light source surface: strips, screens, visors, beacons.
static func glow(color: Color, energy: float = 3.0) -> StandardMaterial3D:
	var key := "g%s%.1f" % [color.to_html(), energy]
	if _cache.has(key):
		return _cache[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color.darkened(0.5)
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = energy
	mat.roughness = 0.4
	_cache[key] = mat
	return mat

# See-through and additive: beams, shields, extract columns, tracers.
static func beam(color: Color, energy: float = 2.0, alpha: float = 0.35) -> StandardMaterial3D:
	var key := "b%s%.1f%.2f" % [color.to_html(), energy, alpha]
	if _cache.has(key):
		return _cache[key]
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(color.r * energy, color.g * energy, color.b * energy, alpha)
	_cache[key] = mat
	return mat

static func glass(color: Color = Color(0.55, 0.75, 0.85)) -> StandardMaterial3D:
	if _cache.has("glass" + color.to_html()):
		return _cache["glass" + color.to_html()]
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(color.r, color.g, color.b, 0.22)
	mat.roughness = 0.05
	mat.metallic = 0.3
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_cache["glass" + color.to_html()] = mat
	return mat

static func _maps(kind: String) -> Array:
	if _cache.has("maps" + kind):
		return _cache["maps" + kind]
	const SIZE := 256
	var noise := FastNoiseLite.new()
	noise.seed = 11
	noise.frequency = 0.11 if kind == "concrete" else 0.012
	noise.fractal_octaves = 5
	var grain := noise.get_seamless_image(SIZE, SIZE)
	var albedo := Image.create(SIZE, SIZE, true, Image.FORMAT_RGB8)
	var height := Image.create(SIZE, SIZE, false, Image.FORMAT_RGB8)
	for y in SIZE:
		for x in SIZE:
			var g := grain.get_pixel(x, y).r
			var shade := (0.93 + g * 0.07) if kind == "concrete" else (0.82 + g * 0.18)
			var h := 0.5 + (g - 0.5) * (0.4 if kind == "concrete" else 0.12)
			if kind == "panel":
				# One plate per tile with a recessed seam round it, a lighter
				# bevel inside the seam, and a faint mid-line.
				var edge := mini(mini(x, SIZE - 1 - x), mini(y, SIZE - 1 - y))
				if edge < 3:
					shade *= 0.5
					h = 0.0
				elif edge < 6:
					shade *= 1.06
					h = 0.75
				elif absi(y - 170) < 1:
					shade *= 0.8
					h = 0.3
			elif kind == "metal":
				shade = 0.8 + g * 0.2 + (0.05 if (x / 4) % 2 == 0 else 0.0)
			albedo.set_pixel(x, y, Color(shade, shade, shade))
			height.set_pixel(x, y, Color(h, h, h))
	albedo.generate_mipmaps()
	height.bump_map_to_normal_map(6.0)
	height.generate_mipmaps()
	var maps := [ImageTexture.create_from_image(albedo), ImageTexture.create_from_image(height)]
	_cache["maps" + kind] = maps
	return maps
