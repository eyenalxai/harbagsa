#+vet explicit-allocators
package harness

import "core:mem"

compare_draw_slot :: proc(
	canvas: ^Compare_Canvas,
	text: ^Compare_Text,
	x, y: int,
	run: Run_Data,
	pair: Compare_Pair,
	is_first: bool,
	max_scale: int,
	allocator: mem.Allocator,
) {
	compare_canvas_border(canvas, x, y, COMPARE_COLUMN_WIDTH, COMPARE_COLUMN_HEIGHT, COMPARE_BORDER)
	missing := is_first ? pair.missing_a : pair.missing_b
	if missing || pair.decode_error {
		compare_canvas_fill_rect(
			canvas,
			x + 1,
			y + 1,
			COMPARE_COLUMN_WIDTH - 2,
			COMPARE_COLUMN_HEIGHT - 2,
			COMPARE_PLACEHOLDER,
		)
		message := missing ? (is_first ? "missing in A" : "missing in B") : "decode error"
		message_width := compare_text_width(text, message)
		compare_text_draw(
			canvas,
			text,
			message,
			x + (COMPARE_COLUMN_WIDTH - message_width) / 2,
			y + COMPARE_COLUMN_HEIGHT / 2,
			COMPARE_ERROR,
		)
		return
	}
	capture, found := diff_capture_find(run.captures, pair.name)
	if !found || capture.path == "" {
		return
	}
	pixels, source_width, source_height, ok := load_png_rgba(capture.path, allocator)
	defer delete(pixels, allocator)
	if !ok {
		return
	}
	scale := min(
		f32(COMPARE_COLUMN_WIDTH - 2) / f32(source_width),
		f32(COMPARE_COLUMN_HEIGHT - 2) / f32(source_height),
	)
	scale = min(scale, f32(max(max_scale, 1)))
	draw_width := max(1, int(f32(source_width) * scale))
	draw_height := max(1, int(f32(source_height) * scale))
	draw_x := x + 1 + (COMPARE_COLUMN_WIDTH - 2 - draw_width) / 2
	draw_y := y + 1 + (COMPARE_COLUMN_HEIGHT - 2 - draw_height) / 2
	compare_canvas_blit_scaled(
		canvas,
		draw_x,
		draw_y,
		draw_width,
		draw_height,
		pixels,
		int(source_width),
		int(source_height),
	)
}

@(private)
compare_draw_delta :: proc(
	canvas: ^Compare_Canvas,
	x, y: int,
	first, second: Run_Data,
	pair: Compare_Pair,
	max_scale: int,
	allocator: mem.Allocator,
) {
	compare_canvas_border(canvas, x, y, COMPARE_COLUMN_WIDTH, COMPARE_COLUMN_HEIGHT, COMPARE_BORDER)
	if !pair.ok {
		compare_canvas_fill_rect(
			canvas,
			x + 1,
			y + 1,
			COMPARE_COLUMN_WIDTH - 2,
			COMPARE_COLUMN_HEIGHT - 2,
			COMPARE_PLACEHOLDER,
		)
		return
	}
	first_capture, first_found := diff_capture_find(first.captures, pair.name)
	second_capture, second_found := diff_capture_find(second.captures, pair.name)
	if !first_found || !second_found {
		return
	}
	first_pixels, first_width, first_height, first_ok := load_png_rgba(first_capture.path, allocator)
	defer delete(first_pixels, allocator)
	second_pixels, second_width, second_height, second_ok := load_png_rgba(second_capture.path, allocator)
	defer delete(second_pixels, allocator)
	if !first_ok || !second_ok || first_width != second_width || first_height != second_height {
		return
	}
	diff := make([]u8, len(first_pixels), allocator)
	defer delete(diff, allocator)
	for index := 0; index < len(first_pixels); index += 4 {
		diff[index + 0] = u8(min(255, abs(i32(first_pixels[index + 0]) - i32(second_pixels[index + 0])) * 4))
		diff[index + 1] = u8(min(255, abs(i32(first_pixels[index + 1]) - i32(second_pixels[index + 1])) * 4))
		diff[index + 2] = u8(min(255, abs(i32(first_pixels[index + 2]) - i32(second_pixels[index + 2])) * 4))
		diff[index + 3] = 255
	}
	scale := min(
		f32(COMPARE_COLUMN_WIDTH - 2) / f32(first_width),
		f32(COMPARE_COLUMN_HEIGHT - 2) / f32(first_height),
	)
	scale = min(scale, f32(max(max_scale, 1)))
	draw_width := max(1, int(f32(first_width) * scale))
	draw_height := max(1, int(f32(first_height) * scale))
	draw_x := x + 1 + (COMPARE_COLUMN_WIDTH - 2 - draw_width) / 2
	draw_y := y + 1 + (COMPARE_COLUMN_HEIGHT - 2 - draw_height) / 2
	compare_canvas_blit_scaled(
		canvas,
		draw_x,
		draw_y,
		draw_width,
		draw_height,
		diff,
		int(first_width),
		int(first_height),
	)
}
