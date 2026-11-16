shader_type spatial;
render_mode diffuse_burley;
uniform vec4 paint:source_color=vec4(.65,.69,.7,1);
uniform float metalness=.2;
uniform float base_roughness=.5;
uniform sampler2D surface_albedo:source_color,filter_linear_mipmap_anisotropic,repeat_enable;
uniform sampler2D surface_normal:hint_normal,filter_linear_mipmap_anisotropic,repeat_enable;
varying float local_height;
void vertex(){local_height=VERTEX.y;}
void fragment(){
 vec3 detail=texture(surface_albedo,UV).rgb;
 float grain=dot(detail,vec3(.3,.5,.2));
 float dirt=(1.-smoothstep(.0,.9,local_height))*.10;
 ALBEDO=paint.rgb*(.78+grain*.5)*(1.-dirt);
 ROUGHNESS=clamp(base_roughness+(1.-grain)*.12,.2,.96);
 METALLIC=metalness;
 NORMAL_MAP=texture(surface_normal,UV).rgb;
 NORMAL_MAP_DEPTH=.16;
}
