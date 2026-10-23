#version 460

layout(location = 0) in vec2 in_position;
layout(location = 1) in vec4 in_color;

layout(location = 0) out vec4 v_color;

layout(push_constant) uniform PushConstants {
    vec4 viewport;
} hud;

void main() {
    vec2 ndc = vec2(
        in_position.x / hud.viewport.x * 2.0 - 1.0,
        in_position.y / hud.viewport.y * 2.0 - 1.0
    );
    gl_Position = vec4(ndc, 0.0, 1.0);
    v_color = in_color;
}
