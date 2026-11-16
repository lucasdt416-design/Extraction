shader_type sky;
uniform vec3 zenith:source_color=vec3(.045,.18,.29);
uniform vec3 horizon:source_color=vec3(.48,.69,.74);
uniform vec3 sun_direction=vec3(-.45,.24,.68);
float hash(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
float noise(vec2 p){vec2 i=floor(p),f=fract(p);f=f*f*(3.-2.*f);return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y);}
void sky(){
 vec3 d=normalize(EYEDIR);float h=max(d.y,0.0);
 vec3 col=mix(horizon,zenith,pow(h,.48));
 float sun=dot(d,normalize(sun_direction));
 col+=vec3(1.0,.65,.33)*pow(max(sun,0.),45.)*.28;
 col+=vec3(1.0,.87,.63)*smoothstep(.9996,.99985,sun)*3.;
 if(d.y>.02){
  vec2 uv=d.xz/(d.y+.18)*1.8;
  float n=noise(uv)*.55+noise(uv*2.1)*.28+noise(uv*4.3)*.12+noise(uv*9.)*.05;
  float cloud=smoothstep(.55,.76,n)*smoothstep(.02,.17,d.y);
  col=mix(col,vec3(.88,.84,.72),cloud*.6);
 }
 vec3 planet_dir=normalize(vec3(.62,.46,-.68));
 float disc=dot(d,planet_dir);float mask=smoothstep(.9910,.9915,disc);
 float band=sin((d.y-d.x*.35)*180.)*.025+sin(d.y*46.)*.03;
 float shade=clamp(dot(d,normalize(vec3(-.6,.3,-.8)))*2.,.1,1.);
 vec3 planet=vec3(.64,.72,.64)*shade+band;
 col=mix(col,planet,mask*.8);
 float ring_plane=abs(dot(d-planet_dir,normalize(vec3(.2,.95,.25))));
 float ring_mask=(1.-smoothstep(.003,.006,ring_plane))*smoothstep(.982,.987,disc)*(1.-smoothstep(.991,.992,disc));
 col=mix(col,vec3(.75,.72,.58),ring_mask*.38);
 COLOR=col;
}
