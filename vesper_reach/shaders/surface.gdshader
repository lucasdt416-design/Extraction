shader_type spatial;
render_mode diffuse_burley;
uniform vec4 base_color:source_color=vec4(.6,.6,.6,1);
uniform float metallic=0.0;
uniform float roughness=.75;
uniform float texture_scale=.5;
uniform float texture_strength=.45;
uniform sampler2D albedo_detail:source_color,filter_linear_mipmap_anisotropic,repeat_enable;
uniform sampler2D normal_detail:hint_normal,filter_linear_mipmap_anisotropic,repeat_enable;
varying vec3 wp;
varying vec3 wn;
void vertex(){wp=(MODEL_MATRIX*vec4(VERTEX,1)).xyz;wn=normalize(MODEL_NORMAL_MATRIX*NORMAL);}
void fragment(){
 vec3 weights=pow(abs(wn),vec3(6.));weights/=max(weights.x+weights.y+weights.z,.001);
 vec3 tx=texture(albedo_detail,wp.zy*texture_scale).rgb;
 vec3 ty=texture(albedo_detail,wp.xz*texture_scale).rgb;
 vec3 tz=texture(albedo_detail,wp.xy*texture_scale).rgb;
 vec3 detail=tx*weights.x+ty*weights.y+tz*weights.z;
 float grain=dot(detail,vec3(.333));
 ALBEDO=base_color.rgb*mix(vec3(1.),vec3(.38)+detail*1.05,texture_strength);
 ROUGHNESS=clamp(roughness+grain*.15,.1,1.);
 METALLIC=metallic;
 NORMAL_MAP=texture(normal_detail,wp.xz*texture_scale+wp.xy*texture_scale*.2).rgb;
 NORMAL_MAP_DEPTH=.22;
}
