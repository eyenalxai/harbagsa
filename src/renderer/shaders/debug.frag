#version 460

layout(location = 0) in vec4 v_color;

layout(location = 0) out vec4 out_color;

#include "camera.glsl"

#include "gamma.glsl"

void main() {
    out_color = vec4(apply_gamma(v_color.rgb, camera.gamma.x), v_color.a);
}
