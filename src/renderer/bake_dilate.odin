#+vet explicit-allocators
package renderer

import "src:bake"

DILATE_RADIUS :: 2

// The bake leaves a probe invalid when its virtual offset cannot leave a static
// box. Borrow the nearest valid probes so a tetrahedron near that box keeps
// four samples; a probe with no valid neighbour stays invalid and is skipped.
// The valid snapshot keeps the fill independent of the loop order.
dilate_probes :: proc(r: ^Renderer, data: ^bake.Data) -> (dilated, skipped: int) {
	count := int(data.header.probe_count)
	counts := data.header.probe_counts
	if count <= 0 || int(counts.x) * int(counts.y) * int(counts.z) != count {
		return 0, 0
	}
	grid := int(data.header.probe_texels)
	columns := int(data.header.probe_atlas_columns)
	if grid <= 0 || columns <= 0 {
		return 0, 0
	}
	invalid := 0
	for state in data.probe_states {
		if state.valid == 0 {
			invalid += 1
		}
	}
	if invalid == 0 {
		return 0, 0
	}

	valid := make([]bool, count, r.allocator)
	defer delete(valid, r.allocator)
	for state, index in data.probe_states {
		valid[index] = state.valid != 0
	}
	irradiance := cast([^]f16)raw_data(data.probe_irradiance)
	moments := cast([^]f16)raw_data(data.probe_moments)
	count_x := int(counts.x)
	count_y := int(counts.y)
	count_z := int(counts.z)
	for z in 0 ..< count_z {
		for y in 0 ..< count_y {
			for x in 0 ..< count_x {
				probe := (z * count_y + y) * count_x + x
				if valid[probe] {
					continue
				}
				irradiance_sum: [4]f64
				moment_sum: [2]f64
				weight_sum: f64
				for dz in -DILATE_RADIUS ..= DILATE_RADIUS {
					nz := z + dz
					if nz < 0 || nz >= count_z {
						continue
					}
					for dy in -DILATE_RADIUS ..= DILATE_RADIUS {
						ny := y + dy
						if ny < 0 || ny >= count_y {
							continue
						}
						for dx in -DILATE_RADIUS ..= DILATE_RADIUS {
							nx := x + dx
							if nx < 0 || nx >= count_x {
								continue
							}
							if dx == 0 && dy == 0 && dz == 0 {
								continue
							}
							neighbour := (nz * count_y + ny) * count_x + nx
							if !valid[neighbour] {
								continue
							}
							weight := 1.0 / f64(1 + dx * dx + dy * dy + dz * dz)
							for texel in 0 ..< grid * grid {
								tx := texel % grid
								ty := texel / grid
								pixel := bake.probe_atlas_pixel(
									neighbour,
									tx,
									ty,
									columns,
									grid,
								)
								for channel in 0 ..< 4 {
									irradiance_sum[channel] +=
										f64(irradiance[pixel * 4 + channel]) * weight
								}
								for channel in 0 ..< 2 {
									moment_sum[channel] +=
										f64(moments[pixel * 2 + channel]) * weight
								}
							}
							weight_sum += weight
						}
					}
				}
				if weight_sum <= 0 {
					skipped += 1
					continue
				}
				for texel in 0 ..< grid * grid {
					tx := texel % grid
					ty := texel / grid
					pixel := bake.probe_atlas_pixel(probe, tx, ty, columns, grid)
					for channel in 0 ..< 4 {
						irradiance[pixel * 4 + channel] =
							f16(irradiance_sum[channel] / weight_sum)
					}
					for channel in 0 ..< 2 {
						moments[pixel * 2 + channel] = f16(moment_sum[channel] / weight_sum)
					}
				}
				data.probe_states[probe] = {valid = 1}
				valid[probe] = true
				dilated += 1
			}
		}
	}
	return
}
