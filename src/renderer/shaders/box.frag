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
#include "cluster.glsl"
#include "probe.glsl"

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

layout(set = 0, binding = 4) readonly buffer ClusterCounts {
    uint counts[];
} cluster_counts;

layout(set = 0, binding = 5) readonly buffer ClusterIndices {
    uint indices[];
} cluster_indices;

struct ProbeVolume {
    vec4 min_spacing;
    uvec4 counts_offset;
};

layout(set = 0, binding = 6) readonly buffer ProbeVolumes {
    ProbeVolume volumes[];
} probe_volumes;

layout(set = 0, binding = 7) readonly buffer ProbeIrradiance {
    vec4 irradiance[];
} probe_irradiance_set;

layout(set = 0, binding = 8) readonly buffer ProbeDepth {
    vec2 depth[];
} probe_depth_set;

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

// A visibility count is a coarse fraction: the sun uses sixteen rays and the
// surface occlusion eight, and either step survives the TAA average as a band.
// Offset the count inside its own step so the resolve sees a continuous value.
// The hash takes the shadow phase, so the offset changes each frame and TAA
// averages it.
float visibility_rounding(uint frame) {
    uint hash = uint(gl_FragCoord.x) * 1973u + uint(gl_FragCoord.y) * 9277u + frame * 26699u;
    hash = (hash ^ 61u) ^ (hash >> 16u);
    hash *= 9u;
    hash ^= hash >> 4u;
    hash *= 0x27d4eb2du;
    hash ^= hash >> 15u;
    return float(hash) / 4294967295.0;
}

// A fully lit or fully occluded pixel is exact. Only the partial counts carry
// the one-step offset, so a surface in full sun does not flicker each frame.
float dithered_visibility(int visible, int count) {
    if (visible <= 0 || visible >= count) {
        return float(visible) / float(count);
    }
    float fraction = float(visible) + visibility_rounding(uint(camera.screen.w)) - 0.5;
    return clamp(fraction / float(count), 0.0, 1.0);
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
    return dithered_visibility(visible, SUN_SAMPLES);
}

vec3 probe_indirect(vec3 world_position, vec3 normal) {
    int volume_count = int(camera.probe.x);
    if (camera.probe.z < 0.5 || volume_count <= 0 || camera.probe.y <= 0.0) {
        return vec3(0.0);
    }

    int volume_index = -1;
    for (int index = 0; index < volume_count; ++index) {
        ProbeVolume volume = probe_volumes.volumes[index];
        vec3 high = volume.min_spacing.xyz +
                    vec3(volume.counts_offset.xyz) * volume.min_spacing.w;
        if (all(greaterThanEqual(world_position, volume.min_spacing.xyz)) &&
            all(lessThanEqual(world_position, high))) {
            volume_index = index;
            break;
        }
    }
    if (volume_index < 0) {
        return vec3(0.0);
    }

    ProbeVolume volume = probe_volumes.volumes[volume_index];
    uvec3 counts = volume.counts_offset.xyz;
    vec3 local = (world_position - volume.min_spacing.xyz) / volume.min_spacing.w - 0.5;
    vec3 base = floor(local);
    vec3 fraction = local - base;

    vec3 sum = vec3(0.0);
    float total_weight = 0.0;
    for (int z = 0; z < 2; ++z) {
        for (int y = 0; y < 2; ++y) {
            for (int x = 0; x < 2; ++x) {
                ivec3 cell = clamp(
                    ivec3(base) + ivec3(x, y, z),
                    ivec3(0),
                    ivec3(counts) - 1
                );
                float weight_x = x == 0 ? 1.0 - fraction.x : fraction.x;
                float weight_y = y == 0 ? 1.0 - fraction.y : fraction.y;
                float weight_z = z == 0 ? 1.0 - fraction.z : fraction.z;

                vec3 probe_position = volume.min_spacing.xyz +
                    (vec3(cell) + 0.5) * volume.min_spacing.w;
                vec3 to_surface = world_position - probe_position;
                float distance2 = dot(to_surface, to_surface);
                if (distance2 < 1e-6) {
                    continue;
                }
                float distance = sqrt(distance2);
                vec3 direction = to_surface / distance;
                float facing = max(dot(normal, -direction), 0.0);
                if (facing <= 0.0) {
                    continue;
                }

                uint probe_index = volume.counts_offset.w + uint(
                    (cell.z * int(counts.y) + cell.y) * int(counts.x) + cell.x
                );
                vec2 oct = oct_encode(direction);
                ivec2 texel = clamp(
                    ivec2(oct * float(PROBE_GRID_SIZE)),
                    ivec2(0),
                    ivec2(PROBE_GRID_SIZE - 1)
                );
                uint sample_index = probe_index * uint(PROBE_TEXELS) +
                    uint(texel.y * PROBE_GRID_SIZE + texel.x);
                vec3 radiance = probe_irradiance_set.irradiance[sample_index].rgb;
                vec2 moments = probe_depth_set.depth[sample_index];
                float mean = moments.x;
                float variance = max(moments.y - mean * mean, 0.0001);
                float chebyshev = 1.0;
                if (distance > mean) {
                    float difference = distance - mean;
                    chebyshev = variance / (variance + difference * difference);
                }

                float weight = weight_x * weight_y * weight_z * facing *
                    chebyshev / (distance2 + 0.05);
                sum += radiance * weight;
                total_weight += weight;
            }
        }
    }
    if (total_weight <= 0.0) {
        return vec3(0.0);
    }
    return sum / total_weight;
}

vec3 point_light_radiance(vec3 world_position, vec3 normal) {
    float view_z = -(camera.view * vec4(world_position, 1.0)).z;
    int cluster_x = clamp(
        int(gl_FragCoord.x / camera.screen.y * float(CLUSTER_X)),
        0,
        CLUSTER_X - 1
    );
    int cluster_y = clamp(
        int(gl_FragCoord.y / camera.screen.z * float(CLUSTER_Y)),
        0,
        CLUSTER_Y - 1
    );
    float slice = log2(max(view_z, CLUSTER_NEAR) / CLUSTER_NEAR) /
                  log2(CLUSTER_FAR / CLUSTER_NEAR);
    int cluster_z = clamp(int(slice * float(CLUSTER_Z)), 0, CLUSTER_Z - 1);
    uint cluster = uint(cluster_x + CLUSTER_X * (cluster_y + CLUSTER_Y * cluster_z));

    uint count = cluster_counts.counts[cluster];
    bool shadows = camera.sun.w > 0.5;
    vec3 sum = vec3(0.0);
    for (uint index = 0; index < count; ++index) {
        uint light_index = cluster_indices.indices[cluster * uint(CLUSTER_LIGHT_STRIDE) + index];
        Light light = light_set.lights[light_index];
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

// The Makefile compiles this with -DAO_SAMPLE_COUNT and passes the same value
// to the Odin build. A cosine-weighted hemisphere sample already carries the
// cosine and the 1/pi of the occlusion integral, so the visible fraction is the
// occlusion term.
#ifndef AO_SAMPLE_COUNT
#define AO_SAMPLE_COUNT 8
#endif
const int AO_SAMPLES = AO_SAMPLE_COUNT;

// The scene has no ambient term, so surface occlusion scales the direct sun and
// point light instead. A corner the light still reaches darkens; a surface no
// light reaches stays black.
float surface_occlusion(vec3 position, vec3 normal, float radius, float phase) {
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
    return dithered_visibility(visible, AO_SAMPLES);
}

void main() {
    // A plan view lowers the clip to drop the roof and the upper walls. The
    // default keeps every fragment, so a normal run pays one compare.
    if (v_world_position.y > camera.occlusion.w) {
        discard;
    }

    ObjectData object = scene.objects[draw.object_index];

    vec3 normal = normalize(v_normal);
    vec3 to_light = normalize(-camera.light_direction.xyz);
    float diffuse = max(dot(normal, to_light), 0.0);
    float visibility = 0.0;
    if (diffuse > 0.0) {
        visibility = sun_visibility(v_world_position, normal, to_light);
    }

    float ao = 1.0;
    if (camera.occlusion.z > 0.5) {
        // A different irrational than the sun phase keeps the two sample sets
        // from sharing a rotation.
        float phase = fract(
            interleaved_gradient_noise(gl_FragCoord.xy) + camera.screen.w * 0.7548776662
        ) * 6.2831853;
        ao = surface_occlusion(v_world_position, normal, camera.occlusion.x, phase);
        ao = mix(1.0, ao, camera.occlusion.y);
    }
    // Direct light only: the sun and the point lights, each with its own shadow
    // ray. The occlusion darkens the light that reaches a corner. There is no
    // ambient term, so a surface that no light reaches is black.
    vec3 lit = (diffuse * SUN_COLOR * visibility + point_light_radiance(v_world_position, normal)) * ao;
    vec3 indirect = probe_indirect(v_world_position, normal);
    vec3 color = v_color * (lit + indirect) + v_color * object.color.a;

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
