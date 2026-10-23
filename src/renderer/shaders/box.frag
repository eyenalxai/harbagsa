#version 460

layout(location = 0) in vec3 v_normal;
layout(location = 1) in vec3 v_color;

layout(location = 0) out vec4 out_color;

layout(set = 0, binding = 0) uniform Camera {
    mat4 view;
    mat4 projection;
    vec4 light_direction;
    vec4 ambient;
} camera;

void main() {
    vec3 normal = normalize(v_normal);
    vec3 to_light = normalize(-camera.light_direction.xyz);
    float diffuse = max(dot(normal, to_light), 0.0);

    vec3 color = v_color * (camera.ambient.rgb + diffuse * vec3(1.0, 0.98, 0.94));

    // sRGB swapchains encode the fragment output in hardware. Other formats
    // need an explicit gamma step so colors match the sRGB path.
    if (camera.ambient.w > 0.5) {
        color = pow(color, vec3(1.0 / 2.2));
    }

    out_color = vec4(color, 1.0);
}
