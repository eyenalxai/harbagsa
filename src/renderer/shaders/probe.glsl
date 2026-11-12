#ifndef PROBE_GLSL
#define PROBE_GLSL

// The probe atlas is a shelf of octahedral tiles, or a 27 x probe count SH9
// image. The state buffer is the packed Probe_State from src/bake/format.odin:
// valid flags in the low byte of word 0, then three f16 offsets.
layout(set = 0, binding = 8) uniform sampler2D probe_irradiance_atlas;
layout(set = 0, binding = 9) uniform sampler2D probe_moments_atlas;
layout(set = 0, binding = 10) readonly buffer ProbeStates {
    uvec2 states[];
} probe_states;
layout(set = 0, binding = 11) uniform ProbeVolumeBlock {
    vec3 origin;
    float spacing;
    uvec3 counts;
    uint probe_texels;
    uint atlas_columns;
    uint probe_count;
    uint basis;
    uint moment_texels;
} volume;

const uint PROBE_BASIS_OCTA = 0u;
const uint PROBE_BASIS_SH9 = 1u;
const uint PROBE_SH_COEFFS = 9u;

// The octahedral pair in src/bake/shading.odin. The bake decodes texel
// normals with the same mirror.
vec2 oct_wrap(vec2 value) {
    return (1.0 - abs(value.yx)) * vec2(
        value.x >= 0.0 ? 1.0 : -1.0,
        value.y >= 0.0 ? 1.0 : -1.0
    );
}

vec2 oct_encode(vec3 direction) {
    direction /= abs(direction.x) + abs(direction.y) + abs(direction.z);
    if (direction.y < 0.0) {
        direction.xz = oct_wrap(direction.xz);
    }
    return direction.xz * 0.5 + 0.5;
}

bool probe_valid(uvec2 state) {
    return (state.x & 0xFFu) != 0u;
}

vec3 probe_offset(uvec2 state) {
    return vec3(
        unpackHalf2x16(state.x >> 16).x,
        unpackHalf2x16(state.y)
    );
}

// Clamping the tile coordinate to the first and last texel center keeps the
// linear tap inside this probe's tile; a shared sampler never bleeds into a
// neighbouring probe.
vec2 probe_atlas_uv(uint probe_index, vec3 direction, uint grid) {
    float texels = float(grid);
    vec2 tile = clamp(
        oct_encode(direction) * texels - 0.5,
        vec2(0.0),
        vec2(texels - 1.0)
    );
    uint column = probe_index % volume.atlas_columns;
    uint row = probe_index / volume.atlas_columns;
    uint rows = volume.probe_count / volume.atlas_columns;
    vec2 origin = vec2(float(column), float(row)) * texels;
    vec2 extent = vec2(
        float(volume.atlas_columns) * texels,
        float(rows) * texels
    );
    return (origin + tile + 0.5) / extent;
}

vec3 probe_irradiance_octa(uint probe_index, vec3 direction) {
    return textureLod(
        probe_irradiance_atlas,
        probe_atlas_uv(probe_index, direction, volume.probe_texels),
        0.0
    ).rgb;
}

float sh_basis(uint index, vec3 direction) {
    if (index == 0u) {
        return 0.28209479177387814;
    }
    if (index == 1u) {
        return 0.48860251190291992 * direction.y;
    }
    if (index == 2u) {
        return 0.48860251190291992 * direction.z;
    }
    if (index == 3u) {
        return 0.48860251190291992 * direction.x;
    }
    if (index == 4u) {
        return 1.0925484305920792 * direction.x * direction.y;
    }
    if (index == 5u) {
        return 1.0925484305920792 * direction.y * direction.z;
    }
    if (index == 6u) {
        return 0.31539156525252005 *
            (3.0 * direction.z * direction.z - 1.0);
    }
    if (index == 7u) {
        return 1.0925484305920792 * direction.x * direction.z;
    }
    return 0.54627421529603959 *
        (direction.x * direction.x - direction.y * direction.y);
}

vec3 probe_irradiance_sh9(uint probe_index, vec3 direction) {
    vec3 sum = vec3(0.0);
    int row = int(probe_index);
    for (uint index = 0u; index < PROBE_SH_COEFFS; ++index) {
        int base = int(index) * 3;
        vec3 coefficient = vec3(
            texelFetch(probe_irradiance_atlas, ivec2(base + 0, row), 0).r,
            texelFetch(probe_irradiance_atlas, ivec2(base + 1, row), 0).r,
            texelFetch(probe_irradiance_atlas, ivec2(base + 2, row), 0).r
        );
        sum += coefficient * sh_basis(index, direction);
    }
    return sum;
}

vec3 probe_irradiance(uint probe_index, vec3 direction) {
    if (volume.basis == PROBE_BASIS_SH9) {
        return probe_irradiance_sh9(probe_index, direction);
    }
    return probe_irradiance_octa(probe_index, direction);
}

vec2 probe_moments(uint probe_index, vec3 direction) {
    return textureLod(
        probe_moments_atlas,
        probe_atlas_uv(probe_index, direction, volume.moment_texels),
        0.0
    ).rg;
}

// The octa storage is (radiance/2)^(1/5); 2 * pow(encoded, 5) restores the
// lightmap-scale value. The default path leaves the square root in place and
// squares after the weights; this path decodes every tap first.
vec3 decode_octa_linear(vec3 encoded) {
    return 2.0 * pow(max(encoded, vec3(0.0)), vec3(5.0));
}

vec3 probe_irradiance_octa_linear(uint probe_index, vec3 direction) {
    float texels = float(volume.probe_texels);
    vec2 tile = clamp(
        oct_encode(direction) * texels - 0.5,
        vec2(0.0),
        vec2(texels - 1.0)
    );
    vec2 base = floor(tile);
    vec2 fraction = tile - base;
    uint column = probe_index % volume.atlas_columns;
    uint row = probe_index / volume.atlas_columns;
    ivec2 origin = ivec2(int(column), int(row)) * int(texels);
    ivec2 low = ivec2(base);
    ivec2 high = min(low + ivec2(1), ivec2(int(texels) - 1));
    vec3 t00 = decode_octa_linear(texelFetch(probe_irradiance_atlas, origin + low, 0).rgb);
    vec3 t10 = decode_octa_linear(texelFetch(probe_irradiance_atlas, origin + ivec2(high.x, low.y), 0).rgb);
    vec3 t01 = decode_octa_linear(texelFetch(probe_irradiance_atlas, origin + ivec2(low.x, high.y), 0).rgb);
    vec3 t11 = decode_octa_linear(texelFetch(probe_irradiance_atlas, origin + high, 0).rgb);
    return mix(mix(t00, t10, fraction.x), mix(t01, t11, fraction.x), fraction.y);
}

struct ProbeTetrahedron {
    ivec3 corner[4];
    vec4 weight;
};

// Split the unit cell into the six tetrahedra around the 000-111 diagonal.
ProbeTetrahedron probe_tetrahedron(vec3 fraction) {
    ProbeTetrahedron tetra;
    if (fraction.x > fraction.y) {
        if (fraction.y > fraction.z) {
            tetra.corner[0] = ivec3(0, 0, 0);
            tetra.corner[1] = ivec3(1, 0, 0);
            tetra.corner[2] = ivec3(1, 1, 0);
            tetra.corner[3] = ivec3(1, 1, 1);
            tetra.weight = vec4(
                1.0 - fraction.x,
                fraction.x - fraction.y,
                fraction.y - fraction.z,
                fraction.z
            );
        } else if (fraction.x > fraction.z) {
            tetra.corner[0] = ivec3(0, 0, 0);
            tetra.corner[1] = ivec3(1, 0, 0);
            tetra.corner[2] = ivec3(1, 0, 1);
            tetra.corner[3] = ivec3(1, 1, 1);
            tetra.weight = vec4(
                1.0 - fraction.x,
                fraction.x - fraction.z,
                fraction.z - fraction.y,
                fraction.y
            );
        } else {
            tetra.corner[0] = ivec3(0, 0, 0);
            tetra.corner[1] = ivec3(0, 0, 1);
            tetra.corner[2] = ivec3(1, 0, 1);
            tetra.corner[3] = ivec3(1, 1, 1);
            tetra.weight = vec4(
                1.0 - fraction.z,
                fraction.z - fraction.x,
                fraction.x - fraction.y,
                fraction.y
            );
        }
    } else {
        if (fraction.z > fraction.y) {
            tetra.corner[0] = ivec3(0, 0, 0);
            tetra.corner[1] = ivec3(0, 0, 1);
            tetra.corner[2] = ivec3(0, 1, 1);
            tetra.corner[3] = ivec3(1, 1, 1);
            tetra.weight = vec4(
                1.0 - fraction.z,
                fraction.z - fraction.y,
                fraction.y - fraction.x,
                fraction.x
            );
        } else if (fraction.z > fraction.x) {
            tetra.corner[0] = ivec3(0, 0, 0);
            tetra.corner[1] = ivec3(0, 1, 0);
            tetra.corner[2] = ivec3(0, 1, 1);
            tetra.corner[3] = ivec3(1, 1, 1);
            tetra.weight = vec4(
                1.0 - fraction.y,
                fraction.y - fraction.z,
                fraction.z - fraction.x,
                fraction.x
            );
        } else {
            tetra.corner[0] = ivec3(0, 0, 0);
            tetra.corner[1] = ivec3(0, 1, 0);
            tetra.corner[2] = ivec3(1, 1, 0);
            tetra.corner[3] = ivec3(1, 1, 1);
            tetra.weight = vec4(
                1.0 - fraction.y,
                fraction.y - fraction.x,
                fraction.x - fraction.z,
                fraction.z
            );
        }
    }
    return tetra;
}

// Four probes with normal bias, facing weight, and the baked depth-moment
// test. The default octa path averages in the gamma-2 curve the storage
// implies; the linear variant decodes every tap first. SH9 reconstructs the
// linear coefficients directly. Invalid probes are skipped; outside the volume
// the term is zero.
vec3 probe_indirect_mode(vec3 world_position, vec3 normal, bool linear) {
    if (volume.probe_count == 0u) {
        return vec3(0.0);
    }
    vec3 sample_position = world_position + normal * (volume.spacing * 0.1);
    vec3 high = volume.origin + vec3(volume.counts) * volume.spacing;
    if (any(lessThan(sample_position, volume.origin)) ||
        any(greaterThan(sample_position, high))) {
        return vec3(0.0);
    }

    ivec3 counts = ivec3(volume.counts);
    vec3 local = (sample_position - volume.origin) / volume.spacing - 0.5;
    ivec3 base = clamp(
        ivec3(floor(local)),
        ivec3(0),
        max(counts - ivec3(2), ivec3(0))
    );
    vec3 fraction = clamp(local - vec3(base), vec3(0.0), vec3(1.0));
    ProbeTetrahedron tetra = probe_tetrahedron(fraction);
    float bias = max(0.05, volume.spacing * 0.05);
    bool sh9 = volume.basis == PROBE_BASIS_SH9;
    bool decode = sh9 || linear;

    vec3 sum = vec3(0.0);
    float total_weight = 0.0;
    for (int corner = 0; corner < 4; ++corner) {
        ivec3 cell = base + tetra.corner[corner];
        if (any(lessThan(cell, ivec3(0))) || any(greaterThanEqual(cell, counts))) {
            continue;
        }
        uint probe_index = uint(
            (cell.z * counts.y + cell.y) * counts.x + cell.x
        );
        uvec2 state = probe_states.states[probe_index];
        if (!probe_valid(state)) {
            continue;
        }
        vec3 probe_position = volume.origin +
            (vec3(cell) + 0.5) * volume.spacing +
            probe_offset(state);
        vec3 to_surface = sample_position - probe_position;
        float distance = length(to_surface);
        if (distance < 1e-5) {
            continue;
        }
        vec3 direction = to_surface / distance;
        // A probe behind the surface samples the far side of the wall.
        float facing = max(dot(-direction, normal), 0.0);
        float weight = tetra.weight[corner] * facing * facing;
        if (weight <= 0.0) {
            continue;
        }

        vec2 moments = 2.0 * probe_moments(probe_index, direction);
        if (moments.x <= 0.0) {
            continue;
        }
        float mean = moments.x;
        float variance = abs(mean * mean - moments.y);
        float chebyshev = 1.0;
        if (distance > mean + bias) {
            float difference = distance - mean - bias;
            chebyshev = variance / (variance + difference * difference);
            chebyshev = max(chebyshev * chebyshev * chebyshev, 0.0);
        }
        weight *= max(0.05, chebyshev);
        if (weight <= 0.0) {
            continue;
        }

        if (decode) {
            vec3 value = sh9
                ? probe_irradiance_sh9(probe_index, normal)
                : probe_irradiance_octa_linear(probe_index, normal);
            sum += value * weight;
        } else {
            vec3 encoded = probe_irradiance_octa(probe_index, normal);
            sum += pow(encoded, vec3(2.5)) * weight;
        }
        total_weight += weight;
    }
    if (total_weight <= 0.0) {
        return vec3(0.0);
    }
    if (decode) {
        return sum / total_weight;
    }
    return pow(sum / total_weight, vec3(2.0)) * 2.0;
}

vec3 probe_indirect(vec3 world_position, vec3 normal) {
    return probe_indirect_mode(world_position, normal, false);
}

vec3 probe_indirect_linear(vec3 world_position, vec3 normal) {
    return probe_indirect_mode(world_position, normal, true);
}

#endif
