#+vet explicit-allocators
package bake

import "core:mem"

LIGHTMAP_KIND :: u64(1)

Lightmap_Result :: struct {
	atlas:          []u8,
	layout:         Atlas_Layout,
	valid_texels:   int,
	invalid_texels: int,
	dilated_texels: int,
	rays:           u64,
	shadow_rays:    u64,
}

Texel_Job :: struct {
	chart: int,
	x:     int,
	y:     int,
	index: int,
}

Lightmap_Work :: struct {
	static:        Static,
	bvh:           ^Bvh,
	layout:        ^Atlas_Layout,
	atlas:         []f32,
	jobs:          []Texel_Job,
	rays:          int,
	workers:       int,
	shadow_counts: []u64,
	atlas_size:    int,
}

lightmap_bake :: proc(
	static: Static,
	bvh: ^Bvh,
	quality: Quality,
	threads: int,
	allocator: mem.Allocator,
) -> (
	result: Lightmap_Result,
	err: Build_Error,
) {
	layout, layout_error := atlas_layout(static, quality, allocator)
	if layout_error != .None {
		return {}, layout_error
	}
	result.layout = layout
	atlas_size := int(quality.atlas_size)
	atlas := make([]f32, atlas_size * atlas_size * 4, allocator)
	defer delete(atlas, allocator)
	valid := make([]bool, atlas_size * atlas_size, allocator)
	defer delete(valid, allocator)
	mem.set(raw_data(atlas), 0, len(atlas) * size_of(f32))
	mem.set(raw_data(valid), 0, len(valid))

	jobs := make([dynamic]Texel_Job, 0, 0, allocator)
	defer delete(jobs)
	for chart, chart_index in layout.charts {
		for y in 0 ..< chart.height {
			for x in 0 ..< chart.width {
				position, normal := face_texel_position(
					static.boxes[chart.box].box,
					chart.face,
					x,
					y,
					chart.width,
					chart.height,
				)
				origin := dv_add(position, dv_mul(normal, SURFACE_PUSHOFF))
				if texel_buried(static, bvh, chart.box, position, origin) {
					result.invalid_texels += 1
					continue
				}
				index := (chart.y + y) * atlas_size + chart.x + x
				valid[index] = true
				append(&jobs, Texel_Job{chart = chart_index, x = x, y = y, index = index})
			}
		}
	}

	shadow_counts := make([]u64, threads, allocator)
	defer delete(shadow_counts, allocator)
	mem.set(raw_data(shadow_counts), 0, len(shadow_counts) * size_of(u64))
	work := Lightmap_Work {
		static        = static,
		bvh           = bvh,
		layout        = &layout,
		atlas         = atlas,
		jobs          = jobs[:],
		rays          = int(quality.lightmap_rays),
		workers       = threads,
		shadow_counts = shadow_counts,
		atlas_size    = atlas_size,
	}
	if !parallel_run(&Parallel_Work{job = &work, run = lightmap_worker}, threads, allocator) {
		atlas_layout_destroy(&layout, allocator)
		return {}, .Threads
	}

	// `dilated_texels` counts every copied texel: repaired buried interiors plus
	// the four-texel gutter. `invalid_texels` counts the buried interiors before
	// the repair, so the two counts overlap by design.
	queue := make([dynamic]int, 0, 0, allocator)
	defer delete(queue)
	scratch := make([]f32, denoise_scratch_len(&layout), allocator)
	defer delete(scratch, allocator)
	for chart in layout.charts {
		result.dilated_texels += atlas_fill_chart(atlas, valid, chart, atlas_size, &queue)
		lightmap_denoise_chart(atlas, chart, atlas_size, scratch)
		result.dilated_texels += atlas_gutter_chart(
			atlas,
			chart,
			atlas_size,
			int(quality.gutter_texels),
		)
	}
	result.valid_texels = len(jobs)
	result.rays = u64(len(jobs)) * u64(quality.lightmap_rays)
	for count in shadow_counts {
		result.shadow_rays += count
	}
	result.atlas = atlas_to_bytes(atlas, allocator)
	return result, .None
}

lightmap_destroy :: proc(result: ^Lightmap_Result, allocator: mem.Allocator) {
	if result.atlas != nil {
		delete(result.atlas, allocator)
	}
	atlas_layout_destroy(&result.layout, allocator)
	result^ = {}
}

@(private)
lightmap_worker :: proc(job: rawptr, worker: int) #no_bounds_check {
	work := cast(^Lightmap_Work)job
	shadows: u64
	for job_index := worker; job_index < len(work.jobs); job_index += work.workers {
		texel := work.jobs[job_index]
		shadows += lightmap_trace(work, texel)
	}
	work.shadow_counts[worker] = shadows
}

@(private)
lightmap_trace :: proc(work: ^Lightmap_Work, texel: Texel_Job) -> u64 #no_bounds_check {
	chart := work.layout.charts[texel.chart]
	position, normal := face_texel_position(
		work.static.boxes[chart.box].box,
		chart.face,
		texel.x,
		texel.y,
		chart.width,
		chart.height,
	)
	origin := dv_add(position, dv_mul(normal, SURFACE_PUSHOFF))
	seed := lightmap_seed(work.static.boxes[chart.box], chart.face, texel.x, texel.y)
	rotation := [2]f64{unit_from_hash(seed), unit_from_hash(hash64(seed))}
	sum := DVec3{}
	shadows: u64
	for ray_index in 0 ..< work.rays {
		direction := cosine_hemisphere(normal, ray_index, work.rays, rotation)
		ray := ray_make(origin, direction)
		hit, hit_ok := ray_cast(work.bvh, ray, RAY_TMIN, RAY_MAX)
		if !hit_ok {
			continue
		}
		radiance, shadow_rays := shade_hit(work.static, work.bvh, ray, hit)
		sum = dv_add(sum, radiance)
		shadows += shadow_rays
	}
	scale := 1.0 / f64(work.rays)
	work.atlas[texel.index * 4 + 0] = f32(sum.x * scale)
	work.atlas[texel.index * 4 + 1] = f32(sum.y * scale)
	work.atlas[texel.index * 4 + 2] = f32(sum.z * scale)
	work.atlas[texel.index * 4 + 3] = 1.0
	return shadows
}

// The noise field follows the surface, not the atlas position, so an unrelated
// static edit does not re-roll every texel of an unchanged wall.
@(private)
lightmap_seed :: proc(entry: Box_Entry, face, x, y: int) -> u64 {
	surface := hash64(slot_key(entry.source, entry.id) ~ u64(face))
	return seed_for(LIGHTMAP_KIND, surface ~ (u64(x) | u64(y) << 32))
}

@(private)
texel_buried :: proc(
	static: Static,
	bvh: ^Bvh,
	receiver: int,
	position, origin: DVec3,
) -> bool {
	for entry, index in static.boxes {
		if index == receiver {
			continue
		}
		if box_contains_rotation(entry.box, bvh.rotations[index], position, 0.001) ||
		   box_contains_rotation(entry.box, bvh.rotations[index], origin, 0.001) {
			return true
		}
	}
	return false
}
