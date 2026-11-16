# Colony Biomes Scenery Kit

24 original, separate GLBs in metres with ground-based origins.

- Three tree types including a weathered snag.
- Eleven shrub, flower, marsh, and ground-cover types.
- Eight formations including glacial erratics, stream cobbles, layered shale, sandstone fins, salt crust, quartz scree, moss boulders, and columnar basalt.
- Two deadwood props including driftwood and a shelf-fungus log.

The contact sheet uses normalized display sizes. The catalog lists the actual dimensions, triangle counts, asset class, and optional collision boxes. Low plants are designed as decorative meshes. Collider descriptions are in Blender X/Y/Z-up order. For Godot, convert a collider position (x, y, z) to (x, z, -y) and size to (x, z, y).

GLBs carry their base materials. For the map look, apply the included Godot stone shader to each rock surface, set `tint` to that surface's original albedo, and bind the supplied `rock_albedo.jpg` to `rock_detail`. Stronger strata work well on shale and sandstone. The shared rock detail texture is Amal Kumar's [Rocky Trail](https://polyhaven.com/a/rocky_trail), CC0 1.0. The mesh geometry and assigned colors are original for the project.
