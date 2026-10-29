#version 460

layout(location = 0) in vec3 in_position;
layout(location = 1) in vec3 in_normal;

layout(location = 0) out vec3 v_normal;
layout(location = 1) out vec3 v_color;
layout(location = 2) out vec3 v_world_position;
layout(location = 3) out vec3 v_local_position;
layout(location = 4) out vec3 v_local_normal;

struct ObjectData {
    mat4 model;
    mat4 prev_model;
    vec4 color;
    uvec4 indirect;
};

layout(push_constant) uniform PushConstants {
    uint object_index;
} draw;

layout(set = 0, binding = 1) readonly buffer Objects {
    ObjectData objects[];
} scene;

#include "camera.glsl"

void main() {
    ObjectData object = scene.objects[draw.object_index];
    vec4 world_position = object.model * vec4(in_position, 1.0);
    vec4 clip_position = camera.projection * camera.view * world_position;
    clip_position.xy += camera.jitter.xy * clip_position.w;
    gl_Position = clip_position;
    v_normal = mat3(object.model) * in_normal;
    v_color = object.color.rgb;
    v_world_position = world_position.xyz;
    v_local_position = in_position;
    v_local_normal = in_normal;
}
