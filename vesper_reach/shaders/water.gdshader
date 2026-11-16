shader_type spatial;
render_mode cull_disabled, diffuse_burley;
uniform vec3 deep_color:source_color=vec3(.018,.15,.17);
uniform vec3 crest_color:source_color=vec3(.18,.48,.42);
uniform float wave_scale=.4;
varying vec3 world_position;
void vertex(){
 world_position=(MODEL_MATRIX*vec4(VERTEX,1)).xyz;
 VERTEX.y+=(sin(world_position.x*.06+TIME*.6)+sin(world_position.z*.085-TIME*.4))*.08*wave_scale;
}
void fragment(){
 vec2 p=world_position.xz;
 float a=sin(p.x*.35+p.y*.18+TIME*.9);
 float b=cos(p.y*.41-p.x*.15-TIME*.7);
 float c=sin(p.x*1.4+p.y*.9+TIME*1.2);
 float fresnel=pow(1.0-clamp(dot(normalize(NORMAL),normalize(VIEW)),0.0,1.0),3.0);
 ALBEDO=mix(deep_color,crest_color,.20+fresnel*.5+(a*b)*.07);
 METALLIC=.38;ROUGHNESS=.17+abs(c)*.05;SPECULAR=.75;
 NORMAL_MAP=normalize(vec3(a*.18+c*.07,b*.16,1.0))*.5+.5;NORMAL_MAP_DEPTH=.6;
}
