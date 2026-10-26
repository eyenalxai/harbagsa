#version 460

layout(early_fragment_tests) in;

layout(location = 0) in vec2 v_ndc;
layout(location = 0) out vec4 out_color;
layout(location = 1) out vec4 out_velocity;

#include "camera.glsl"
#include "sky.glsl"

vec3 direction_from_ndc(vec2 ndc) {
    vec3 view_direction = vec3(
        ndc.x / camera.projection[0][0],
        ndc.y / camera.projection[1][1],
        -1.0
    );
    return normalize(transpose(mat3(camera.view)) * view_direction);
}

vec2 project_direction(mat4 view_projection, vec3 direction) {
    vec4 clip = view_projection * vec4(direction, 0.0);
    if (clip.w <= 0.0) {
        return vec2(2.0);
    }
    return clip.xy / clip.w * 0.5 + 0.5;
}

void main() {
    vec3 direction = direction_from_ndc(v_ndc);
    vec3 stable = direction_from_ndc(v_ndc - camera.jitter.xy);

    out_color = vec4(sky_gradient(direction), 1.0);

    mat4 current_view_projection = camera.projection * camera.view;
    vec2 previous_uv = project_direction(camera.prev_view_projection, stable);
    vec2 current_uv = project_direction(current_view_projection, stable);
    out_velocity = vec4(previous_uv - current_uv, camera.lights.z, 0.0);
}
