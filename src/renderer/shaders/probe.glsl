#ifndef PROBE_GLSL
#define PROBE_GLSL

// The probe atlas is a shelf of 8 x 8 octahedral tiles. The state buffer is the
// packed Probe_State from src/bake/format.odin: valid flags in the low byte of
// word 0, then three f16 offsets.
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
    uint atlas_width;
    uint atlas_height;
} volume;

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
vec2 probe_atlas_uv(uint probe_index, vec3 direction) {
    float texels = float(volume.probe_texels);
    vec2 tile = clamp(
        oct_encode(direction) * texels - 0.5,
        vec2(0.0),
        vec2(texels - 1.0)
    );
    uint column = probe_index % volume.atlas_columns;
    uint row = probe_index / volume.atlas_columns;
    vec2 origin = vec2(float(column), float(row)) * texels;
    return (origin + tile + 0.5) / vec2(
        float(volume.atlas_width),
        float(volume.atlas_height)
    );
}

vec3 probe_irradiance(uint probe_index, vec3 direction) {
    return textureLod(
        probe_irradiance_atlas,
        probe_atlas_uv(probe_index, direction),
        0.0
    ).rgb;
}

vec2 probe_moments(uint probe_index, vec3 direction) {
    return textureLod(
        probe_moments_atlas,
        probe_atlas_uv(probe_index, direction),
        0.0
    ).rg;
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
// test. The stored irradiance is (radiance/2)^(1/5): pow(encoded, 2.5) is
// sqrt(radiance/2), so the square and the 2x factor restore the lightmap scale.
// Invalid probes are skipped; outside the volume the term is zero.
vec3 probe_indirect(vec3 world_position, vec3 normal) {
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

        vec3 encoded = probe_irradiance(probe_index, normal);
        sum += pow(encoded, vec3(2.5)) * weight;
        total_weight += weight;
    }
    if (total_weight <= 0.0) {
        return vec3(0.0);
    }
    return pow(sum / total_weight, vec3(2.0)) * 2.0;
}

#endif
