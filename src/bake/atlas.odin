#+vet explicit-allocators
package bake

import "core:math"
import "core:mem"

Chart :: struct {
	box:    int,
	face:   int,
	x:      int,
	y:      int,
	width:  int,
	height: int,
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

	cursor_x := 0
	cursor_y := 0
	row_height := 0
	for entry, box_index in static.boxes {
		key := slot_key(entry.source, entry.id)
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
			alloc_width := width + 2 * pad
			alloc_height := height + 2 * pad
			if alloc_width > atlas_size || alloc_height > atlas_size {
				atlas_layout_destroy(&layout, allocator)
				return {}, .Atlas_Full
			}
			if cursor_x + alloc_width > atlas_size {
				cursor_x = 0
				cursor_y += row_height
				row_height = 0
			}
			if cursor_y + alloc_height > atlas_size {
				atlas_layout_destroy(&layout, allocator)
				return {}, .Atlas_Full
			}
			chart := Chart {
				box    = box_index,
				face   = face,
				x      = cursor_x + pad,
				y      = cursor_y + pad,
				width  = width,
				height = height,
			}
			append(&layout.charts, chart)
			layout.faces[box_index * FACE_COUNT + face] = {
				key     = key,
				slot    = u32(box_index),
				face    = u8(face),
				uv_rect = center_to_center(chart, atlas_size),
			}
			cursor_x += alloc_width
			row_height = max(row_height, alloc_height)
		}
	}
	return layout, .None
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

// A buried texel clones the nearest valid texel inside its own chart. The
// gutter then clones the chart edge, so a bilinear tap never reads black or a
// neighbouring chart. The fill is a multi-source breadth-first pass, so a fully
// buried chart costs its area instead of a ring search per texel.
atlas_dilate_chart :: proc(
	atlas: []f32,
	valid: []bool,
	chart: Chart,
	atlas_size: int,
	pad: int,
	queue: ^[dynamic]int,
) -> (
	filled: int,
	dilated: int,
) {
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

atlas_to_bytes :: proc(atlas: []f32, allocator: mem.Allocator) -> []u8 {
	bytes := make([]u8, len(atlas) * 2, allocator)
	values := cast([^]f16)raw_data(bytes)
	for value, index in atlas {
		values[index] = f16(value)
	}
	return bytes
}
