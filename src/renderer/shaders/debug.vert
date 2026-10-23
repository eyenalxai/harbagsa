#version 460

layout(location = 0) in vec3 in_position;
layout(location = 1) in vec4 in_color;

layout(location = 0) out vec4 v_color;

layout(set = 0, binding = 0) uniform Camera {
    mat4 view;
    mat4 projection;
    vec4 light_direction;
    vec4 ambient;
    vec4 gamma;
} camera;

void main() {
    gl_Position = camera.projection * camera.view * vec4(in_position, 1.0);
    v_color = in_color;
}
