#version 460
#extension GL_EXT_ray_query : require

layout(early_fragment_tests) in;

layout(location = 0) in vec3 v_normal;
layout(location = 1) in vec3 v_color;
layout(location = 2) in vec3 v_world_position;
layout(location = 3) in vec3 v_local_position;
layout(location = 4) flat in vec3 v_local_normal;

layout(location = 0) out vec4 out_color;
layout(location = 1) out vec4 out_velocity;

#include "scene.glsl"

layout(push_constant) uniform PushConstants {
    uint object_index;
    uint view;
} draw;

#include "terms.glsl"

void main() {
    if (v_world_position.y > camera.screen.w) {
        discard;
    }

    ObjectData object = scene.objects[draw.object_index];
    vec3 normal = normalize(v_normal);
    vec3 lit = point_light_radiance(v_world_position, normal, true);
    vec3 indirect = vec3(0.0);
    float indirect_weight = max(object.lightmap_weight, object.probe_weight);
    if (object.lightmap_weight > 0.0) {
        indirect = lightmap_indirect(object, v_local_normal, v_local_position);
    } else if (object.probe_weight > 0.0) {
        indirect = probe_indirect(v_world_position, normal);
    }
    vec3 color = v_color * (lit + indirect * indirect_weight) +
                 v_color * object.color.a;

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
