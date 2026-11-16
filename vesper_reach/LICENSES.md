# Asset provenance

Architecture, terrain layout, procedural decorations, props, weapons, and source code in this package were created for this task. V2 additionally uses the licensed nature models listed below. The world uses original names and designs; no Marathon meshes, textures, logos, maps, or audio were extracted or included.

The colony billboard atlas `godot/art/textures/colony-signage.png` was generated with the built-in image generation tool for this project. Its design prompt is recorded in `source/signage-prompt.txt`.

The following material textures are supplied by Poly Haven under CC0 1.0. They are bundled locally, with source URLs and checksums in `godot/art/textures/sources.json`:

- Rocky Trail — Amal Kumar: https://polyhaven.com/a/rocky_trail
- Forest Ground 01 — Rob Tuytel: https://polyhaven.com/a/forrest_ground_01
- Concrete Floor 01 — Rob Tuytel: https://polyhaven.com/a/concrete_floor_01
- Poly Haven license information: https://polyhaven.com/license

Diffuse, OpenGL normal, and roughness maps were downloaded for each material. Terrain shaders use diffuse and normal maps. Roughness maps are included for further material authoring; the supplied shaders currently use scalar roughness and variation.

Blender and Godot executables are development tools and are not redistributed in this package.

## V2 environment sources (CC0 1.0)

- [Island Tree 01](https://polyhaven.com/a/island_tree_01), Poly Haven: normalized to a 14 m base height and simplified to approximately 32,000 triangles for game use.
- [Rock Moss Set 01](https://polyhaven.com/a/rock_moss_set_01), Kless Gyzen / Poly Haven: six rocks normalized and simplified to approximately 2,400 triangles each.
- [Industrial Sunset (Pure Sky)](https://polyhaven.com/a/industrial_sunset_puresky), Sergej Majboroda (original) and Jarod Guest (sky edits): 2K HDR panorama used for the sky and environment lighting.

Exact download URLs and verified source checksums are recorded in `godot/data/v2-sources.json`. Renderable derived GLBs and their textures are included. The optional high-resolution vendor source downloads are recreated by `source/v2/fetch_environment.py`.
