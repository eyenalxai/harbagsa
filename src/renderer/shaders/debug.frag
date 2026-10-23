#version 460

layout(location = 0) in vec4 v_color;

layout(location = 0) out vec4 out_color;

layout(set = 0, binding = 0) uniform Camera {
    mat4 view;
    mat4 projection;
    vec4 light_direction;
    vec4 ambient;
    vec4 gamma;
} camera;

void main() {
    vec3 color = v_color.rgb;

    // sRGB swapchains encode the fragment output in hardware. Other formats
    // need an explicit gamma step so the lines match the scene.
    if (camera.gamma.x > 0.5) {
        color = pow(color, vec3(1.0 / 2.2));
    }

    out_color = vec4(color, v_color.a);
}
