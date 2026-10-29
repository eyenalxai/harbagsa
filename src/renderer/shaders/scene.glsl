#ifndef SCENE_GLSL
#define SCENE_GLSL

// The fragment interface the scene shaders share: the object buffer, the
// camera, the point lights and their clusters, and the lightmap atlas. The
// term include reads these declarations, and so does a future pick shader.

struct ObjectData {
    mat4 model;
    mat4 prev_model;
    vec4 color;
    uint lightmap_slot;
    float lightmap_weight;
    float probe_weight;
    uint pad0;
};

layout(set = 0, binding = 1) readonly buffer Objects {
    ObjectData objects[];
} scene;

#include "camera.glsl"
#include "cluster.glsl"
#include "probe.glsl"

layout(set = 0, binding = 2) uniform accelerationStructureEXT scene_tlas;

struct Light {
    vec4 position;
    vec4 color;
};

layout(set = 0, binding = 3) readonly buffer Lights {
    Light lights[];
} light_set;

layout(set = 0, binding = 4) readonly buffer ClusterCounts {
    uint counts[];
} cluster_counts;

layout(set = 0, binding = 5) readonly buffer ClusterIndices {
    uint indices[];
} cluster_indices;

// The Odin mirror is in src/bake/format.odin and src/bake/geometry.odin.
struct LightmapFace {
    uvec2 key;
    uvec2 slot_face;
    vec4 uv_rect;
};

layout(set = 0, binding = 6) uniform sampler2D lightmap_atlas;
layout(set = 0, binding = 7) readonly buffer LightmapFaces {
    LightmapFace faces[];
} lightmap;

#endif
