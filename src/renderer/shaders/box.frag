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

// std430: position.xyz is the light position and position.w its intensity;
// color.rgb is the light color and color.w its range.
struct Light {
    vec4 position;
    vec4 color;
};

layout(set = 0, binding = 3) readonly buffer Lights {
    Light lights[];
} light_set;

const vec3 SUN_COLOR = vec3(1.0, 0.98, 0.94);
const int SUN_SAMPLES = 16;
const float GOLDEN_ANGLE = 2.39996323;
const uint SUN_RAY_MASK = 0xFFu;
// A lamp instance carries 0x01. The point shadow ray tests 0x02, so a lamp
// never blocks its own light while the sun ray still sees it.
const uint POINT_RAY_MASK = 0x02u;
// A light on a surface ends its shadow ray on that surface. The ray query
// reports that endpoint as a hit for some pixels and misses it for others, so
// the surface the lamp is mounted on paints a fan of shadows on every surface
// it lights. Stop the ray short of the light instead.
const float POINT_SHADOW_END_BIAS = 0.001;

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

bool occluded(vec3 origin, vec3 direction, uint mask, float max_distance) {
    rayQueryEXT query;
    rayQueryInitializeEXT(
        query,
        scene_tlas,
        gl_RayFlagsTerminateOnFirstHitEXT | gl_RayFlagsOpaqueEXT,
        mask,
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
        if (!occluded(origin, direction, SUN_RAY_MASK, 1000.0)) {
            visible += 1;
        }
    }
    return float(visible) / float(SUN_SAMPLES);
}

vec3 point_light_radiance(vec3 world_position, vec3 normal) {
    int count = int(camera.sun.z);
    bool shadows = camera.sun.w > 0.5;
    vec3 sum = vec3(0.0);
    for (int i = 0; i < count; ++i) {
        Light light = light_set.lights[i];
        vec3 offset = light.position.xyz - world_position;
        float distance = length(offset);
        if (distance <= 0.0 || distance >= light.color.w) {
            continue;
        }
        vec3 direction = offset / distance;
        float diffuse = max(dot(normal, direction), 0.0);
        if (diffuse <= 0.0) {
            continue;
        }
        float reach = distance / light.color.w;
        float falloff = 1.0 - reach * reach;
        falloff *= falloff;
        float visibility = 1.0;
        if (shadows) {
            // Keep the endpoint short of the light. A surface the light sits on
            // would otherwise shadow it for a subset of the pixels, which reads
            // as a fan across every surface the lamp lights.
            float shadow_distance = max(distance - POINT_SHADOW_END_BIAS, 0.0);
            if (occluded(
                world_position + normal * 0.002,
                direction,
                POINT_RAY_MASK,
                shadow_distance
            )) {
                visibility = 0.0;
            }
        }
        sum += light.color.rgb * (light.position.w * diffuse * falloff * visibility);
    }
    return sum;
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
        if (!occluded(origin, direction, 0xFFu, radius)) {
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
    // The sky ambient is a fixed exposure, not the real sky-to-sun ratio, so a
    // full AO band on a sunlit floor reads as dirt. Direct sun buries the sky
    // term in life. Keep the occlusion where the sky is the only light.
    float shade = 1.0 - visibility;
    vec3 lit = ambient * mix(1.0, ao, shade) + diffuse * SUN_COLOR * visibility;
    lit += point_light_radiance(v_world_position, normal);
    vec3 color = v_color * lit + v_color * object.color.a;

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
