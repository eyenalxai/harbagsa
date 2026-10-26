#version 460

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

const vec3 AMBIENT_FLOOR = vec3(0.055, 0.060, 0.070);

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
        float reach = distance / light.color.w;
        float falloff = 1.0 - reach * reach;
        falloff *= falloff;
        sum += light.color.rgb * (light.position.w * diffuse * falloff);
    }
    return sum;
}

void main() {
    if (v_world_position.y > camera.screen.w) {
        discard;
    }

    ObjectData object = scene.objects[draw.object_index];
    vec3 normal = normalize(v_normal);
    vec3 lit = AMBIENT_FLOOR + point_light_radiance(v_world_position, normal);
    vec3 color = v_color * lit + v_color * object.color.a;

    vec4 world_position = vec4(v_world_position, 1.0);
    vec4 previous_world = object.prev_model * vec4(v_local_position, 1.0);
    vec4 previous_clip = camera.prev_view_projection * previous_world;
    vec2 previous_uv = vec2(2.0);
    if (previous_clip.w > 0.0) {
        previous_uv = (previous_clip.xy / previous_clip.w) * 0.5 + 0.5;
    }
    vec2 current_uv = vec2(2.0);
    vec4 current_clip = camera.projection * camera.view * world_position;
    if (current_clip.w > 0.0) {
        current_uv = (current_clip.xy / current_clip.w) * 0.5 + 0.5;
    }
    float view_depth = -(camera.view * world_position).z;

    out_color = vec4(color, 1.0);
    out_velocity = vec4(previous_uv - current_uv, view_depth, 0.0);
}
