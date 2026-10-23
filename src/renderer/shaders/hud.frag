#version 460

layout(location = 0) in vec4 v_color;

layout(location = 0) out vec4 out_color;

layout(push_constant) uniform PushConstants {
    vec4 viewport;
} hud;

#include "gamma.glsl"

void main() {
    out_color = vec4(apply_gamma(v_color.rgb, hud.viewport.z), v_color.a);
}
