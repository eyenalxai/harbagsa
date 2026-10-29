#version 460
#extension GL_EXT_ray_query : require

// One diagnostic view per draw. The beauty shader stays free of this dispatch:
// a shader that also carries the term code recompiles the composed pixel, and
// the composed pixel has to stay byte-identical.
layout(early_fragment_tests) in;

layout(location = 0) in vec3 v_normal;
layout(location = 1) in vec3 v_color;
layout(location = 2) in vec3 v_world_position;
layout(location = 3) in vec3 v_local_position;
layout(location = 4) flat in vec3 v_local_normal;

layout(location = 0) out vec4 out_color;
layout(location = 1) out vec4 out_velocity;

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

    out_color = vec4(
        view_term(
            object,
            v_color,
            v_world_position,
            normal,
            v_local_normal,
            v_local_position,
            draw.view
        ),
        1.0
    );
    out_velocity = vec4(previous_uv - current_uv, view_depth, 0.0);
}
