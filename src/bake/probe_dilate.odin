#+vet explicit-allocators
package bake

// A probe that remains invalid after the virtual-offset pass is filled from
// nearby valid probes, so a crate near a wall does not lose a whole
// tetrahedron. The fill runs in index order and may use a probe filled earlier
// in the same pass, which lets a thin band of invalid probes drain to a valid
// neighbour. A probe with no valid source stays invalid and the sampler skips
// it; there is no black fill.
PROBE_DILATE_RADIUS :: 2

PROBE_IRRADIANCE_CHANNELS :: 4
PROBE_MOMENT_CHANNELS :: 2

probe_dilate :: proc(work: ^Probe_Work) -> (dilated: int) {
	counts := work.counts
	for probe in 0 ..< work.count {
		if work.states[probe].valid != 0 {
			continue
		}
		x := probe % counts.x
		y := (probe / counts.x) % counts.y
		z := probe / (counts.x * counts.y)

		irradiance_sum: [PROBE_TEXEL_COUNT][PROBE_IRRADIANCE_CHANNELS]f64
		moment_sum: [PROBE_TEXEL_COUNT][PROBE_MOMENT_CHANNELS]f64
		weight_sum: f64

		for offset_z in -PROBE_DILATE_RADIUS ..= PROBE_DILATE_RADIUS {
			neighbor_z := z + offset_z
			if neighbor_z < 0 || neighbor_z >= counts.z {
				continue
			}
			for offset_y in -PROBE_DILATE_RADIUS ..= PROBE_DILATE_RADIUS {
				neighbor_y := y + offset_y
				if neighbor_y < 0 || neighbor_y >= counts.y {
					continue
				}
				for offset_x in -PROBE_DILATE_RADIUS ..= PROBE_DILATE_RADIUS {
					neighbor_x := x + offset_x
					if neighbor_x < 0 || neighbor_x >= counts.x {
						continue
					}
					neighbor := (neighbor_z * counts.y + neighbor_y) * counts.x + neighbor_x
					if work.states[neighbor].valid == 0 {
						continue
					}
					distance_squared := f64(
						offset_x * offset_x + offset_y * offset_y + offset_z * offset_z,
					)
					weight := 1.0 / (1.0 + distance_squared)
					irradiance_base := neighbor * PROBE_TEXEL_COUNT * PROBE_IRRADIANCE_CHANNELS
					moment_base := neighbor * PROBE_TEXEL_COUNT * PROBE_MOMENT_CHANNELS
					for texel in 0 ..< PROBE_TEXEL_COUNT {
						for channel in 0 ..< PROBE_IRRADIANCE_CHANNELS {
							index := irradiance_base + texel * PROBE_IRRADIANCE_CHANNELS + channel
							irradiance_sum[texel][channel] += f64(work.irradiance[index]) * weight
						}
						for channel in 0 ..< PROBE_MOMENT_CHANNELS {
							index := moment_base + texel * PROBE_MOMENT_CHANNELS + channel
							moment_sum[texel][channel] += f64(work.moments[index]) * weight
						}
					}
					weight_sum += weight
				}
			}
		}
		if weight_sum <= 0 {
			continue
		}

		irradiance_base := probe * PROBE_TEXEL_COUNT * PROBE_IRRADIANCE_CHANNELS
		moment_base := probe * PROBE_TEXEL_COUNT * PROBE_MOMENT_CHANNELS
		scale := 1.0 / weight_sum
		for texel in 0 ..< PROBE_TEXEL_COUNT {
			for channel in 0 ..< PROBE_IRRADIANCE_CHANNELS {
				index := irradiance_base + texel * PROBE_IRRADIANCE_CHANNELS + channel
				work.irradiance[index] = f16(irradiance_sum[texel][channel] * scale)
			}
			for channel in 0 ..< PROBE_MOMENT_CHANNELS {
				index := moment_base + texel * PROBE_MOMENT_CHANNELS + channel
				work.moments[index] = f16(moment_sum[texel][channel] * scale)
			}
		}
		work.states[probe] = {valid = 1}
		dilated += 1
	}
	return
}
