shader_type spatial;
render_mode diffuse_burley;
uniform sampler2D micro_normal:hint_normal,filter_linear_mipmap_anisotropic,repeat_enable;
varying vec3 wp;
float hash(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
float noise(vec2 p){vec2 i=floor(p),f=fract(p);f=f*f*(3.-2.*f);return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y);}
void vertex(){wp=(MODEL_MATRIX*vec4(VERTEX,1)).xyz;}
void fragment(){
 vec2 p=wp.xz;
 float grain=noise(p*5.);
 float patch=noise(p*.22)*.65+noise(p*.61)*.35;
 float water=smoothstep(.56,.69,patch);
 vec3 dry=vec3(.038,.047,.050)*(grain*.24+.86);
 ALBEDO=mix(dry,vec3(.012,.020,.024),water*.8);
 ROUGHNESS=mix(.68,.18,water);
 METALLIC=.08;
 SPECULAR=.65;
 NORMAL_MAP=mix(texture(micro_normal,p*.75).rgb,vec3(.5,.5,1.),water*.96);
 NORMAL_MAP_DEPTH=.12;
}
