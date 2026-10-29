#+vet explicit-allocators
package bake

import "core:mem"

// A probe that remains invalid after the virtual-offset pass copies the nearest
// valid probe within the radius. The copy keeps that probe's sample origin in
// the offset, so the stored depth moments stay measured from the point the
// shader tests. A probe with no valid source stays invalid and the sampler
// skips it; there is no black fill.
PROBE_DILATE_RADIUS :: 2

probe_dilate :: proc(work: ^Probe_Work, allocator: mem.Allocator) -> (dilated: int) {
	sources := make([]bool, work.count, allocator)
	defer delete(sources, allocator)
	for probe in 0 ..< work.count {
		sources[probe] = work.states[probe].valid != 0
	}

	irradiance_span := PROBE_TEXEL_COUNT * PROBE_IRRADIANCE_CHANNELS
	moment_span := PROBE_TEXEL_COUNT * PROBE_MOMENT_CHANNELS
	for probe in 0 ..< work.count {
		if sources[probe] {
			continue
		}
		x, y, z := probe_cell(probe, work.counts)
		best_probe := -1
		best_distance := 0
		for offset_z in -PROBE_DILATE_RADIUS ..= PROBE_DILATE_RADIUS {
			neighbor_z := z + offset_z
			if neighbor_z < 0 || neighbor_z >= work.counts.z {
				continue
			}
			for offset_y in -PROBE_DILATE_RADIUS ..= PROBE_DILATE_RADIUS {
				neighbor_y := y + offset_y
				if neighbor_y < 0 || neighbor_y >= work.counts.y {
					continue
				}
				for offset_x in -PROBE_DILATE_RADIUS ..= PROBE_DILATE_RADIUS {
					neighbor_x := x + offset_x
					if neighbor_x < 0 || neighbor_x >= work.counts.x {
						continue
					}
					neighbor := (neighbor_z * work.counts.y + neighbor_y) * work.counts.x + neighbor_x
					if !sources[neighbor] {
						continue
					}
					distance := offset_x * offset_x + offset_y * offset_y + offset_z * offset_z
					if best_probe < 0 || distance < best_distance {
						best_probe = neighbor
						best_distance = distance
					}
				}
			}
		}
		if best_probe < 0 {
			continue
		}

		source_base := best_probe * irradiance_span
		destination_base := probe * irradiance_span
		copy(
			work.irradiance[destination_base:destination_base + irradiance_span],
			work.irradiance[source_base:source_base + irradiance_span],
		)
		source_moment_base := best_probe * moment_span
		destination_moment_base := probe * moment_span
		copy(
			work.moments[destination_moment_base:destination_moment_base + moment_span],
			work.moments[source_moment_base:source_moment_base + moment_span],
		)

		source_x, source_y, source_z := probe_cell(best_probe, work.counts)
		source_center := dv_add(
			work.min,
			dv_mul(
				{f64(source_x) + 0.5, f64(source_y) + 0.5, f64(source_z) + 0.5},
				work.spacing,
			),
		)
		destination_center := dv_add(
			work.min,
			dv_mul({f64(x) + 0.5, f64(y) + 0.5, f64(z) + 0.5}, work.spacing),
		)
		source_offset := work.states[best_probe].offset
		offset := dv_add(
			DVec3{f64(source_offset.x), f64(source_offset.y), f64(source_offset.z)},
			dv_sub(source_center, destination_center),
		)
		work.states[probe] = {
			valid  = 1,
			offset = {f16(offset.x), f16(offset.y), f16(offset.z)},
		}
		dilated += 1
	}
	return
}
