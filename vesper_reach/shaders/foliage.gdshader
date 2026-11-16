shader_type spatial;
render_mode cull_disabled,diffuse_burley;
uniform vec4 leaf_color:source_color=vec4(.07,.20,.05,1);
varying vec3 wp;
void vertex(){
 wp=(MODEL_MATRIX*vec4(VERTEX,1.)).xyz;
 float wind=sin(TIME*1.2+wp.x*.4+wp.z*.2)+sin(TIME*.7+wp.z*.7)*.4;
 VERTEX.x+=wind*.07*clamp(VERTEX.y*.12,0.,1.);
 VERTEX.z+=wind*.04*clamp(VERTEX.y*.12,0.,1.);
}
void fragment(){
 float variation=sin(wp.x*7.3+wp.y*3.7+wp.z*2.8)*.14+.86;
 ALBEDO=leaf_color.rgb*variation;
 ROUGHNESS=.88;
 BACKLIGHT=leaf_color.rgb*.28;
}
