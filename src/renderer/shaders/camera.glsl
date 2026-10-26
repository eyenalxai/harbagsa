layout(set = 0, binding = 0) uniform Camera {
    mat4 view;
    mat4 projection;
    mat4 prev_view_projection;
    vec4 screen;
    vec4 lights;
    vec4 jitter;
    vec4 occlusion;
    vec4 probe;
} camera;
