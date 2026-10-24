#version 460

layout(set = 0, binding = 0) uniform sampler2D atlas;

layout(location = 0) in vec4 v_color;
layout(location = 1) in vec2 v_uv;

layout(location = 0) out vec4 out_color;

layout(push_constant) uniform PushConstants {
    vec4 viewport;
} hud;

#include "gamma.glsl"

void main() {
    // The atlas is rasterized at the device pixel size and sits on the pixel
    // grid, so the sample is already the coverage of this pixel: no threshold,
    // no derivative, no reconstruction.
    float coverage = 1.0;
    if (v_uv.x >= 0.0) {
        coverage = texture(atlas, v_uv).r;
    }
    out_color = vec4(apply_gamma(v_color.rgb, hud.viewport.z), v_color.a * coverage);
}
