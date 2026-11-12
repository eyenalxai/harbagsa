#+vet explicit-allocators
package bake

import "core:math"

// Octa irradiance is stored as (radiance/2)^(1/5) in R11G11B10F. The sampler
// decodes it with pow(encoded, 2.5), so a storage change here must change
// probe.glsl in the same commit. Depth moments are stored halved for the same
// reason: the shader's 2x read restores them.
@(private)
probe_blend :: proc(
	work: ^Probe_Work,
	probe: int,
	directions: []DVec3,
	radiance: []DVec3,
	distances: []f64,
) #no_bounds_check {
	probe_moment_blend(work, probe, directions, distances)
	switch work.basis {
	case .Octa:
		probe_blend_octa(work, probe, directions, radiance, distances)
	case .SH9:
		probe_blend_sh9(work, probe, directions, radiance)
	}
}

@(private)
probe_moment_blend :: proc(
	work: ^Probe_Work,
	probe: int,
	directions: []DVec3,
	distances: []f64,
) #no_bounds_check {
	grid := work.moment_texels
	count := grid * grid
	max_distance := work.spacing * math.sqrt(3.0) * 1.5
	normals: [PROBE_MOMENT_TEXELS_HIGH * PROBE_MOMENT_TEXELS_HIGH]DVec3
	distance_sum, distance2_sum, weight_sum: [PROBE_MOMENT_TEXELS_HIGH * PROBE_MOMENT_TEXELS_HIGH]f64
	for ty in 0 ..< grid {
		for tx in 0 ..< grid {
			normals[ty * grid + tx] = oct_texel_normal(tx, ty, grid)
		}
	}
	for ray_index in 0 ..< work.rays {
		direction := directions[ray_index]
		distance_value := min(math.abs(distances[ray_index]), max_distance)
		for texel in 0 ..< count {
			cosine := dv_dot(normals[texel], direction)
			if cosine <= 0 {
				continue
			}
			weight := pow50(cosine)
			distance_sum[texel] += distance_value * weight
			distance2_sum[texel] += distance_value * distance_value * weight
			weight_sum[texel] += weight
		}
	}
	for ty in 0 ..< grid {
		for tx in 0 ..< grid {
			texel := ty * grid + tx
			denominator := 2.0 * max(weight_sum[texel], 1e-9)
			pixel := probe_atlas_pixel(probe, tx, ty, work.columns, grid)
			base := pixel * PROBE_MOMENT_CHANNELS
			work.moments[base + 0] = f16(distance_sum[texel] / denominator)
			work.moments[base + 1] = f16(distance2_sum[texel] / denominator)
		}
	}
}

@(private)
probe_blend_octa :: proc(
	work: ^Probe_Work,
	probe: int,
	directions: []DVec3,
	radiance: []DVec3,
	distances: []f64,
) #no_bounds_check {
	normals: [PROBE_TEXEL_COUNT]DVec3
	sum_x, sum_y, sum_z: [PROBE_TEXEL_COUNT]f64
	cosine_sum: [PROBE_TEXEL_COUNT]f64
	for ty in 0 ..< PROBE_TEXELS {
		for tx in 0 ..< PROBE_TEXELS {
			normals[ty * PROBE_TEXELS + tx] = oct_texel_normal(tx, ty, PROBE_TEXELS)
		}
	}
	for ray_index in 0 ..< work.rays {
		direction := directions[ray_index]
		value := radiance[ray_index]
		front := distances[ray_index] >= 0
		if !front {
			continue
		}
		for texel in 0 ..< PROBE_TEXEL_COUNT {
			cosine := dv_dot(normals[texel], direction)
			if cosine <= 0 {
				continue
			}
			sum_x[texel] += value.x * cosine
			sum_y[texel] += value.y * cosine
			sum_z[texel] += value.z * cosine
			cosine_sum[texel] += cosine
		}
	}
	for ty in 0 ..< PROBE_TEXELS {
		for tx in 0 ..< PROBE_TEXELS {
			texel := ty * PROBE_TEXELS + tx
			denominator := 2.0 * max(cosine_sum[texel], 1e-9)
			encoded := [3]f64 {
				pow_ratio(sum_x[texel] / denominator, 1.0 / PROBE_IRRADIANCE_GAMMA),
				pow_ratio(sum_y[texel] / denominator, 1.0 / PROBE_IRRADIANCE_GAMMA),
				pow_ratio(sum_z[texel] / denominator, 1.0 / PROBE_IRRADIANCE_GAMMA),
			}
			pixel := probe_atlas_pixel(probe, tx, ty, work.columns, PROBE_TEXELS)
			work.irradiance_u32[pixel] = pack_r11g11b10(encoded)
		}
	}
}
