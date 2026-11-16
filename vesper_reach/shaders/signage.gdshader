shader_type spatial;
render_mode cull_disabled;
uniform sampler2D atlas:source_color,filter_linear_mipmap_anisotropic;
uniform vec2 quadrant=vec2(0,0);
void fragment(){
 vec2 uv=UV*.498+quadrant*.5+vec2(.001);
 vec3 graphic=texture(atlas,uv).rgb;
 ALBEDO=graphic*.75;EMISSION=graphic*.28;ROUGHNESS=.42;
}
