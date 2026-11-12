#+vet explicit-allocators
package bake

import "core:math"
import "core:mem"

LIGHTMAP_KIND :: u64(1)

Lightmap_Result :: struct {
	atlas:          []u8,
	layout:         Atlas_Layout,
	valid_texels:   int,
	invalid_texels: int,
	dilated_texels: int,
	allocated_texels: int,
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
	first_bounce:  []f32,
	charts:        []int,
	jobs:          []Texel_Job,
	rays:          int,
	workers:       int,
	shadow_counts: []u64,
	atlas_size:    int,
	second_pass:   bool,
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
	bounces := int(quality.bounces)
	result.allocated_texels = atlas_allocated_texels(
		layout.faces,
		atlas_size,
		int(quality.gutter_texels),
	)
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
	// `dilated_texels` counts every copied texel in the first pass: repaired
	// buried interiors plus the gutter. `invalid_texels` counts the buried
	// interiors before the repair, so the two counts overlap by design.
	result.dilated_texels = lightmap_filter_charts(
		atlas,
		valid,
		&layout,
		atlas_size,
		int(quality.gutter_texels),
		allocator,
	)
	result.valid_texels = len(jobs)
	result.rays = u64(len(jobs)) * u64(quality.lightmap_rays) * u64(bounces)
	for count in shadow_counts {
		result.shadow_rays += count
	}

	if bounces > 1 {
		// The second gather reads the finished first-bounce field and writes
		// only the added term, so a one-bounce build is byte-identical.
		first_bounce := make([]f32, len(atlas), allocator)
		defer delete(first_bounce, allocator)
		copy(first_bounce, atlas)
		mem.set(raw_data(atlas), 0, len(atlas) * size_of(f32))
		mem.set(raw_data(valid), 0, len(valid))
		for job in jobs {
			valid[job.index] = true
		}
		charts := make([]int, len(static.boxes) * FACE_COUNT, allocator)
		defer delete(charts, allocator)
		for chart, chart_index in layout.charts {
			charts[chart.box * FACE_COUNT + chart.face] = chart_index
		}
		work.first_bounce = first_bounce
		work.charts = charts
		work.second_pass = true
		if !parallel_run(&Parallel_Work{job = &work, run = lightmap_worker}, threads, allocator) {
			atlas_layout_destroy(&layout, allocator)
			return {}, .Threads
		}
		result.dilated_texels += lightmap_filter_charts(
			atlas,
			valid,
			&layout,
			atlas_size,
			int(quality.gutter_texels),
			allocator,
		)
		for index in 0 ..< len(atlas) / 4 {
			atlas[index * 4 + 0] += first_bounce[index * 4 + 0]
			atlas[index * 4 + 1] += first_bounce[index * 4 + 1]
			atlas[index * 4 + 2] += first_bounce[index * 4 + 2]
			atlas[index * 4 + 3] = 1.0
		}
	}
	result.atlas = atlas_to_bytes(atlas, allocator)
	return result, .None
}

@(private)
lightmap_filter_charts :: proc(
	atlas: []f32,
	valid: []bool,
	layout: ^Atlas_Layout,
	atlas_size, gutter: int,
	allocator: mem.Allocator,
) -> (dilated: int) {
	queue := make([dynamic]int, 0, 0, allocator)
	defer delete(queue)
	scratch := make([]f32, denoise_scratch_len(layout), allocator)
	defer delete(scratch, allocator)
	for chart in layout.charts {
		dilated += atlas_fill_chart(atlas, valid, chart, atlas_size, &queue)
		lightmap_denoise_chart(atlas, chart, atlas_size, scratch)
		dilated += atlas_gutter_chart(atlas, chart, atlas_size, gutter)
	}
	return
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
		if work.second_pass {
			point := dv_add(ray.origin, dv_mul(ray.direction, hit.t))
			sum = dv_add(sum, second_bounce_radiance(work, hit, point))
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

@(private)
second_bounce_radiance :: proc(work: ^Lightmap_Work, hit: Hit, point: DVec3) -> DVec3 {
	box := work.static.boxes[hit.box].box
	incident := lightmap_sample(work, hit.box, point, hit.normal)
	return {
		f64(box.color.x) * incident.x,
		f64(box.color.y) * incident.y,
		f64(box.color.z) * incident.z,
	}
}

// The local face and its coordinates use the same `face_point` mapping that
// baked the chart, so the sample lands on the hit surface.
@(private)
lightmap_sample :: proc(work: ^Lightmap_Work, box_index: int, point, normal: DVec3) -> DVec3 {
	local_normal := quat_inverse_rotate(work.bvh.rotations[box_index], normal)
	axis := 0
	if math.abs(local_normal.y) > math.abs(local_normal.x) {
		axis = 1
	}
	if math.abs(local_normal.z) > math.abs(local_normal[axis]) {
		axis = 2
	}
	face := axis * 2
	if local_normal[axis] < 0 {
		face += 1
	}
	chart := work.layout.charts[work.charts[box_index * FACE_COUNT + face]]
	entry := work.static.boxes[box_index]
	local := quat_inverse_rotate(
		work.bvh.rotations[box_index],
		dv_sub(point, dv(entry.box.center)),
	)
	basis := FACE_BASES[face]
	half := entry.box.half_extents
	u_axis := face_axis(basis.u)
	v_axis := face_axis(basis.v)
	s := 0.5 + local[u_axis] * f64(basis.u[u_axis]) / (2.0 * f64(half[u_axis]))
	t := 0.5 + local[v_axis] * f64(basis.v[v_axis]) / (2.0 * f64(half[v_axis]))
	return lightmap_bilinear(work.first_bounce, work.atlas_size, chart, s, t)
}

@(private)
lightmap_bilinear :: proc(
	atlas: []f32,
	atlas_size: int,
	chart: Chart,
	s, t: f64,
) -> DVec3 {
	fx := clamp(s, 0, 1) * f64(chart.width) - 0.5
	fy := clamp(t, 0, 1) * f64(chart.height) - 0.5
	x0 := int(math.floor(fx))
	y0 := int(math.floor(fy))
	tx := fx - f64(x0)
	ty := fy - f64(y0)
	x0 = clamp(x0, 0, chart.width - 1)
	y0 = clamp(y0, 0, chart.height - 1)
	x1 := min(x0 + 1, chart.width - 1)
	y1 := min(y0 + 1, chart.height - 1)
	row0 := (chart.y + y0) * atlas_size
	row1 := (chart.y + y1) * atlas_size
	index00 := (row0 + chart.x + x0) * 4
	index10 := (row0 + chart.x + x1) * 4
	index01 := (row1 + chart.x + x0) * 4
	index11 := (row1 + chart.x + x1) * 4
	result: DVec3
	for channel in 0 ..< 3 {
		top := f64(atlas[index00 + channel]) * (1.0 - tx) +
			f64(atlas[index10 + channel]) * tx
		bottom := f64(atlas[index01 + channel]) * (1.0 - tx) +
			f64(atlas[index11 + channel]) * tx
		result[channel] = top * (1.0 - ty) + bottom * ty
	}
	return result
}

// The noise field follows the surface, not the atlas position, so an unrelated
// static edit does not re-roll every texel of an unchanged wall. Hashing the
// identity and then the face gives every face its own field. The transform is
// deliberately absent: a moved box keeps its field after the republish.
@(private)
lightmap_seed :: proc(entry: Box_Entry, face, x, y: int) -> u64 {
	surface := hash64(hash64(slot_identity(entry.source, entry.id)) ~ u64(face))
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
