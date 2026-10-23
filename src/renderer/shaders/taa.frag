#version 460

layout(location = 0) out vec4 out_color;
layout(location = 1) out vec4 out_history;

layout(push_constant) uniform PushConstants {
    float gamma;
} resolve;

layout(set = 0, binding = 0) uniform sampler2D scene_color;
layout(set = 0, binding = 1) uniform sampler2D velocity;
layout(set = 0, binding = 2) uniform sampler2D history;

#include "gamma.glsl"

void main() {
    ivec2 pixel = ivec2(gl_FragCoord.xy);
    vec4 color = texelFetch(scene_color, pixel, 0);
    vec4 motion = texelFetch(velocity, pixel, 0);

    // Pass-through until the history accumulation lands in the next ticket.
    out_color = vec4(apply_gamma(color.rgb, resolve.gamma), 1.0);
    out_history = vec4(color.rgb, motion.z);
}
