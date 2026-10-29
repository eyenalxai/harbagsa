#ifndef PROBE_GLSL
#define PROBE_GLSL

// The probe shelf atlas stores one 8 x 8 block per probe. This mirrors
// bake.PROBE_TEXELS; the quality block rejects any other size.
#define PROBE_GRID_SIZE 8

layout(set = 0, binding = 8) uniform sampler2D probe_irradiance_texture;
layout(set = 0, binding = 9) uniform sampler2D probe_moments_texture;

layout(set = 0, binding = 10) readonly buffer ProbeStates {
    // Two words per probe: valid and offset.x, then offset.y and offset.z.
    uint words[];
} probe_states;

layout(set = 0, binding = 11) uniform BakeVolume {
    vec4 min_spacing;
    uvec4 counts_texels;
    uvec4 atlas_info;
} bake_volume;

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

ivec2 probe_origin(uint probe) {
    uint columns = bake_volume.atlas_info.x;
    return ivec2(probe % columns, probe / columns) * PROBE_GRID_SIZE;
}

vec4 probe_irradiance_texel(uint probe, ivec2 texel) {
    texel = clamp(texel, ivec2(0), ivec2(PROBE_GRID_SIZE - 1));
    return texelFetch(probe_irradiance_texture, probe_origin(probe) + texel, 0);
}

vec2 probe_moment_texel(uint probe, ivec2 texel) {
    texel = clamp(texel, ivec2(0), ivec2(PROBE_GRID_SIZE - 1));
    return texelFetch(probe_moments_texture, probe_origin(probe) + texel, 0).rg;
}

vec3 probe_sample_irradiance(uint probe, vec3 direction) {
    vec2 uv = oct_encode(direction) * float(PROBE_GRID_SIZE) - 0.5;
    ivec2 base = ivec2(floor(uv));
    vec2 fraction = uv - vec2(base);
    vec4 bottom = mix(
        probe_irradiance_texel(probe, base),
        probe_irradiance_texel(probe, base + ivec2(1, 0)),
        fraction.x
    );
    vec4 top = mix(
        probe_irradiance_texel(probe, base + ivec2(0, 1)),
        probe_irradiance_texel(probe, base + ivec2(1, 1)),
        fraction.x
    );
    return mix(bottom, top, fraction.y).rgb;
}

vec2 probe_sample_moments(uint probe, vec3 direction) {
    vec2 uv = oct_encode(direction) * float(PROBE_GRID_SIZE) - 0.5;
    ivec2 base = ivec2(floor(uv));
    vec2 fraction = uv - vec2(base);
    vec2 bottom = mix(
        probe_moment_texel(probe, base),
        probe_moment_texel(probe, base + ivec2(1, 0)),
        fraction.x
    );
    vec2 top = mix(
        probe_moment_texel(probe, base + ivec2(0, 1)),
        probe_moment_texel(probe, base + ivec2(1, 1)),
        fraction.x
    );
    return mix(bottom, top, fraction.y);
}

// Static probes are baked once, so the fragment only selects a tetrahedron,
// applies the visibility tests, and decodes the stored octahedral radiance.
vec3 probe_indirect(vec3 world_position, vec3 normal) {
    uvec3 counts = bake_volume.counts_texels.xyz;
    if (bake_volume.atlas_info.y == 0u ||
        counts.x == 0u || counts.y == 0u || counts.z == 0u) {
        return vec3(0.0);
    }
    float spacing = bake_volume.min_spacing.w;
    vec3 low = bake_volume.min_spacing.xyz;
    vec3 high = low + vec3(counts) * spacing;
    vec3 sample_position = world_position + normal * spacing * 0.1;
    if (any(lessThan(sample_position, low)) || any(greaterThan(sample_position, high))) {
        return vec3(0.0);
    }

    vec3 local = (sample_position - low) / spacing - 0.5;
    ivec3 base = ivec3(floor(local));
    vec3 fraction = local - vec3(base);
    ivec3 counts_i = ivec3(counts);

    // Split the cell into six tetrahedra by ordering the fractional axes.
    ivec3 edge_1;
    ivec3 edge_2;
    float w0;
    float w1;
    float w2;
    float w3;
    if (fraction.x > fraction.y) {
        if (fraction.y > fraction.z) {
            w0 = 1.0 - fraction.x;
            w1 = fraction.x - fraction.y;
            w2 = fraction.y - fraction.z;
            w3 = fraction.z;
            edge_1 = ivec3(1, 0, 0);
            edge_2 = ivec3(0, 1, 0);
        } else if (fraction.x > fraction.z) {
            w0 = 1.0 - fraction.x;
            w1 = fraction.x - fraction.z;
            w2 = fraction.z - fraction.y;
            w3 = fraction.y;
            edge_1 = ivec3(1, 0, 0);
            edge_2 = ivec3(0, 0, 1);
        } else {
            w0 = 1.0 - fraction.z;
            w1 = fraction.z - fraction.x;
            w2 = fraction.x - fraction.y;
            w3 = fraction.y;
            edge_1 = ivec3(0, 0, 1);
            edge_2 = ivec3(1, 0, 0);
        }
    } else if (fraction.y > fraction.z) {
        if (fraction.x > fraction.z) {
            w0 = 1.0 - fraction.y;
            w1 = fraction.y - fraction.x;
            w2 = fraction.x - fraction.z;
            w3 = fraction.z;
            edge_1 = ivec3(0, 1, 0);
            edge_2 = ivec3(1, 0, 0);
        } else {
            w0 = 1.0 - fraction.y;
            w1 = fraction.y - fraction.z;
            w2 = fraction.z - fraction.x;
            w3 = fraction.x;
            edge_1 = ivec3(0, 1, 0);
            edge_2 = ivec3(0, 0, 1);
        }
    } else {
        w0 = 1.0 - fraction.z;
        w1 = fraction.z - fraction.y;
        w2 = fraction.y - fraction.x;
        w3 = fraction.x;
        edge_1 = ivec3(0, 0, 1);
        edge_2 = ivec3(0, 1, 0);
    }

    ivec3 offsets[4] = ivec3[4](
        ivec3(0),
        edge_1,
        edge_1 + edge_2,
        ivec3(1, 1, 1)
    );
    float weights[4] = float[4](w0, w1, w2, w3);
    float bias = max(0.05, spacing * 0.05);
    vec3 sum = vec3(0.0);
    float total = 0.0;
    for (int corner = 0; corner < 4; ++corner) {
        if (weights[corner] <= 0.0) {
            continue;
        }
        ivec3 cell = clamp(base + offsets[corner], ivec3(0), counts_i - 1);
        uint probe = uint(
            (cell.z * counts_i.y + cell.y) * counts_i.x + cell.x
        );
        uint word = probe_states.words[probe * 2u];
        if ((word & 0xFFu) == 0u) {
            // The bake marks probes inside static geometry invalid. Skip them
            // and renormalize; filling would borrow another probe's moments
            // and leak through the wall.
            continue;
        }
        vec3 offset = vec3(
            unpackHalf2x16(word).y,
            unpackHalf2x16(probe_states.words[probe * 2u + 1u])
        );
        vec3 probe_position = low + (vec3(cell) + 0.5) * spacing + offset;
        vec3 to_surface = sample_position - probe_position;
        float distance = length(to_surface);
        vec3 direction = distance > 1e-4 ? to_surface / distance : normal;
        float facing = max(dot(-direction, normal), 0.0);
        vec2 moments = 2.0 * probe_sample_moments(probe, direction);
        float mean = moments.x;
        float variance = abs(mean * mean - moments.y);
        float chebyshev = 1.0;
        if (distance > mean + bias) {
            float difference = distance - mean;
            chebyshev = variance / (variance + difference * difference);
            chebyshev = max(chebyshev * chebyshev * chebyshev, 0.0);
        }
        float weight = weights[corner] * facing * facing *
            max(0.05, chebyshev);
        vec3 encoded = probe_sample_irradiance(probe, normal);
        sum += pow(encoded, vec3(2.5)) * weight;
        total += weight;
    }
    if (total <= 0.0) {
        return vec3(0.0);
    }
    // The bake stores (radiance / 2)^(1 / 5); the gather restores radiance.
    return pow(sum / total, vec3(2.0)) * 2.0;
}

#endif
