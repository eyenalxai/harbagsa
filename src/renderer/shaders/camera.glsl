layout(set = 0, binding = 0) uniform Camera {
    mat4 view;
    mat4 projection;
    mat4 prev_view_projection;
    vec4 light_direction;
    vec4 ambient;
    vec4 screen;
    vec4 sun;
    vec4 jitter;
} camera;
