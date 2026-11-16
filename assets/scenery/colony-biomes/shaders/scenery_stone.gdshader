shader_type spatial;
render_mode diffuse_burley;
uniform sampler2D rock_detail : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 tint : source_color = vec4(.22,.24,.24,1);
uniform float stratum = .25;
varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
    world_pos = (MODEL_MATRIX * vec4(VERTEX,1.0)).xyz;
    world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

void fragment() {
    vec3 normal = normalize(world_normal);
    vec3 axis = pow(abs(normal),vec3(4.0));
    axis /= max(dot(axis,vec3(1.0)),.001);
    vec3 p = world_pos*.93;
    vec3 texture_color = texture(rock_detail,p.zy).rgb*axis.x +
                         texture(rock_detail,p.xz).rgb*axis.y +
                         texture(rock_detail,p.xy).rgb*axis.z;
    float grain = dot(texture_color,vec3(.32,.51,.17));
    float band = sin(world_pos.y*21.0+world_pos.x*.32+world_pos.z*.27+grain*1.75);
    float layers = mix(1.0,mix(.67,1.20,smoothstep(-.32,.55,band)),stratum);
    ALBEDO = tint.rgb * (.50+grain*1.38) * layers;
    ROUGHNESS = mix(.91,.64,grain);
}
