#+vet explicit-allocators
package bake

import "core:math"
import "core:mem"

PROBE_KIND :: u64(2)

Probe_Result :: struct {
	irradiance:    []u8,
	moments:       []u8,
	states:        []Probe_State,
	min:           [3]f32,
	spacing:       f32,
	counts:        [3]u32,
	columns:       u32,
	rays:          u64,
	shadow_rays:   u64,
	invalid_probes: int,
	dilated_probes: int,
}

Probe_Work :: struct {
	static:        Static,
	bvh:           ^Bvh,
	irradiance:    []f16,
	moments:       []f16,
	states:        []Probe_State,
	min:           DVec3,
	spacing:       f64,
	counts:        [3]int,
	count:         int,
	columns:       int,
	rays:          int,
	workers:       int,
	directions:    []DVec3,
	radiance:      []DVec3,
	distances:     []f64,
	shadow_counts: []u64,
	invalid_counts: []int,
}

probe_bake :: proc(
	static: Static,
	bvh: ^Bvh,
	quality: Quality,
	threads: int,
	allocator: mem.Allocator,
) -> (
	result: Probe_Result,
	err: Build_Error,
) {
	if quality.probe_texels != PROBE_TEXELS {
		return {}, .Probe_Count
	}
	min, counts := probe_grid(quality.probe_spacing)
	count := int(counts.x) * int(counts.y) * int(counts.z)
	if count <= 0 {
		return {}, .Probe_Count
	}
	columns := probe_columns(count)

	result.min = min
	result.spacing = quality.probe_spacing
	result.counts = counts
	result.columns = u32(columns)
	result.states = make([]Probe_State, count, allocator)
	mem.set(raw_data(result.states), 0, count * size_of(Probe_State))
	irradiance := make([]f16, count * PROBE_TEXEL_COUNT * 4, allocator)
	defer delete(irradiance, allocator)
	moments := make([]f16, count * PROBE_TEXEL_COUNT * 2, allocator)
	defer delete(moments, allocator)
	mem.set(raw_data(irradiance), 0, len(irradiance) * size_of(f16))
	mem.set(raw_data(moments), 0, len(moments) * size_of(f16))

	rays := int(quality.probe_rays)
	directions := make([]DVec3, threads * rays, allocator)
	defer delete(directions, allocator)
	radiance := make([]DVec3, threads * rays, allocator)
	defer delete(radiance, allocator)
	distances := make([]f64, threads * rays, allocator)
	defer delete(distances, allocator)
	shadow_counts := make([]u64, threads, allocator)
	defer delete(shadow_counts, allocator)
	mem.set(raw_data(shadow_counts), 0, len(shadow_counts) * size_of(u64))
	invalid_counts := make([]int, threads, allocator)
	defer delete(invalid_counts, allocator)

	work := Probe_Work {
		static         = static,
		bvh            = bvh,
		irradiance     = irradiance,
		moments        = moments,
		states         = result.states,
		min            = dv(min),
		spacing        = f64(quality.probe_spacing),
		counts         = {int(counts.x), int(counts.y), int(counts.z)},
		count          = count,
		columns        = columns,
		rays           = rays,
		workers        = threads,
		directions     = directions,
		radiance       = radiance,
		distances      = distances,
		shadow_counts  = shadow_counts,
		invalid_counts = invalid_counts,
	}
	if !parallel_run(&Parallel_Work{job = &work, run = probe_worker}, threads, allocator) {
		delete(result.states, allocator)
		return {}, .Threads
	}
	result.dilated_probes = probe_dilate(&work)

	for value in shadow_counts {
		result.shadow_rays += value
	}
	for value in invalid_counts {
		result.invalid_probes += value
	}
	result.rays = u64(count - result.invalid_probes) * u64(rays)
	result.irradiance = f16_slice_to_bytes(irradiance, allocator)
	result.moments = f16_slice_to_bytes(moments, allocator)
	return result, .None
}

probe_destroy :: proc(result: ^Probe_Result, allocator: mem.Allocator) {
	if result.irradiance != nil {
		delete(result.irradiance, allocator)
	}
	if result.moments != nil {
		delete(result.moments, allocator)
	}
	if result.states != nil {
		delete(result.states, allocator)
	}
	result^ = {}
}

@(private)
probe_worker :: proc(job: rawptr, worker: int) #no_bounds_check {
	work := cast(^Probe_Work)job
	first := worker * work.rays
	directions := work.directions[first:first + work.rays]
	radiance := work.radiance[first:first + work.rays]
	distances := work.distances[first:first + work.rays]
	shadows: u64
	for probe := worker; probe < work.count; probe += work.workers {
		x := probe % work.counts.x
		y := (probe / work.counts.x) % work.counts.y
		z := probe / (work.counts.x * work.counts.y)
		base := dv_add(
			work.min,
			dv_mul({f64(x) + 0.5, f64(y) + 0.5, f64(z) + 0.5}, work.spacing),
		)
		sample, offset, valid := probe_sample(work.static, work.bvh, base, work.spacing * PROBE_OFFSET_MAX_FRACTION)
		if !valid {
			work.invalid_counts[worker] += 1
			continue
		}
		work.states[probe] = {
			valid  = 1,
			offset = {f16(offset.x), f16(offset.y), f16(offset.z)},
		}
		seed := seed_for(PROBE_KIND, u64(probe))
		rotation_x := unit_from_hash(seed)
		rotation_y := unit_from_hash(hash64(seed))
		for ray_index in 0 ..< work.rays {
			direction := probe_direction(ray_index, work.rays, rotation_x, rotation_y)
			directions[ray_index] = direction
			ray := ray_make(sample, direction)
			hit, hit_ok := ray_cast(work.bvh, ray, RAY_TMIN, RAY_MAX)
			if !hit_ok {
				radiance[ray_index] = {}
				distances[ray_index] = RAY_MAX
				continue
			}
			value, shadow_rays := shade_hit(work.static, work.bvh, ray, hit)
			radiance[ray_index] = hit.front ? value : [3]f64{}
			distances[ray_index] = hit.front ? hit.t : -hit.t
			shadows += shadow_rays
		}
		probe_blend(work, probe, directions, radiance, distances)
	}
	work.shadow_counts[worker] = shadows
}

// The stored octahedral irradiance and depth moments use the legacy gamma-5
// storage encoding: irradiance is (radiance/2)^(1/5), and the moments are
// halved. The sampler decodes the irradiance with pow(encoded, 2.5) and applies
// the final 2x factor, so the bake and the shader must change together.
@(private)
probe_blend :: proc(
	work: ^Probe_Work,
	probe: int,
	directions: []DVec3,
	radiance: []DVec3,
	distances: []f64,
) #no_bounds_check {
	max_distance := work.spacing * math.sqrt(3.0) * 1.5
	normals: [PROBE_TEXEL_COUNT]DVec3
	sum_x, sum_y, sum_z: [PROBE_TEXEL_COUNT]f64
	cosine_sum, distance_sum, distance2_sum, distance_weight: [PROBE_TEXEL_COUNT]f64
	for ty in 0 ..< PROBE_TEXELS {
		for tx in 0 ..< PROBE_TEXELS {
			normals[ty * PROBE_TEXELS + tx] = oct_texel_normal(tx, ty, PROBE_TEXELS)
		}
	}

	for ray_index in 0 ..< work.rays {
		direction := directions[ray_index]
		value := radiance[ray_index]
		distance_value := min(math.abs(distances[ray_index]), max_distance)
		front := distances[ray_index] >= 0
		for texel in 0 ..< PROBE_TEXEL_COUNT {
			cosine := dv_dot(normals[texel], direction)
			if cosine <= 0 {
				continue
			}
			if front {
				sum_x[texel] += value.x * cosine
				sum_y[texel] += value.y * cosine
				sum_z[texel] += value.z * cosine
				cosine_sum[texel] += cosine
			}
			weight := pow50(cosine)
			distance_sum[texel] += distance_value * weight
			distance2_sum[texel] += distance_value * distance_value * weight
			distance_weight[texel] += weight
		}
	}

	for ty in 0 ..< PROBE_TEXELS {
		for tx in 0 ..< PROBE_TEXELS {
			texel := ty * PROBE_TEXELS + tx
			denominator := 2.0 * max(cosine_sum[texel], 1e-9)
			encoded := DVec3 {
				pow_ratio(sum_x[texel] / denominator, 1.0 / PROBE_IRRADIANCE_GAMMA),
				pow_ratio(sum_y[texel] / denominator, 1.0 / PROBE_IRRADIANCE_GAMMA),
				pow_ratio(sum_z[texel] / denominator, 1.0 / PROBE_IRRADIANCE_GAMMA),
			}
			depth_denominator := 2.0 * max(distance_weight[texel], 1e-9)
			pixel := probe_atlas_pixel(probe, tx, ty, work.columns, PROBE_TEXELS)
			work.irradiance[pixel * 4 + 0] = f16(encoded.x)
			work.irradiance[pixel * 4 + 1] = f16(encoded.y)
			work.irradiance[pixel * 4 + 2] = f16(encoded.z)
			work.irradiance[pixel * 4 + 3] = 1.0
			work.moments[pixel * 2 + 0] = f16(distance_sum[texel] / depth_denominator)
			work.moments[pixel * 2 + 1] = f16(distance2_sum[texel] / depth_denominator)
		}
	}
}

@(private)
// The old probe blend used pow(cosine, 50). Repeated squaring keeps the same
// angular falloff without a transcendental call in the probe loop.
pow50 :: proc(value: f64) -> f64 {
	square := value * value
	quad := square * square
	eight := quad * quad
	sixteen := eight * eight
	thirty_two := sixteen * sixteen
	return thirty_two * sixteen * square
}

@(private)
pow_ratio :: proc(value: f64, power: f64) -> f64 {
	if value <= 0 {
		return 0
	}
	return math.pow(value, power)
}

probe_atlas_pixel :: proc(probe, x, y, columns, grid: int) -> int {
	column := probe % columns
	row := probe / columns
	return (row * grid + y) * (columns * grid) + column * grid + x
}

probe_columns :: proc(count: int) -> int {
	target := int(math.sqrt(f64(count)))
	for columns := target; columns >= 1; columns -= 1 {
		if count % columns == 0 {
			return columns
		}
	}
	return 1
}

probe_sample :: proc(
	static: Static,
	bvh: ^Bvh,
	base: DVec3,
	max_offset: f64,
) -> (
	sample: DVec3,
	offset: DVec3,
	valid: bool,
) {
	if !inside_any_box(static, bvh, base) {
		return base, {}, true
	}
	best_distance := f64(1e30)
	for entry, index in static.boxes {
		if !box_contains_rotation(entry.box, bvh.rotations[index], base, 0.001) {
			continue
		}
		local := quat_inverse_rotate(
			bvh.rotations[index],
			dv_sub(base, dv(entry.box.center)),
		)
		half := dv(entry.box.half_extents)
		for axis in 0 ..< 3 {
			for sign in ([2]f64{-1.0, 1.0}) {
				face_distance := half[axis] - sign * local[axis]
				if face_distance < 0 || face_distance + PROBE_OFFSET_MARGIN > max_offset {
					continue
				}
				local_offset := dv_mul(dv_axis(axis), sign * (face_distance + PROBE_OFFSET_MARGIN))
				candidate_offset := quat_rotate(bvh.rotations[index], local_offset)
				candidate := dv_add(base, candidate_offset)
				if inside_any_box(static, bvh, candidate) {
					continue
				}
				if face_distance < best_distance {
					best_distance = face_distance
					sample = candidate
					offset = candidate_offset
					valid = true
				}
			}
		}
	}
	return
}

@(private)
inside_any_box :: proc(static: Static, bvh: ^Bvh, point: DVec3) -> bool {
	for entry, index in static.boxes {
		if box_contains_rotation(entry.box, bvh.rotations[index], point, 0.001) {
			return true
		}
	}
	return false
}
