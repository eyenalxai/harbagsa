#ifndef LIGHTMAP_GLSL
#define LIGHTMAP_GLSL

layout(set = 0, binding = 6) uniform sampler2D lightmap_texture;

// The 32-byte stride matches bake.Face. The shader reads only the rect; the
// identity fields keep the layout aligned with the artifact.
struct LightmapFace {
    uvec2 key;
    uint slot;
    uint face;
    vec4 uv_rect;
};

layout(set = 0, binding = 7) readonly buffer LightmapFaces {
    LightmapFace faces[];
} lightmap_faces;

// The Odin mirror is INVALID_LIGHTMAP_SLOT in src/renderer/bake.odin.
const uint INVALID_LIGHTMAP_SLOT = 0xFFFFFFFFu;

// The bake table in src/bake/geometry.odin. The face index, u axis, and v axis
// must stay identical or the chart is sampled mirrored or rotated.
const vec3 FACE_NORMALS[6] = vec3[6](
    vec3(1.0, 0.0, 0.0), vec3(-1.0, 0.0, 0.0),
    vec3(0.0, 1.0, 0.0), vec3(0.0, -1.0, 0.0),
    vec3(0.0, 0.0, 1.0), vec3(0.0, 0.0, -1.0)
);
const vec3 FACE_U[6] = vec3[6](
    vec3(0.0, 0.0, 1.0), vec3(0.0, 0.0, -1.0),
    vec3(1.0, 0.0, 0.0), vec3(1.0, 0.0, 0.0),
    vec3(1.0, 0.0, 0.0), vec3(-1.0, 0.0, 0.0)
);
const vec3 FACE_V[6] = vec3[6](
    vec3(0.0, -1.0, 0.0), vec3(0.0, -1.0, 0.0),
    vec3(0.0, 0.0, -1.0), vec3(0.0, 0.0, 1.0),
    vec3(0.0, 1.0, 0.0), vec3(0.0, 1.0, 0.0)
);

vec3 lightmap_indirect(uint slot, vec3 local_position, vec3 local_normal) {
    int face = -1;
    for (uint index = 0u; index < 6u; ++index) {
        if (dot(local_normal, FACE_NORMALS[index]) > 0.5) {
            face = int(index);
            break;
        }
    }
    if (face < 0) {
        return vec3(0.0);
    }
    vec4 rect = lightmap_faces.faces[slot * 6u + uint(face)].uv_rect;
    float s = clamp(dot(local_position, FACE_U[face]) + 0.5, 0.0, 1.0);
    float t = clamp(dot(local_position, FACE_V[face]) + 0.5, 0.0, 1.0);
    return texture(lightmap_texture, mix(rect.xy, rect.zw, vec2(s, t))).rgb;
}

#endif
