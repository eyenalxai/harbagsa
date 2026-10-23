#version 460

layout(location = 0) in vec3 v_normal;
layout(location = 1) in vec3 v_color;

layout(location = 0) out vec4 out_color;

layout(set = 0, binding = 0) uniform Camera {
    mat4 view;
    mat4 projection;
    vec4 light_direction;
    vec4 ambient;
    vec4 gamma;
} camera;

#include "gamma.glsl"

void main() {
    vec3 normal = normalize(v_normal);
    vec3 to_light = normalize(-camera.light_direction.xyz);
    float diffuse = max(dot(normal, to_light), 0.0);

    vec3 color = v_color * (camera.ambient.rgb + diffuse * vec3(1.0, 0.98, 0.94));

    out_color = vec4(apply_gamma(color, camera.gamma.x), 1.0);
}
