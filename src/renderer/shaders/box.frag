#version 460

layout(location = 0) in vec3 v_normal;
layout(location = 1) in vec3 v_color;
layout(location = 2) in vec3 v_world_position;
layout(location = 3) in vec3 v_local_position;

layout(location = 0) out vec4 out_color;
layout(location = 1) out vec4 out_velocity;

struct ObjectData {
    mat4 model;
    mat4 prev_model;
    vec4 color;
};

layout(push_constant) uniform PushConstants {
    uint object_index;
} draw;

layout(set = 0, binding = 2) readonly buffer Objects {
    ObjectData objects[];
} scene;

#include "camera.glsl"

layout(set = 0, binding = 1) uniform sampler2DShadow shadow_map;
layout(set = 0, binding = 3) uniform sampler2D shadow_depth;

const vec3 SUN_COLOR = vec3(1.0, 0.98, 0.94);
const float SHADOW_NORMAL_OFFSET = 0.02;
const float SHADOW_DEPTH_BIAS = 0.0003;
const float SHADOW_SLOPE_BIAS = 0.0015;
const int BLOCKER_SAMPLES = 24;
const int PCF_SAMPLES = 32;
const float BLOCKER_SEARCH_TEXELS = 16.0;
const float MIN_PENUMBRA_TEXELS = 0.75;
const float MAX_PENUMBRA_TEXELS = 16.0;
const float GOLDEN_ANGLE = 2.39996323;

vec2 vogel_disk(int index, int count, float phase) {
    float radius = sqrt((float(index) + 0.5) / float(count));
    float angle = float(index) * GOLDEN_ANGLE + phase;
    return radius * vec2(cos(angle), sin(angle));
}

float interleaved_gradient_noise(vec2 pixel) {
    return fract(52.9829189 * fract(dot(pixel, vec2(0.06711056, 0.00583715))));
}

float sun_visibility(vec3 world_position, vec3 normal, vec3 to_light) {
    vec4 light_position = camera.light_view_projection *
        vec4(world_position + normal * SHADOW_NORMAL_OFFSET, 1.0);
    vec3 projected = light_position.xyz / light_position.w;
    vec2 uv = projected.xy * 0.5 + 0.5;
    if (any(lessThan(uv, vec2(0.0))) || any(greaterThan(uv, vec2(1.0)))) {
        return 1.0;
    }

    float bias = max(SHADOW_DEPTH_BIAS, SHADOW_SLOPE_BIAS * (1.0 - dot(normal, to_light)));
    float receiver_depth = projected.z - bias;
    vec2 texel = 1.0 / vec2(textureSize(shadow_depth, 0));
    float phase = interleaved_gradient_noise(gl_FragCoord.xy) * 6.2831853;

    float search_radius = BLOCKER_SEARCH_TEXELS * texel.x;
    float blocker_depth = 0.0;
    int blocker_count = 0;
    for (int i = 0; i < BLOCKER_SAMPLES; ++i) {
        vec2 offset = vogel_disk(i, BLOCKER_SAMPLES, phase) * search_radius;
        float depth = texture(shadow_depth, uv + offset).r;
        if (depth < receiver_depth) {
            blocker_depth += depth;
            blocker_count += 1;
        }
    }
    if (blocker_count == 0) {
        return 1.0;
    }
    blocker_depth /= float(blocker_count);

    float penumbra_uv = max(projected.z - blocker_depth, 0.0) * camera.shadow_params.x;
    float penumbra_texels = clamp(
        penumbra_uv * float(textureSize(shadow_depth, 0).x),
        MIN_PENUMBRA_TEXELS,
        MAX_PENUMBRA_TEXELS
    );
    float radius = penumbra_texels * texel.x;

    float visibility = 0.0;
    for (int i = 0; i < PCF_SAMPLES; ++i) {
        vec2 offset = vogel_disk(i, PCF_SAMPLES, phase + 1.7) * radius;
        visibility += texture(shadow_map, vec3(uv + offset, receiver_depth));
    }
    return visibility / float(PCF_SAMPLES);
}

void main() {
    ObjectData object = scene.objects[draw.object_index];

    vec3 normal = normalize(v_normal);
    vec3 to_light = normalize(-camera.light_direction.xyz);
    float diffuse = max(dot(normal, to_light), 0.0);
    float visibility = sun_visibility(v_world_position, normal, to_light);
    vec3 color = v_color * (camera.ambient.rgb + diffuse * SUN_COLOR * visibility);

    vec4 world_position = vec4(v_world_position, 1.0);
    vec4 previous_world = object.prev_model * vec4(v_local_position, 1.0);
    vec4 previous_clip = camera.prev_view_projection * previous_world;
    vec2 previous_uv = vec2(2.0);
    if (previous_clip.w > 0.0) {
        previous_uv = (previous_clip.xy / previous_clip.w) * 0.5 + 0.5;
    }
    vec2 pixel_uv = gl_FragCoord.xy / camera.screen.yz;
    float view_depth = -(camera.view * world_position).z;

    out_color = vec4(color, 1.0);
    out_velocity = vec4(previous_uv - pixel_uv, view_depth, 0.0);
}
