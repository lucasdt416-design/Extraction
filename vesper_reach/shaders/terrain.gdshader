shader_type spatial;
render_mode diffuse_burley;
varying vec3 world_position;
varying vec3 biome_color;
uniform sampler2D rock_albedo:source_color,filter_linear_mipmap_anisotropic,repeat_enable;
uniform sampler2D rock_normal:hint_normal,filter_linear_mipmap_anisotropic,repeat_enable;
uniform sampler2D forest_albedo:source_color,filter_linear_mipmap_anisotropic,repeat_enable;
uniform sampler2D forest_normal:hint_normal,filter_linear_mipmap_anisotropic,repeat_enable;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1,311.7))) * 43758.5453); }
float noise(vec2 p) {vec2 i=floor(p), f=fract(p);f=f*f*(3.0-2.0*f);return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y);}
void vertex(){world_position=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;biome_color=COLOR.rgb;}
void fragment(){
 vec2 p=world_position.xz;
 float broad=noise(p*.08)*.55+noise(p*.31)*.3+noise(p*1.7)*.15;
 float fine=noise(p*8.0);
 float greenery=smoothstep(1.1,1.65,biome_color.g/max(biome_color.r,.02));
 vec3 rock=texture(rock_albedo,p*.21).rgb;
 vec3 forest=texture(forest_albedo,p*.29).rgb;
 vec3 detail=mix(rock,forest,greenery);
 ALBEDO=detail*mix(vec3(.72),biome_color*2.1,.45)*(.78+.38*broad);
 ROUGHNESS=.80+fine*.19;
 float nx=noise((p+vec2(.04,0))*3.0)-noise((p-vec2(.04,0))*3.0);
 float ny=noise((p+vec2(0,.04))*3.0)-noise((p-vec2(0,.04))*3.0);
 NORMAL_MAP=mix(texture(rock_normal,p*.21).rgb,texture(forest_normal,p*.29).rgb,greenery);
 NORMAL_MAP_DEPTH=.85;
}
