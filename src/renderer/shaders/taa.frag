#version 460

layout(location = 0) out vec4 out_color;
layout(location = 1) out vec4 out_history;
layout(location = 2) out float out_count;

layout(push_constant) uniform PushConstants {
    float gamma;
    float history_valid;
    float max_samples;
} resolve;

layout(set = 0, binding = 0) uniform sampler2D scene_color;
layout(set = 0, binding = 1) uniform sampler2D velocity;
layout(set = 0, binding = 2) uniform sampler2D history;
layout(set = 0, binding = 3) uniform sampler2D sample_count;

#include "gamma.glsl"

const float DEPTH_TOLERANCE = 0.02;
const float CLIP_SIGMA = 2.0;
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
    float resolved_count = 1.0;

    bool in_bounds = all(greaterThanEqual(history_uv, vec2(0.0))) &&
                     all(lessThanEqual(history_uv, vec2(1.0)));
    if (resolve.history_valid > 0.5 && in_bounds) {
        vec3 m1 = vec3(0.0);
        vec3 m2 = vec3(0.0);
        float depth_min = curr_depth;
        float depth_max = curr_depth;
        for (int y = -1; y <= 1; ++y) {
            for (int x = -1; x <= 1; ++x) {
                ivec2 sample_pixel = clamp(pixel + ivec2(x, y), ivec2(0), extent - 1);
                vec3 c = rgb_to_ycocg(max(texelFetch(scene_color, sample_pixel, 0).rgb, vec3(0.0)));
                m1 += c;
                m2 += c * c;
                float sample_depth = texelFetch(velocity, sample_pixel, 0).z;
                depth_min = min(depth_min, sample_depth);
                depth_max = max(depth_max, sample_depth);
            }
        }
        vec3 mu = m1 / 9.0;
        vec3 sigma = sqrt(max(m2 / 9.0 - mu * mu, vec3(0.0)));
        vec3 lo = mu - CLIP_SIGMA * sigma;
        vec3 hi = mu + CLIP_SIGMA * sigma;

        vec2 half_texel = 0.5 / vec2(extent);
        vec2 clamped_uv = clamp(history_uv, half_texel, 1.0 - half_texel);
        vec4 history_sample = textureLod(history, clamped_uv, 0.0);
        vec3 raw_history = rgb_to_ycocg(max(history_sample.rgb, vec3(0.0)));
        vec3 clipped_history = clip_aabb(lo, hi, raw_history);

        // Jitter moves a geometry edge across a pixel, so the history depth and
        // the current depth differ on exactly the pixels that need smoothing.
        // Accept any history depth inside the current 3x3 range; a real
        // disocclusion falls outside the range and still drops the history.
        float depth_tolerance = max(DEPTH_TOLERANCE * curr_depth, 1e-4);
        float depth_lo = depth_min - depth_tolerance;
        float depth_hi = depth_max + depth_tolerance;
        float depth_outside = max(depth_lo - history_sample.a, history_sample.a - depth_hi);
        float trust = 1.0 - smoothstep(0.0, depth_tolerance, depth_outside);

        float samples = textureLod(sample_count, clamped_uv, 0.0).r;
        float count = clamp(samples, 0.0, resolve.max_samples);
        float weight = count / (count + 1.0);

        if (trust < 0.5) {
            resolved = current.rgb;
            resolved_count = 1.0;
        } else {
            resolved = mix(current.rgb, ycocg_to_rgb(clipped_history), weight * trust);
            resolved_count = min(samples + 1.0, resolve.max_samples);
        }
    }

    out_color = vec4(apply_gamma(resolved, resolve.gamma), 1.0);
    out_history = vec4(resolved, curr_depth);
    out_count = resolved_count;
}
