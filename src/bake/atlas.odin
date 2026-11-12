#+vet explicit-allocators
package bake

import "core:math"
import "core:mem"
import "core:slice"

Chart :: struct {
	box:    int,
	face:   int,
	x:      int,
	y:      int,
	width:  int,
	height: int,
}

// The packer sorts these before placement. A tall chart first means the shelf
// height is set by the tallest entry, so smaller faces do not leave a tall row
// with a mostly empty upper half.
Chart_Plan :: struct {
	box:         int,
	face:        int,
	width:       int,
	height:      int,
	alloc_width: int,
	alloc_height: int,
}

Atlas_Layout :: struct {
	charts: [dynamic]Chart,
	faces:  []Face,
	slots:  []Slot,
}

atlas_layout_destroy :: proc(layout: ^Atlas_Layout, allocator: mem.Allocator) {
	if layout.charts != nil {
		delete(layout.charts)
	}
	if layout.faces != nil {
		delete(layout.faces, allocator)
	}
	if layout.slots != nil {
		delete(layout.slots, allocator)
	}
	layout^ = {}
}

atlas_layout :: proc(
	static: Static,
	quality: Quality,
	allocator: mem.Allocator,
) -> (
	layout: Atlas_Layout,
	err: Build_Error,
) {
	atlas_size := int(quality.atlas_size)
	pad := int(quality.gutter_texels)
	if atlas_size <= 0 || quality.texels_per_meter == 0 || pad < 0 || quality.min_chart == 0 {
		return {}, .Atlas_Full
	}

	slot_count := len(static.boxes)
	layout.charts = make([dynamic]Chart, 0, slot_count * FACE_COUNT, allocator)
	layout.faces = make([]Face, slot_count * FACE_COUNT, allocator)
	layout.slots = make([]Slot, slot_count, allocator)

	plans := make([dynamic]Chart_Plan, 0, slot_count * FACE_COUNT, allocator)
	defer delete(plans)
	for entry, box_index in static.boxes {
		key := slot_key(entry.source, entry.id, entry.box)
		layout.slots[box_index] = {
			key        = key,
			first_face = u32(box_index * FACE_COUNT),
			face_count = FACE_COUNT,
		}
		for face in 0 ..< FACE_COUNT {
			width_meters, height_meters := face_size(entry.box, face)
			texels := f64(quality.texels_per_meter)
			width := max(int(quality.min_chart), int(math.ceil(width_meters * texels)))
			height := max(int(quality.min_chart), int(math.ceil(height_meters * texels)))
			append(&plans, Chart_Plan {
				box = box_index,
				face = face,
				width = width,
				height = height,
				alloc_width = width + 2 * pad,
				alloc_height = height + 2 * pad,
			})
		}
	}
	slice.sort_by(plans[:], proc(a, b: Chart_Plan) -> bool {
		if a.alloc_height != b.alloc_height {
			return a.alloc_height > b.alloc_height
		}
		if a.alloc_width != b.alloc_width {
			return a.alloc_width > b.alloc_width
		}
		if a.box != b.box {
			return a.box < b.box
		}
		return a.face < b.face
	})

	cursor_x := 0
	cursor_y := 0
	row_height := 0
	for plan in plans {
		if plan.alloc_width > atlas_size || plan.alloc_height > atlas_size {
			atlas_layout_destroy(&layout, allocator)
			return {}, .Atlas_Full
		}
		if cursor_x + plan.alloc_width > atlas_size {
			cursor_x = 0
			cursor_y += row_height
			row_height = 0
		}
		if cursor_y + plan.alloc_height > atlas_size {
			atlas_layout_destroy(&layout, allocator)
			return {}, .Atlas_Full
		}
		chart := Chart {
			box    = plan.box,
			face   = plan.face,
			x      = cursor_x + pad,
			y      = cursor_y + pad,
			width  = plan.width,
			height = plan.height,
		}
		append(&layout.charts, chart)
		layout.faces[plan.box * FACE_COUNT + plan.face] = {
			key     = layout.slots[plan.box].key,
			slot    = u32(plan.box),
			face    = u8(plan.face),
			uv_rect = center_to_center(chart, atlas_size),
		}
		cursor_x += plan.alloc_width
		row_height = max(row_height, plan.alloc_height)
	}
	return layout, .None
}

// Every chart owns the chart rect plus one gutter on each side. The sum is the
// atlas texels the layout allocates, not the baked or valid texel count.
atlas_allocated_texels :: proc(faces: []Face, atlas_size, pad: int) -> int {
	total := 0
	for face in faces {
		width := int(math.round(f64((face.uv_rect[2] - face.uv_rect[0]) * f32(atlas_size)))) + 1
		height := int(math.round(f64((face.uv_rect[3] - face.uv_rect[1]) * f32(atlas_size)))) + 1
		total += (width + 2 * pad) * (height + 2 * pad)
	}
	return total
}

@(private)
center_to_center :: proc(chart: Chart, atlas_size: int) -> [4]f32 {
	size := f32(atlas_size)
	return {
		(f32(chart.x) + 0.5) / size,
		(f32(chart.y) + 0.5) / size,
		(f32(chart.x + chart.width) - 0.5) / size,
		(f32(chart.y + chart.height) - 0.5) / size,
	}
}

// A buried texel clones the nearest valid texel inside its own chart. The fill
// is a multi-source breadth-first pass, so a fully buried chart costs its area
// instead of a ring search per texel.
atlas_fill_chart :: proc(
	atlas: []f32,
	valid: []bool,
	chart: Chart,
	atlas_size: int,
	queue: ^[dynamic]int,
) -> (filled: int) {
	clear(queue)
	for y in chart.y ..< chart.y + chart.height {
		for x in chart.x ..< chart.x + chart.width {
			index := y * atlas_size + x
			if valid[index] {
				append(queue, index)
			}
		}
	}
	head := 0
	for head < len(queue) {
		source := queue[head]
		head += 1
		source_x := source % atlas_size
		source_y := source / atlas_size
		for dy in -1 ..= 1 {
			for dx in -1 ..= 1 {
				if dx == 0 && dy == 0 {
					continue
				}
				x := source_x + dx
				y := source_y + dy
				if x < chart.x || x >= chart.x + chart.width ||
				   y < chart.y || y >= chart.y + chart.height {
					continue
				}
				index := y * atlas_size + x
				if valid[index] {
					continue
				}
				copy_texel(atlas, index, source)
				valid[index] = true
				append(queue, index)
				filled += 1
			}
		}
	}
	return
}

// The gutter clones the chart edge, so a bilinear tap never reads black or a
// neighbouring chart.
atlas_gutter_chart :: proc(
	atlas: []f32,
	chart: Chart,
	atlas_size: int,
	pad: int,
) -> (dilated: int) {
	for y in chart.y - pad ..< chart.y + chart.height + pad {
		for x in chart.x - pad ..< chart.x + chart.width + pad {
			if x >= chart.x && x < chart.x + chart.width &&
			   y >= chart.y && y < chart.y + chart.height {
				continue
			}
			source_x := clamp(x, chart.x, chart.x + chart.width - 1)
			source_y := clamp(y, chart.y, chart.y + chart.height - 1)
			copy_texel(atlas, y * atlas_size + x, source_y * atlas_size + source_x)
			dilated += 1
		}
	}
	return
}

@(private)
copy_texel :: proc(atlas: []f32, destination, source: int) {
	for channel in 0 ..< 4 {
		atlas[destination * 4 + channel] = atlas[source * 4 + channel]
	}
}

f16_buffer :: proc(count: int, allocator: mem.Allocator) -> (bytes: []u8, values: [^]f16) {
	bytes = make([]u8, count * 2, allocator)
	values = cast([^]f16)raw_data(bytes)
	return
}

f16_slice_to_bytes :: proc(values: []f16, allocator: mem.Allocator) -> []u8 {
	bytes, output := f16_buffer(len(values), allocator)
	for value, index in values {
		output[index] = value
	}
	return bytes
}

u32_slice_to_bytes :: proc(values: []u32, allocator: mem.Allocator) -> []u8 {
	bytes := make([]u8, len(values) * size_of(u32), allocator)
	if len(values) > 0 {
		mem.copy(raw_data(bytes), raw_data(values), len(bytes))
	}
	return bytes
}

atlas_to_bytes :: proc(atlas: []f32, allocator: mem.Allocator) -> []u8 {
	bytes, values := f16_buffer(len(atlas), allocator)
	for value, index in atlas {
		values[index] = f16(value)
	}
	return bytes
}
