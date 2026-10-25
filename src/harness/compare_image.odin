#+vet explicit-allocators
package harness

import "core:mem"

Compare_Canvas :: struct {
	width:  int,
	height: int,
	pixels: []u8,
}

compare_canvas_create :: proc(width, height: int, allocator: mem.Allocator) -> Compare_Canvas {
	if width <= 0 || height <= 0 {
		return {}
	}
	return {
		width = width,
		height = height,
		pixels = make([]u8, width * height * 4, allocator),
	}
}

compare_canvas_destroy :: proc(canvas: ^Compare_Canvas, allocator: mem.Allocator) {
	if canvas.pixels != nil {
		delete(canvas.pixels, allocator)
	}
	canvas^ = {}
}

compare_canvas_fill :: proc(canvas: ^Compare_Canvas, color: [4]u8) {
	for index := 0; index < len(canvas.pixels); index += 4 {
		canvas.pixels[index + 0] = color[0]
		canvas.pixels[index + 1] = color[1]
		canvas.pixels[index + 2] = color[2]
		canvas.pixels[index + 3] = color[3]
	}
}

compare_canvas_fill_rect :: proc(
	canvas: ^Compare_Canvas,
	x, y, width, height: int,
	color: [4]u8,
) {
	for row in max(y, 0) ..< min(y + height, canvas.height) {
		for column in max(x, 0) ..< min(x + width, canvas.width) {
			compare_canvas_set_pixel(canvas, column, row, color)
		}
	}
}

compare_canvas_border :: proc(
	canvas: ^Compare_Canvas,
	x, y, width, height: int,
	color: [4]u8,
	thickness := 1,
) {
	for step in 0 ..< thickness {
		compare_canvas_fill_rect(canvas, x + step, y + step, width - step * 2, 1, color)
		compare_canvas_fill_rect(canvas, x + step, y + height - 1 - step, width - step * 2, 1, color)
		compare_canvas_fill_rect(canvas, x + step, y + step, 1, height - step * 2, color)
		compare_canvas_fill_rect(canvas, x + width - 1 - step, y + step, 1, height - step * 2, color)
	}
}

compare_canvas_set_pixel :: proc(canvas: ^Compare_Canvas, x, y: int, color: [4]u8) {
	if x < 0 || y < 0 || x >= canvas.width || y >= canvas.height {
		return
	}
	index := (y * canvas.width + x) * 4
	canvas.pixels[index + 0] = color[0]
	canvas.pixels[index + 1] = color[1]
	canvas.pixels[index + 2] = color[2]
	canvas.pixels[index + 3] = color[3]
}

compare_canvas_blend_pixel :: proc(
	canvas: ^Compare_Canvas,
	x, y: int,
	color: [4]u8,
	coverage: u8,
) {
	if x < 0 || y < 0 || x >= canvas.width || y >= canvas.height {
		return
	}
	index := (y * canvas.width + x) * 4
	alpha := f32(coverage) / 255.0
	canvas.pixels[index + 0] = u8(f32(color[0]) * alpha + f32(canvas.pixels[index + 0]) * (1.0 - alpha))
	canvas.pixels[index + 1] = u8(f32(color[1]) * alpha + f32(canvas.pixels[index + 1]) * (1.0 - alpha))
	canvas.pixels[index + 2] = u8(f32(color[2]) * alpha + f32(canvas.pixels[index + 2]) * (1.0 - alpha))
	canvas.pixels[index + 3] = max(canvas.pixels[index + 3], color[3])
}

compare_canvas_blit_scaled :: proc(
	canvas: ^Compare_Canvas,
	dest_x, dest_y, dest_width, dest_height: int,
	pixels: []u8,
	source_width, source_height: int,
) {
	if dest_width <= 0 || dest_height <= 0 || source_width <= 0 || source_height <= 0 {
		return
	}
	if len(pixels) < source_width * source_height * 4 {
		return
	}
	for row in 0 ..< dest_height {
		source_row := row * source_height / dest_height
		for column in 0 ..< dest_width {
			source_column := column * source_width / dest_width
			source := (source_row * source_width + source_column) * 4
			target := ((dest_y + row) * canvas.width + dest_x + column) * 4
			if dest_x + column < 0 || dest_x + column >= canvas.width {
				continue
			}
			if dest_y + row < 0 || dest_y + row >= canvas.height {
				continue
			}
			canvas.pixels[target + 0] = pixels[source + 0]
			canvas.pixels[target + 1] = pixels[source + 1]
			canvas.pixels[target + 2] = pixels[source + 2]
			canvas.pixels[target + 3] = 255
		}
	}
}
