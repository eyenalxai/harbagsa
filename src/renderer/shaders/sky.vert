#version 460

layout(location = 0) out vec2 v_ndc;

#include "camera.glsl"

// A fullscreen triangle at the far plane. The depth prepass leaves 1.0 where no
// geometry covers the pixel, so the sky pass with depth EQUAL shades only the
// background. The triangle does not move: the jitter goes into the sampled
// direction, so TAA rotates the sky under the same phase as the boxes while the
// velocity stays unjittered.
void main() {
    vec2 uv = vec2(float((gl_VertexIndex << 1) & 2), float(gl_VertexIndex & 2));
    vec2 ndc = uv * 2.0 - 1.0;
    v_ndc = ndc + camera.jitter.xy;
    gl_Position = vec4(ndc, 1.0, 1.0);
}
