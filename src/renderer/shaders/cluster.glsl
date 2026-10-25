#ifndef CLUSTER_GLSL
#define CLUSTER_GLSL

// The Odin mirror is in src/renderer/uniforms.odin. Change both together.
#define CLUSTER_X 16
#define CLUSTER_Y 9
#define CLUSTER_Z 24
#define CLUSTER_COUNT (CLUSTER_X * CLUSTER_Y * CLUSTER_Z)
#define CLUSTER_NEAR 0.05
#define CLUSTER_FAR 200.0
#define CLUSTER_LIGHT_STRIDE 256

#endif
