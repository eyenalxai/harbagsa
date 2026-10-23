#version 460

layout(location = 0) in vec3 in_position;
layout(location = 1) in vec3 in_normal;

layout(location = 0) out vec3 v_normal;
layout(location = 1) out vec3 v_color;
layout(location = 2) out vec3 v_world_position;

layout(push_constant) uniform PushConstants {
    mat4 model;
    vec4 color;
} object;

#include "camera.glsl"

void main() {
    vec4 world_position = object.model * vec4(in_position, 1.0);
    gl_Position = camera.projection * camera.view * world_position;
    v_normal = mat3(object.model) * in_normal;
    v_color = object.color.rgb;
    v_world_position = world_position.xyz;
}
