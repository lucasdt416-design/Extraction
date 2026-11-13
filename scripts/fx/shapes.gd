class_name Shapes
extends RefCounted

# Mesh generators. Godot's BoxMesh has knife-sharp edges, which is most of why
# a scene built from boxes looks like a scene built from boxes. A rounded box
# catches a highlight along every edge the way a real manufactured object does.

static var _cache: Dictionary = {}

# A box with rounded edges and corners. `steps` is how many extra rows of
# vertices each bevel gets: 1 is a clean chamfer-ish round (cheap, for small
# parts), 3 is smooth (for large props seen up close).
static func rounded_box(size: Vector3, radius: float, steps: int = 2) -> ArrayMesh:
	radius = minf(radius, minf(size.x, minf(size.y, size.z)) * 0.5 - 0.0005)
	var key := "%.3f,%.3f,%.3f,%.3f,%d" % [size.x, size.y, size.z, radius, steps]
	if _cache.has(key):
		return _cache[key]
	var half := size * 0.5
	var inner := half - Vector3.ONE * radius
	# Coordinates along each axis: the flat span, plus rows across each bevel.
	var axes: Array = []
	for axis in 3:
		var coords: Array[float] = []
		for i in steps + 1:
			coords.append(-half[axis] + radius * float(i) / float(steps + 1))
		coords.append(-inner[axis])
		coords.append(inner[axis])
		for i in range(steps, -1, -1):
			coords.append(half[axis] - radius * float(i) / float(steps + 1))
		axes.append(coords)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for face in 6:
		var w := face / 2            # the axis this face is perpendicular to
		var u := (w + 1) % 3
		var v := (w + 2) % 3
		var sign := 1.0 if face % 2 == 0 else -1.0
		var cu: Array[float] = axes[u]
		var cv: Array[float] = axes[v]
		var grid: Array = []
		for i in cu.size():
			var row: Array = []
			for j in cv.size():
				var p := Vector3.ZERO
				p[w] = half[w] * sign
				p[u] = cu[i]
				p[v] = cv[j]
				# Pull the point onto the rounded surface: nearest point of the
				# inner box, pushed out by the radius.
				var core := p.clamp(-inner, inner)
				var normal := (p - core).normalized()
				row.append([core + normal * radius, normal])
			grid.append(row)
		for i in cu.size() - 1:
			for j in cv.size() - 1:
				var quad: Array = [grid[i][j], grid[i + 1][j], grid[i + 1][j + 1], grid[i][j + 1]]
				var order: Array = [0, 1, 2, 0, 2, 3] if sign < 0.0 else [0, 2, 1, 0, 3, 2]
				for index: int in order:
					st.set_normal(quad[index][1])
					st.add_vertex(quad[index][0])
	var mesh := st.commit()
	_cache[key] = mesh
	return mesh
