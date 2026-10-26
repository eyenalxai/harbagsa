#ifndef PROBE_GATHER_GLSL
#define PROBE_GATHER_GLSL

vec4 probe_irradiance_texel(uint probe_index, ivec2 texel) {
    texel = clamp(texel, ivec2(0), ivec2(PROBE_GRID_SIZE - 1));
    return probe_irradiance_set.irradiance[
        probe_index * uint(PROBE_TEXELS) + uint(texel.y * PROBE_GRID_SIZE + texel.x)
    ];
}

vec2 probe_depth_texel(uint probe_index, ivec2 texel) {
    texel = clamp(texel, ivec2(0), ivec2(PROBE_GRID_SIZE - 1));
    return probe_depth_set.depth[
        probe_index * uint(PROBE_TEXELS) + uint(texel.y * PROBE_GRID_SIZE + texel.x)
    ];
}

vec3 probe_sample_irradiance(uint probe_index, vec3 direction) {
    vec2 uv = oct_encode(direction) * float(PROBE_GRID_SIZE) - 0.5;
    ivec2 base = ivec2(floor(uv));
    vec2 fraction = uv - vec2(base);
    vec4 bottom = mix(
        probe_irradiance_texel(probe_index, base),
        probe_irradiance_texel(probe_index, base + ivec2(1, 0)),
        fraction.x
    );
    vec4 top = mix(
        probe_irradiance_texel(probe_index, base + ivec2(0, 1)),
        probe_irradiance_texel(probe_index, base + ivec2(1, 1)),
        fraction.x
    );
    return mix(bottom, top, fraction.y).rgb;
}

vec2 probe_sample_depth(uint probe_index, vec3 direction) {
    vec2 uv = oct_encode(direction) * float(PROBE_GRID_SIZE) - 0.5;
    ivec2 base = ivec2(floor(uv));
    vec2 fraction = uv - vec2(base);
    vec2 bottom = mix(
        probe_depth_texel(probe_index, base),
        probe_depth_texel(probe_index, base + ivec2(1, 0)),
        fraction.x
    );
    vec2 top = mix(
        probe_depth_texel(probe_index, base + ivec2(0, 1)),
        probe_depth_texel(probe_index, base + ivec2(1, 1)),
        fraction.x
    );
    return mix(bottom, top, fraction.y);
}

vec3 probe_indirect(vec3 world_position, vec3 normal) {
    int volume_count = int(camera.probe.x);
    if (camera.probe.z < 0.5 || volume_count <= 0 || camera.probe.y <= 0.0) {
        return vec3(0.0);
    }

    int volume_index = -1;
    for (int index = 0; index < volume_count; ++index) {
        ProbeVolume volume = probe_volumes.volumes[index];
        vec3 high = volume.min_spacing.xyz +
                    vec3(volume.counts_offset.xyz) * volume.min_spacing.w +
                    vec3(1e-3);
        if (all(greaterThanEqual(world_position, volume.min_spacing.xyz - vec3(1e-3))) &&
            all(lessThanEqual(world_position, high))) {
            volume_index = index;
            break;
        }
    }
    if (volume_index < 0) {
        return vec3(0.0);
    }

    ProbeVolume volume = probe_volumes.volumes[volume_index];
    uvec3 counts = volume.counts_offset.xyz;
    vec3 local = (world_position - volume.min_spacing.xyz) / volume.min_spacing.w - 0.5;
    vec3 base = floor(local);
    vec3 fraction = local - base;
    float bias = max(PROBE_VISIBILITY_MIN_BIAS, volume.min_spacing.w * PROBE_VISIBILITY_BIAS);

    vec3 sum = vec3(0.0);
    float total_weight = 0.0;
    for (int z = 0; z < 2; ++z) {
        for (int y = 0; y < 2; ++y) {
            for (int x = 0; x < 2; ++x) {
                ivec3 cell = clamp(
                    ivec3(base) + ivec3(x, y, z),
                    ivec3(0),
                    ivec3(counts) - 1
                );
                float weight_x = max(0.0, x == 0 ? 1.0 - fraction.x : fraction.x);
                float weight_y = max(0.0, y == 0 ? 1.0 - fraction.y : fraction.y);
                float weight_z = max(0.0, z == 0 ? 1.0 - fraction.z : fraction.z);

                uint probe_index = volume.counts_offset.w + uint(
                    (cell.z * int(counts.y) + cell.y) * int(counts.x) + cell.x
                );
                vec4 probe_data = probe_positions.positions[probe_index];
                if (probe_data.w < 0.5) {
                    continue;
                }
                vec3 probe_position = probe_data.xyz;
                vec3 to_surface = world_position - probe_position;
                float distance2 = dot(to_surface, to_surface);
                if (distance2 < 1e-6) {
                    continue;
                }
                float distance = sqrt(distance2);
                vec3 direction = to_surface / distance;
                vec3 to_probe = -direction;
                float wrap = (dot(to_probe, normal) + 1.0) * 0.5;
                float weight = weight_x * weight_y * weight_z * (wrap * wrap + 0.2);

                vec2 moments = 2.0 * probe_sample_depth(probe_index, direction);
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

                vec3 encoded = probe_sample_irradiance(probe_index, normal);
                vec3 irradiance = pow(
                    encoded,
                    vec3(PROBE_IRRADIANCE_ENCODING_GAMMA * 0.5)
                );
                sum += irradiance * weight;
                total_weight += weight;
            }
        }
    }
    if (total_weight <= 0.0) {
        return vec3(0.0);
    }
    vec3 irradiance = pow(sum / total_weight, vec3(2.0));
    return irradiance * (2.0 * PROBE_PI) * PROBE_INDIRECT_SCALE;
}

#endif
