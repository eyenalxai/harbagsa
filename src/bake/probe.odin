#+vet explicit-allocators
package bake

import "core:math"
import "core:mem"

PROBE_KIND :: u64(2)

Probe_Result :: struct {
	irradiance:       []u8,
	moments:          []u8,
	states:           []Probe_State,
	min:              [3]f32,
	spacing:          f32,
	counts:           [3]u32,
	basis:            Probe_Basis,
	moment_texels:    u32,
	columns:          u32,
	rays:             u64,
	shadow_rays:      u64,
	invalid_probes:   int,
	dilated_probes:   int,
}

Probe_Work :: struct {
	static:           Static,
	bvh:              ^Bvh,
	basis:            Probe_Basis,
	moment_texels:    int,
	irradiance_u32:   []u32,
	irradiance_f16:   []f16,
	moments:          []f16,
	states:           []Probe_State,
	min:              DVec3,
	spacing:          f64,
	counts:           [3]int,
	count:            int,
	columns:          int,
	rays:             int,
	workers:          int,
	directions:       []DVec3,
	radiance:         []DVec3,
	distances:        []f64,
	shadow_counts:    []u64,
	invalid_counts:   []int,
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
	basis := Probe_Basis(quality.probe_basis)
	moment_texels := int(quality.probe_moment_texels)
	if quality.probe_texels != PROBE_TEXELS ||
	   (basis != .Octa && basis != .SH9) ||
	   (moment_texels != PROBE_MOMENT_TEXELS && moment_texels != PROBE_MOMENT_TEXELS_HIGH) {
		return {}, .Probe_Count
	}
	min, counts := probe_grid(quality.probe_spacing)
	count := int(counts.x) * int(counts.y) * int(counts.z)
	if count <= 0 {
		return {}, .Probe_Count
	}
	columns := probe_columns(count)
	rows := count / columns
	irradiance_width, irradiance_height := columns * PROBE_TEXELS, rows * PROBE_TEXELS
	if basis == .SH9 {
		irradiance_width, irradiance_height = PROBE_SH_TEXELS, count
	}
	moment_width, moment_height := columns * moment_texels, rows * moment_texels
	if irradiance_width > MAX_PROBE_ATLAS_DIM || irradiance_height > MAX_PROBE_ATLAS_DIM ||
	   moment_width > MAX_PROBE_ATLAS_DIM || moment_height > MAX_PROBE_ATLAS_DIM {
		return {}, .Probe_Count
	}

	result.min = min
	result.spacing = quality.probe_spacing
	result.counts = counts
	result.basis = basis
	result.moment_texels = u32(moment_texels)
	result.columns = u32(columns)
	result.states = make([]Probe_State, count, allocator)
	mem.set(raw_data(result.states), 0, count * size_of(Probe_State))
	irradiance_u32: []u32
	irradiance_f16: []f16
	if basis == .Octa {
		irradiance_u32 = make([]u32, count * PROBE_TEXEL_COUNT, allocator)
		mem.set(raw_data(irradiance_u32), 0, len(irradiance_u32) * size_of(u32))
	} else {
		irradiance_f16 = make([]f16, count * PROBE_SH_COEFFS * 4, allocator)
		mem.set(raw_data(irradiance_f16), 0, len(irradiance_f16) * size_of(f16))
	}
	defer {
		if irradiance_u32 != nil {
			delete(irradiance_u32, allocator)
		}
		if irradiance_f16 != nil {
			delete(irradiance_f16, allocator)
		}
	}
	moment_count := count * moment_texels * moment_texels
	moments := make([]f16, moment_count * PROBE_MOMENT_CHANNELS, allocator)
	defer delete(moments, allocator)
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
		basis          = basis,
		moment_texels  = moment_texels,
		irradiance_u32 = irradiance_u32,
		irradiance_f16 = irradiance_f16,
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
	result.dilated_probes = probe_dilate(&work, allocator)

	for value in shadow_counts {
		result.shadow_rays += value
	}
	for value in invalid_counts {
		result.invalid_probes += value
	}
	result.rays = u64(count - result.invalid_probes) * u64(rays)
	if basis == .Octa {
		result.irradiance = u32_slice_to_bytes(irradiance_u32, allocator)
	} else {
		result.irradiance = f16_slice_to_bytes(irradiance_f16, allocator)
	}
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
		x, y, z := probe_cell(probe, work.counts)
		base := probe_center(work.min, work.spacing, x, y, z)
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

probe_cell :: proc(probe: int, counts: [3]int) -> (x, y, z: int) {
	x = probe % counts.x
	y = (probe / counts.x) % counts.y
	z = probe / (counts.x * counts.y)
	return
}

probe_center :: proc(min: DVec3, spacing: f64, x, y, z: int) -> DVec3 {
	return dv_add(min, dv_mul({f64(x) + 0.5, f64(y) + 0.5, f64(z) + 0.5}, spacing))
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
