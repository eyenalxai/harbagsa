#ifndef TERMS_GLSL
#define TERMS_GLSL

// The one place the lit terms are evaluated. The lit fragment shader composes
// the beauty pixel from these terms, and a future pick shader reads the same
// functions, so a pick names the value the lit pass wrote.
//
// This header is fragment-only: bindings 2 through 11 are declared for the
// fragment stage only.

#include "scene.glsl"

// The Odin mirror is Capture_View in src/renderer/capture_view.odin. The order
// is the push constant value the lit pass receives.
const uint VIEW_BEAUTY = 0u;
const uint VIEW_DIRECT = 1u;
const uint VIEW_LIGHTMAP = 2u;
const uint VIEW_PROBE = 3u;
const uint VIEW_EMISSIVE = 4u;
const uint VIEW_SHADOW = 5u;
const uint VIEW_LIGHTMAP_GRID = 6u;
const uint VIEW_PROBE_CELL = 7u;

// src/bake/bake.odin ATLAS_SIZE.
const float LIGHTMAP_ATLAS_SIZE = 1024.0;
// A chart edge covers this fraction of a face at either end of its st range.
const float CHART_EDGE_FRACTION = 0.015;

// FACE_BASES in src/bake/geometry.odin: the face order is +X, -X, +Y, -Y, +Z,
// -Z and s = dot(local, u) + 0.5, t = dot(local, v) + 0.5.
const vec3 FACE_U[6] = vec3[6](
    vec3( 0.0,  0.0,  1.0),
    vec3( 0.0,  0.0, -1.0),
    vec3( 1.0,  0.0,  0.0),
    vec3( 1.0,  0.0,  0.0),
    vec3( 1.0,  0.0,  0.0),
    vec3(-1.0,  0.0,  0.0)
);
const vec3 FACE_V[6] = vec3[6](
    vec3( 0.0, -1.0,  0.0),
    vec3( 0.0, -1.0,  0.0),
    vec3( 0.0,  0.0, -1.0),
    vec3( 0.0,  0.0,  1.0),
    vec3( 0.0,  1.0,  0.0),
    vec3( 0.0,  1.0,  0.0)
);

int face_index(vec3 local_normal) {
    vec3 axis = abs(local_normal);
    if (axis.x >= axis.y && axis.x >= axis.z) {
        return local_normal.x > 0.0 ? 0 : 1;
    }
    if (axis.y >= axis.z) {
        return local_normal.y > 0.0 ? 2 : 3;
    }
    return local_normal.z > 0.0 ? 4 : 5;
}

const uint POINT_RAY_MASK = 0x02u;
// A lamp that sits on a wall ends its shadow ray on that wall. Stop short of
// the light so the surface cannot paint a fan of false shadows.
const float POINT_SHADOW_END_BIAS = 0.001;

bool occluded(vec3 origin, vec3 direction, uint mask, float max_distance) {
    rayQueryEXT query;
    rayQueryInitializeEXT(
        query,
        scene_tlas,
        gl_RayFlagsTerminateOnFirstHitEXT | gl_RayFlagsOpaqueEXT,
        mask,
        origin,
        0.001,
        direction,
        max_distance
    );
    while (rayQueryProceedEXT(query)) {}
    return rayQueryGetIntersectionTypeEXT(query, true) !=
           gl_RayQueryCommittedIntersectionNoneEXT;
}

// The direct term. The shadow view walks the same clusters with `trace_shadows`
// false; the beauty call passes true, so the expression stays the original one.
vec3 point_light_radiance(vec3 world_position, vec3 normal, bool trace_shadows) {
    float view_z = -(camera.view * vec4(world_position, 1.0)).z;
    int cluster_x = clamp(
        int(gl_FragCoord.x / camera.screen.y * float(CLUSTER_X)),
        0,
        CLUSTER_X - 1
    );
    int cluster_y = clamp(
        int(gl_FragCoord.y / camera.screen.z * float(CLUSTER_Y)),
        0,
        CLUSTER_Y - 1
    );
    float slice = log2(max(view_z, CLUSTER_NEAR) / CLUSTER_NEAR) /
                  log2(CLUSTER_FAR / CLUSTER_NEAR);
    int cluster_z = clamp(int(slice * float(CLUSTER_Z)), 0, CLUSTER_Z - 1);
    uint cluster = uint(cluster_x + CLUSTER_X * (cluster_y + CLUSTER_Y * cluster_z));

    uint count = cluster_counts.counts[cluster];
    vec3 sum = vec3(0.0);
    for (uint index = 0; index < count; ++index) {
        uint light_index = cluster_indices.indices[cluster * uint(CLUSTER_LIGHT_STRIDE) + index];
        Light light = light_set.lights[light_index];
        vec3 offset = light.position.xyz - world_position;
        float distance = length(offset);
        if (distance <= 0.0 || distance >= light.color.w) {
            continue;
        }
        vec3 direction = offset / distance;
        float diffuse = max(dot(normal, direction), 0.0);
        float reach = distance / light.color.w;
        float falloff = 1.0 - reach * reach;
        falloff *= falloff;
        float visibility = 1.0;
        if (trace_shadows && camera.lights.y > 0.5) {
            float shadow_distance = max(distance - POINT_SHADOW_END_BIAS, 0.0);
            if (occluded(
                world_position + normal * 0.002,
                direction,
                POINT_RAY_MASK,
                shadow_distance
            )) {
                visibility = 0.0;
            }
        }
        sum += light.color.rgb * (light.position.w * diffuse * falloff * visibility);
    }
    return sum;
}

// Shadowed direct over unshadowed direct as one grey value. A surface no light
// reaches cannot be shadowed, so it reports full visibility.
vec3 shadow_ratio(vec3 world_position, vec3 normal) {
    vec3 shadowed = point_light_radiance(world_position, normal, true);
    vec3 open = point_light_radiance(world_position, normal, false);
    const vec3 LUMA = vec3(0.2126, 0.7152, 0.0722);
    float total = dot(open, LUMA);
    if (total <= 0.0) {
        return vec3(1.0);
    }
    return vec3(clamp(dot(shadowed, LUMA) / total, 0.0, 1.0));
}

struct Lightmap_Sample {
    vec2 uv;
    vec2 st;
};

// The rect is center-to-center, so the clamp lands on the first and last texel
// centers instead of the geometric edge.
Lightmap_Sample lightmap_sample(
    ObjectData object,
    vec3 local_normal,
    vec3 local_position
) {
    int face = face_index(local_normal);
    vec4 rect = lightmap.faces[object.lightmap_slot * 6u + uint(face)].uv_rect;
    vec2 st = vec2(
        dot(local_position, FACE_U[face]),
        dot(local_position, FACE_V[face])
    ) + 0.5;
    vec2 clamped = clamp(st, 0.0, 1.0);
    return Lightmap_Sample(mix(rect.xy, rect.zw, clamped), st);
}

vec3 lightmap_indirect(ObjectData object, vec3 local_normal, vec3 local_position) {
    Lightmap_Sample tap = lightmap_sample(object, local_normal, local_position);
    return textureLod(lightmap_atlas, tap.uv, 0.0).rgb;
}

// The four probes of the containing tetrahedral cell, with the same bias and
// clamp probe_indirect uses, so a cell view names the cell the indirect read.
struct Probe_Cell {
    ivec3 base;
    uint invalid;
    bool inside;
};

Probe_Cell probe_cell(vec3 world_position, vec3 normal) {
    Probe_Cell cell;
    cell.base = ivec3(0);
    cell.invalid = 0u;
    cell.inside = false;
    if (volume.probe_count == 0u) {
        return cell;
    }
    ivec3 counts = ivec3(volume.counts);
    if (counts.x < 1 || counts.y < 1 || counts.z < 1) {
        return cell;
    }
    vec3 sample_position = world_position + normal * (volume.spacing * 0.1);
    vec3 high = volume.origin + vec3(volume.counts) * volume.spacing;
    if (any(lessThan(sample_position, volume.origin)) ||
        any(greaterThan(sample_position, high))) {
        return cell;
    }
    cell.inside = true;
    vec3 local = (sample_position - volume.origin) / volume.spacing - 0.5;
    cell.base = clamp(ivec3(floor(local)), ivec3(0), max(counts - ivec3(2), ivec3(0)));
    for (int z = 0; z < 2; ++z) {
        for (int y = 0; y < 2; ++y) {
            for (int x = 0; x < 2; ++x) {
                ivec3 corner = cell.base + ivec3(x, y, z);
                if (any(lessThan(corner, ivec3(0))) ||
                    any(greaterThanEqual(corner, counts))) {
                    continue;
                }
                uint probe_index = uint(
                    (corner.z * counts.y + corner.y) * counts.x + corner.x
                );
                if (!probe_valid(probe_states.states[probe_index])) {
                    cell.invalid += 1u;
                }
            }
        }
    }
    return cell;
}

vec3 hue_to_rgb(float hue) {
    vec3 offsets = vec3(0.0, 2.0 / 3.0, 1.0 / 3.0);
    vec3 k = mod(hue + offsets, vec3(1.0));
    return clamp(abs(k * 6.0 - 3.0) - 1.0, 0.0, 1.0);
}

// Hashed cell-id colour: the hue is the cell identity and the value stays high
// so neighbouring cells never collapse into the same grey.
vec3 probe_cell_color(Probe_Cell cell) {
    if (!cell.inside) {
        return vec3(1.0, 0.0, 1.0);
    }
    if (cell.invalid > 0u) {
        return vec3(1.0, 0.0, 0.0);
    }
    uint hash = uint(cell.base.x) * 73856093u ^
                uint(cell.base.y) * 19349663u ^
                uint(cell.base.z) * 83492791u;
    hash ^= hash >> 13u;
    hash *= 1274126177u;
    hash ^= hash >> 16u;
    float hue = float(hash & 0xFFFFu) / 65535.0;
    return mix(vec3(0.35), vec3(1.0), hue_to_rgb(hue));
}

// A checker from atlas texel coordinates plus one line at each chart edge. A
// box with no lightmap tile is magenta; the term does not exist for it.
vec3 lightmap_grid(ObjectData object, vec3 local_normal, vec3 local_position) {
    if (object.lightmap_weight <= 0.0) {
        return vec3(1.0, 0.0, 1.0);
    }
    Lightmap_Sample tap = lightmap_sample(object, local_normal, local_position);
    vec2 texel = floor(tap.uv * LIGHTMAP_ATLAS_SIZE);
    float checker = mod(texel.x + texel.y, 2.0);
    vec3 color = mix(vec3(0.18), vec3(0.82), checker);
    float edge = min(
        min(tap.st.x, 1.0 - tap.st.x),
        min(tap.st.y, 1.0 - tap.st.y)
    );
    float line = step(edge, CHART_EDGE_FRACTION);
    return mix(color, vec3(1.0, 0.15, 0.1), line);
}

// The colour one term view writes. Beauty never reaches this function: the lit
// pass composes it, and the call site keeps the composed expression.
vec3 view_term(
    ObjectData object,
    vec3 albedo,
    vec3 world_position,
    vec3 normal,
    vec3 local_normal,
    vec3 local_position,
    uint view
) {
    if (view == VIEW_LIGHTMAP_GRID) {
        return lightmap_grid(object, local_normal, local_position);
    }
    if (view == VIEW_PROBE_CELL) {
        return probe_cell_color(probe_cell(world_position, normal));
    }
    if (view == VIEW_SHADOW) {
        return shadow_ratio(world_position, normal);
    }
    if (view == VIEW_DIRECT) {
        return albedo * point_light_radiance(world_position, normal, true);
    }
    if (view == VIEW_LIGHTMAP) {
        return albedo * lightmap_indirect(object, local_normal, local_position) *
               object.lightmap_weight;
    }
    if (view == VIEW_PROBE) {
        return albedo * probe_indirect(world_position, normal) * object.probe_weight;
    }
    if (view == VIEW_EMISSIVE) {
        return albedo * object.color.a;
    }
    return vec3(0.0);
}

#endif
