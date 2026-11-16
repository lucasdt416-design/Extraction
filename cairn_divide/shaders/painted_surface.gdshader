shader_type spatial;
render_mode diffuse_burley;
uniform vec4 paint:source_color=vec4(.65,.69,.7,1);
uniform float metalness=.2;
uniform float base_roughness=.5;
uniform float wear=0.0; // 0 new, 1 long abandoned: stains, rust and flaked paint
uniform sampler2D surface_albedo:source_color,filter_linear_mipmap_anisotropic,repeat_enable;
uniform sampler2D surface_normal:hint_normal,filter_linear_mipmap_anisotropic,repeat_enable;
varying float local_height;
varying vec3 wp;
float h21(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
float n2(vec2 p){vec2 i=floor(p),f=fract(p);f=f*f*(3.-2.*f);return mix(mix(h21(i),h21(i+vec2(1,0)),f.x),mix(h21(i+vec2(0,1)),h21(i+vec2(1)),f.x),f.y);}
void vertex(){local_height=VERTEX.y;wp=(MODEL_MATRIX*vec4(VERTEX,1)).xyz;}
void fragment(){
 vec3 detail=texture(surface_albedo,UV).rgb;
 float grain=dot(detail,vec3(.3,.5,.2));
 float dirt=(1.-smoothstep(.0,.9,local_height))*.10;
 ALBEDO=paint.rgb*(.78+grain*.5)*(1.-dirt);
 vec2 face=vec2(wp.x+wp.z,wp.y);
 float patch=n2(face*.55)*.6+n2(face*2.3)*.4;
 float streak=n2(vec2((wp.x+wp.z)*3.1,wp.y*.22));
 float worn=wear*clamp(smoothstep(.5,.72,patch)+smoothstep(.62,.9,streak)*.7+(1.-smoothstep(.0,1.6,local_height))*.5,0.,1.);
 ALBEDO=mix(ALBEDO,vec3(.21,.15,.10)*(.55+grain*.7),worn*.8);
 ROUGHNESS=clamp(base_roughness+(1.-grain)*.12+worn*.3,.2,.96);
 METALLIC=metalness;
 NORMAL_MAP=texture(surface_normal,UV).rgb;
 NORMAL_MAP_DEPTH=.16;
}
