#version 460

layout(location = 0) in vec3 in_position;
layout(location = 1) in vec4 in_color;

layout(location = 0) out vec4 v_color;

#include "camera.glsl"

void main() {
    gl_Position = camera.projection * camera.view * vec4(in_position, 1.0);
    v_color = in_color;
}
