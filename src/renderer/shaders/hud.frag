#version 460

layout(location = 0) in vec4 v_color;

layout(location = 0) out vec4 out_color;

layout(push_constant) uniform PushConstants {
    vec4 viewport;
} hud;

void main() {
    vec3 color = v_color.rgb;

    if (hud.viewport.z > 0.5) {
        color = pow(color, vec3(1.0 / 2.2));
    }

    out_color = vec4(color, v_color.a);
}
