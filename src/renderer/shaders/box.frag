#version 460

layout(location = 0) in vec3 v_normal;
layout(location = 1) in vec3 v_color;
layout(location = 2) in vec3 v_world_position;

layout(location = 0) out vec4 out_color;

layout(set = 0, binding = 0) uniform Camera {
    mat4 view;
    mat4 projection;
    vec4 light_direction;
    vec4 ambient;
    vec4 gamma;
    mat4 light_view_projection;
} camera;

layout(set = 0, binding = 1) uniform sampler2DShadow shadow_map;

#include "gamma.glsl"

const vec3 SUN_COLOR = vec3(1.0, 0.98, 0.94);
const float SHADOW_NORMAL_OFFSET = 0.04;
const float SHADOW_DEPTH_BIAS = 0.0006;

float sun_visibility(vec3 world_position, vec3 normal, vec3 to_light) {
    vec4 light_position = camera.light_view_projection *
        vec4(world_position + normal * SHADOW_NORMAL_OFFSET, 1.0);
    vec3 projected = light_position.xyz / light_position.w;
    vec3 uv = projected * 0.5 + 0.5;
    if (any(lessThan(uv, vec3(0.0))) || any(greaterThan(uv, vec3(1.0)))) {
        return 1.0;
    }

    float bias = max(SHADOW_DEPTH_BIAS, 0.003 * (1.0 - dot(normal, to_light)));
    vec2 texel = 1.0 / vec2(textureSize(shadow_map, 0));
    float visibility = 0.0;
    for (int x = -1; x <= 1; x++) {
        for (int y = -1; y <= 1; y++) {
            visibility += texture(
                shadow_map,
                vec3(uv.xy + vec2(x, y) * texel, projected.z - bias)
            );
        }
    }
    return visibility / 9.0;
}

void main() {
    vec3 normal = normalize(v_normal);
    vec3 to_light = normalize(-camera.light_direction.xyz);
    float diffuse = max(dot(normal, to_light), 0.0);
    float visibility = sun_visibility(v_world_position, normal, to_light);

    vec3 color = v_color * (camera.ambient.rgb + diffuse * SUN_COLOR * visibility);

    out_color = vec4(apply_gamma(color, camera.gamma.x), 1.0);
}
