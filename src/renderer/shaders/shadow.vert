#version 460

layout(location = 0) in vec3 in_position;

layout(push_constant) uniform PushConstants {
    mat4 model;
} object;

layout(set = 0, binding = 0) uniform Camera {
    mat4 view;
    mat4 projection;
    vec4 light_direction;
    vec4 ambient;
    vec4 gamma;
    mat4 light_view_projection;
} camera;

void main() {
    gl_Position = camera.light_view_projection * object.model * vec4(in_position, 1.0);
}
