shader_type spatial;
render_mode blend_mix,depth_draw_opaque;
varying vec3 wp;
uniform sampler2D normal_texture:hint_normal,filter_linear_mipmap_anisotropic,repeat_enable;
void vertex(){wp=(MODEL_MATRIX*vec4(VERTEX,1)).xyz;VERTEX.y+=sin(wp.z*.8+TIME*1.5)*.04+sin(wp.x*1.2+TIME)*.025;}
void fragment(){
 vec2 ripple=vec2(sin(wp.x*.7+wp.z*.35+TIME*1.7),cos(wp.z*.6-wp.x*.3+TIME*1.2))*.11;
 NORMAL_MAP=normalize(vec3(ripple,1.0))*.5+.5;
 NORMAL_MAP_DEPTH=.35;
 ALBEDO=vec3(.018,.07,.065);METALLIC=.35;ROUGHNESS=.20;
}
