shader_type spatial;
render_mode diffuse_burley;
varying vec3 wp;
varying vec3 wn;
uniform sampler2D rock_albedo:source_color,filter_linear_mipmap_anisotropic,repeat_enable;
uniform sampler2D rock_normal:hint_normal,filter_linear_mipmap_anisotropic,repeat_enable;
uniform sampler2D forest_albedo:source_color,filter_linear_mipmap_anisotropic,repeat_enable;
uniform sampler2D forest_normal:hint_normal,filter_linear_mipmap_anisotropic,repeat_enable;
uniform float lift=0.0; // how far the host has lowered the map
float hash(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
float noise(vec2 p){vec2 i=floor(p),f=fract(p);f=f*f*(3.-2.*f);return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1)),f.x),f.y);}
void vertex(){wp=(MODEL_MATRIX*vec4(VERTEX,1)).xyz;wn=normalize(MODEL_NORMAL_MATRIX*NORMAL);}
void fragment(){
 vec3 weights=pow(abs(wn),vec3(5));weights/=max(dot(weights,vec3(1)),.001);
 vec3 rock=texture(rock_albedo,wp.zy*.14).rgb*weights.x+texture(rock_albedo,wp.xz*.14).rgb*weights.y+texture(rock_albedo,wp.xy*.14).rgb*weights.z;
 vec3 soil=texture(forest_albedo,wp.xz*.32).rgb;
 float moss=smoothstep(.42,.78,wn.y)*(1.-smoothstep(190.,290.,wp.y+lift));
 float broad=noise(wp.xz*.025)*.55+noise(wp.xz*.13)*.25+noise(wp.xz*.65)*.2;
 vec3 mosscolor=mix(vec3(.05,.10,.03),vec3(.13,.20,.07),broad);
 ALBEDO=mix(rock*vec3(.38,.45,.48),soil*.2+mosscolor*.85,moss)*(.76+broad*.42);
 float snow=smoothstep(310.,390.,wp.y+lift+noise(wp.xz*.027)*55.)*smoothstep(.38,.82,wn.y);
 ALBEDO=mix(ALBEDO,vec3(.67,.74,.77),snow);
 ROUGHNESS=.92;
 NORMAL_MAP=mix(texture(rock_normal,wp.xz*.14).rgb,texture(forest_normal,wp.xz*.32).rgb,moss);
 NORMAL_MAP_DEPTH=.65;
}
