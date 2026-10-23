#version 460

layout(location = 0) in vec4 v_color;

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
    out_color = vec4(apply_gamma(v_color.rgb, camera.gamma.x), v_color.a);
}
