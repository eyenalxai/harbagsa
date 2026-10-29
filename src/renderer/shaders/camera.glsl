#ifndef CAMERA_GLSL
#define CAMERA_GLSL

// The Odin mirror is Camera_Uniform in src/renderer/uniforms.odin. screen holds
// gamma, width, height, and plan-view clip height. lights.x holds the
// point-light count. The other lanes are reserved by std140 alignment.
layout(set = 0, binding = 0) uniform Camera {
    mat4 view;
    mat4 projection;
    mat4 prev_view_projection;
    vec4 screen;
    vec4 lights;
    vec4 jitter;
} camera;

#endif
