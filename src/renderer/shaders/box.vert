#version 460

layout(location = 0) in vec3 in_position;
layout(location = 1) in vec3 in_normal;

layout(location = 0) out vec3 v_normal;
layout(location = 1) out vec3 v_color;

layout(push_constant) uniform PushConstants {
    mat4 model;
    vec4 color;
} object;

layout(set = 0, binding = 0) uniform Camera {
    mat4 view;
    mat4 projection;
    vec4 light_direction;
    vec4 ambient;
} camera;

void main() {
    vec4 world_position = object.model * vec4(in_position, 1.0);
    gl_Position = camera.projection * camera.view * world_position;
    v_normal = in_normal;
    v_color = object.color.rgb;
}
