#version 460

layout(location = 0) in vec3 in_position;

layout(push_constant) uniform PushConstants {
    mat4 model;
} object;

#include "camera.glsl"

void main() {
    gl_Position = camera.light_view_projection * object.model * vec4(in_position, 1.0);
}
