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
    float coverage = 1.0;
    if (v_uv.x >= 0.0) {
        // The atlas stores the distance to the glyph outline, so one field
        // renders crisply at every size. The derivative sets the antialiasing
        // width, which is what keeps small text from turning into grey mush.
        float distance = texture(atlas, v_uv).r;
        float width = max(fwidth(distance) * 0.5, 0.001);
        coverage = smoothstep(0.5 - width, 0.5 + width, distance);
    }
    out_color = vec4(apply_gamma(v_color.rgb, hud.viewport.z), v_color.a * coverage);
}
