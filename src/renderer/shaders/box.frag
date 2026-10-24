#version 460
#extension GL_EXT_ray_query : require

layout(early_fragment_tests) in;

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

layout(set = 0, binding = 1) readonly buffer Objects {
    ObjectData objects[];
} scene;

#include "camera.glsl"
#include "sky.glsl"

layout(set = 0, binding = 2) uniform accelerationStructureEXT scene_tlas;

const vec3 SUN_COLOR = vec3(1.0, 0.98, 0.94);
const int SUN_SAMPLES = 16;
const float GOLDEN_ANGLE = 2.39996323;

vec2 vogel_disk(int index, int count, float phase) {
    float radius = sqrt((float(index) + 0.5) / float(count));
    float angle = float(index) * GOLDEN_ANGLE + phase;
    return radius * vec2(cos(angle), sin(angle));
}

float interleaved_gradient_noise(vec2 pixel) {
    return fract(52.9829189 * fract(dot(pixel, vec2(0.06711056, 0.00583715))));
}

vec3 sun_direction(vec3 to_light, int index, int count, float phase) {
    vec3 up = abs(to_light.y) < 0.99 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
    vec3 tangent = normalize(cross(up, to_light));
    vec3 bitangent = cross(to_light, tangent);
    vec2 disk = vogel_disk(index, count, phase) * camera.sun.x;
    return normalize(to_light + tangent * disk.x + bitangent * disk.y);
}

bool occluded(vec3 origin, vec3 direction, float max_distance) {
    rayQueryEXT query;
    rayQueryInitializeEXT(
        query,
        scene_tlas,
        gl_RayFlagsTerminateOnFirstHitEXT | gl_RayFlagsOpaqueEXT,
        0xFF,
        origin,
        0.001,
        direction,
        max_distance
    );
    while (rayQueryProceedEXT(query)) {}
    return rayQueryGetIntersectionTypeEXT(query, true) != gl_RayQueryCommittedIntersectionNoneEXT;
}

float sun_visibility(vec3 world_position, vec3 normal, vec3 to_light) {
    vec3 origin = world_position + normal * 0.002;
    float phase = fract(
        interleaved_gradient_noise(gl_FragCoord.xy) + camera.screen.w * 0.61803398875
    ) * 6.2831853;

    int visible = 0;
    for (int i = 0; i < SUN_SAMPLES; ++i) {
        vec3 direction = sun_direction(to_light, i, SUN_SAMPLES, phase);
        if (!occluded(origin, direction, 1000.0)) {
            visible += 1;
        }
    }
    return float(visible) / float(SUN_SAMPLES);
}

// The shader constant must match AO_SAMPLES in scene.odin. A cosine-weighted
// hemisphere sample already carries the cosine and the 1/pi of the AO
// integral, so the visible fraction is the AO term.
const int AO_SAMPLES = 8;

float ambient_visibility(vec3 position, vec3 normal, float radius, float phase) {
    vec3 origin = position + normal * 0.01;
    vec3 up = abs(normal.y) < 0.99 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
    vec3 tangent = normalize(cross(up, normal));
    vec3 bitangent = cross(normal, tangent);

    int visible = 0;
    for (int i = 0; i < AO_SAMPLES; ++i) {
        vec2 disk = vogel_disk(i, AO_SAMPLES, phase);
        float height = sqrt(max(0.0, 1.0 - dot(disk, disk)));
        vec3 direction = normalize(tangent * disk.x + bitangent * disk.y + normal * height);
        if (!occluded(origin, direction, radius)) {
            visible += 1;
        }
    }
    return float(visible) / float(AO_SAMPLES);
}

void main() {
    ObjectData object = scene.objects[draw.object_index];

    vec3 normal = normalize(v_normal);
    vec3 to_light = normalize(-camera.light_direction.xyz);
    float diffuse = max(dot(normal, to_light), 0.0);
    float visibility = 0.0;
    if (diffuse > 0.0) {
        visibility = sun_visibility(v_world_position, normal, to_light);
    }
    vec3 ambient = camera.lighting.w > 0.5 ? sky_ambient(normal) : camera.ambient.rgb;
    float ao = 1.0;
    if (camera.lighting.z > 0.5) {
        // A different irrational than the sun phase keeps the two sample sets
        // from sharing a rotation.
        float phase = fract(
            interleaved_gradient_noise(gl_FragCoord.xy) + camera.screen.w * 0.7548776662
        ) * 6.2831853;
        ao = ambient_visibility(v_world_position, normal, camera.lighting.x, phase);
        ao = mix(1.0, ao, camera.lighting.y);
    }
    vec3 color = v_color * (ambient * ao + diffuse * SUN_COLOR * visibility);

    vec4 world_position = vec4(v_world_position, 1.0);
    vec4 previous_world = object.prev_model * vec4(v_local_position, 1.0);
    vec4 previous_clip = camera.prev_view_projection * previous_world;
    vec2 previous_uv = vec2(2.0);
    if (previous_clip.w > 0.0) {
        previous_uv = (previous_clip.xy / previous_clip.w) * 0.5 + 0.5;
    }
    // The vertex shader jitters the clip position. The velocity target needs
    // unjittered screen motion, so project the current world point with the
    // unjittered current view-projection.
    vec2 current_uv = vec2(2.0);
    vec4 current_clip = camera.projection * camera.view * world_position;
    if (current_clip.w > 0.0) {
        current_uv = (current_clip.xy / current_clip.w) * 0.5 + 0.5;
    }
    float view_depth = -(camera.view * world_position).z;

    out_color = vec4(color, 1.0);
    out_velocity = vec4(previous_uv - current_uv, view_depth, 0.0);
}
