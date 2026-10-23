#version 460

layout(location = 0) out vec4 out_color;
layout(location = 1) out vec4 out_history;

layout(push_constant) uniform PushConstants {
    float gamma;
    float weight;
} resolve;

layout(set = 0, binding = 0) uniform sampler2D scene_color;
layout(set = 0, binding = 1) uniform sampler2D velocity;
layout(set = 0, binding = 2) uniform sampler2D history;

#include "gamma.glsl"

const float DEPTH_TRUST_MIN = 0.01;
const float DEPTH_TRUST_MAX = 0.02;
const float CLIP_SIGMA = 1.0;
const float CLIP_EPSILON = 1e-5;

vec3 rgb_to_ycocg(vec3 c) {
    return vec3(
        0.25 * c.r + 0.5 * c.g + 0.25 * c.b,
        0.5 * c.r - 0.5 * c.b,
        -0.25 * c.r + 0.5 * c.g - 0.25 * c.b
    );
}

vec3 ycocg_to_rgb(vec3 c) {
    float t = c.x - c.z;
    return vec3(t + c.y, c.x + c.z, t - c.y);
}

vec3 clip_aabb(vec3 lo, vec3 hi, vec3 p) {
    vec3 e = 0.5 * (hi - lo) + CLIP_EPSILON;
    vec3 v = p - 0.5 * (hi + lo);
    vec3 a = abs(v / e);
    float m = max(a.x, max(a.y, a.z));
    if (m > 1.0) {
        return 0.5 * (hi + lo) + v / m;
    }
    return p;
}

void main() {
    ivec2 extent = textureSize(scene_color, 0);
    ivec2 pixel = clamp(ivec2(gl_FragCoord.xy), ivec2(0), extent - 1);
    vec4 current = texelFetch(scene_color, pixel, 0);
    vec4 motion = texelFetch(velocity, pixel, 0);
    float curr_depth = motion.z;

    vec2 uv = gl_FragCoord.xy / vec2(extent);
    vec2 history_uv = uv + motion.xy;
    vec3 resolved = current.rgb;

    if (resolve.weight > 0.0 &&
        all(greaterThanEqual(history_uv, vec2(0.0))) &&
        all(lessThanEqual(history_uv, vec2(1.0)))) {
        vec3 m1 = vec3(0.0);
        vec3 m2 = vec3(0.0);
        vec3 mn = vec3(1e30);
        vec3 mx = vec3(-1e30);
        for (int y = -1; y <= 1; ++y) {
            for (int x = -1; x <= 1; ++x) {
                ivec2 sample_pixel = clamp(pixel + ivec2(x, y), ivec2(0), extent - 1);
                vec3 c = rgb_to_ycocg(max(texelFetch(scene_color, sample_pixel, 0).rgb, vec3(0.0)));
                m1 += c;
                m2 += c * c;
                mn = min(mn, c);
                mx = max(mx, c);
            }
        }
        vec3 mu = m1 / 9.0;
        vec3 sigma = sqrt(max(m2 / 9.0 - mu * mu, vec3(0.0)));
        vec3 lo = max(mu - CLIP_SIGMA * sigma, mn);
        vec3 hi = min(mu + CLIP_SIGMA * sigma, mx);

        vec2 half_texel = 0.5 / vec2(extent);
        vec2 clamped_uv = clamp(history_uv, half_texel, 1.0 - half_texel);
        vec4 history_sample = textureLod(history, clamped_uv, 0.0);
        vec3 hist = rgb_to_ycocg(max(history_sample.rgb, vec3(0.0)));
        hist = clip_aabb(lo, hi, hist);

        float rel = abs(curr_depth - history_sample.a) / max(curr_depth, 1.0);
        float trust = 1.0 - smoothstep(DEPTH_TRUST_MIN, DEPTH_TRUST_MAX, rel);
        float w = resolve.weight * trust;
        resolved = mix(current.rgb, ycocg_to_rgb(hist), w);
    }

    out_color = vec4(apply_gamma(resolved, resolve.gamma), 1.0);
    out_history = vec4(resolved, curr_depth);
}
