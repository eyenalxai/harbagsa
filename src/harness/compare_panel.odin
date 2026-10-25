#+vet explicit-allocators
package harness

import "core:fmt"
import "core:mem"
import "core:strings"

COMPARE_MARGIN :: 24
COMPARE_GAP :: 20
COMPARE_COLUMN_WIDTH :: 640
COMPARE_COLUMN_HEIGHT :: 360
COMPARE_LINE_HEIGHT :: 22
COMPARE_HEADER_LINES :: 5
COMPARE_ROWS_PER_PAGE :: 6
COMPARE_ROW_LABEL_HEIGHT :: 22
COMPARE_ROW_DELTA_HEIGHT :: 22
COMPARE_ROW_GAP :: 16

COMPARE_BACKGROUND :: [4]u8{15, 20, 26, 255}
COMPARE_SURFACE :: [4]u8{25, 31, 38, 255}
COMPARE_PLACEHOLDER :: [4]u8{42, 28, 30, 255}
COMPARE_BORDER :: [4]u8{70, 80, 92, 255}
COMPARE_TEXT :: [4]u8{238, 242, 246, 255}
COMPARE_SECONDARY :: [4]u8{167, 178, 191, 255}
COMPARE_ACCENT :: [4]u8{230, 175, 58, 255}
COMPARE_ERROR :: [4]u8{220, 108, 108, 255}

compare_write_pages :: proc(
	report: ^Compare_Report,
	first, second: Compare_Run,
	out_dir: string,
	allocator: mem.Allocator,
) -> ([]string, string) {
	text := compare_text_init(allocator)
	if !text.ok {
		return nil, format_error("%s", "cannot build the compare text atlas")
	}
	defer compare_text_destroy(&text)

	total_pages := max(1, (len(report.pairs) + COMPARE_ROWS_PER_PAGE - 1) / COMPARE_ROWS_PER_PAGE)
	pages := make([dynamic]string, 0, total_pages, allocator)
	for page in 0 ..< total_pages {
		start := page * COMPARE_ROWS_PER_PAGE
		end := min(start + COMPARE_ROWS_PER_PAGE, len(report.pairs))
		canvas := compare_panel_canvas(report, first, second, page, total_pages, report.pairs[start:end], &text, allocator)
		if canvas.pixels == nil {
			compare_pages_destroy(pages[:], allocator)
			return nil, format_error("%s", "cannot allocate the compare panel")
		}
		name := "compare"
		if page > 0 {
			name = fmt.aprintf("compare-%d", page + 1, allocator = context.temp_allocator)
		}
		written, write_error := capture_write_png(
			out_dir,
			name,
			0,
			u32(canvas.width),
			u32(canvas.height),
			canvas.pixels,
			allocator,
		)
		compare_canvas_destroy(&canvas, allocator)
		if write_error != "" {
			compare_pages_destroy(pages[:], allocator)
			return nil, write_error
		}
		append(&pages, strings.clone(written.path, allocator))
		capture_result_destroy(&written, allocator)
	}
	return pages[:], ""
}

compare_pages_destroy :: proc(pages: []string, allocator: mem.Allocator) {
	for page in pages {
		delete(page, allocator)
	}
	delete(pages, allocator)
}

@(private)
compare_panel_canvas :: proc(
	report: ^Compare_Report,
	first, second: Compare_Run,
	page, total_pages: int,
	pairs: []Compare_Pair,
	text: ^Compare_Text,
	allocator: mem.Allocator,
) -> Compare_Canvas {
	header_height := COMPARE_MARGIN + COMPARE_HEADER_LINES * COMPARE_LINE_HEIGHT + 10
	row_height :=
		COMPARE_ROW_LABEL_HEIGHT + COMPARE_COLUMN_HEIGHT + COMPARE_ROW_DELTA_HEIGHT + COMPARE_ROW_GAP
	height := header_height + len(pairs) * row_height + COMPARE_MARGIN
	width := COMPARE_MARGIN * 2 + COMPARE_COLUMN_WIDTH * 2 + COMPARE_GAP
	canvas := compare_canvas_create(width, height, allocator)
	if canvas.pixels == nil {
		return {}
	}
	compare_canvas_fill(&canvas, COMPARE_BACKGROUND)

	baseline := COMPARE_MARGIN + 16
	compare_text_draw(
		&canvas,
		text,
		compare_text_fit(text, fmt.aprintf(
			"A  %s  rev %s%s",
			report.scenario_a,
			report.revision_a,
			report.dirty_a ? " dirty" : "",
			allocator = context.temp_allocator,
		), width - COMPARE_MARGIN * 2),
		COMPARE_MARGIN,
		baseline,
		COMPARE_ACCENT,
	)
	baseline += COMPARE_LINE_HEIGHT
	compare_text_draw(
		&canvas,
		text,
		compare_text_fit(text, first.dir, width - COMPARE_MARGIN * 2),
		COMPARE_MARGIN,
		baseline,
		COMPARE_SECONDARY,
	)
	baseline += COMPARE_LINE_HEIGHT
	compare_text_draw(
		&canvas,
		text,
		compare_text_fit(text, fmt.aprintf(
			"B  %s  rev %s%s",
			report.scenario_b,
			report.revision_b,
			report.dirty_b ? " dirty" : "",
			allocator = context.temp_allocator,
		), width - COMPARE_MARGIN * 2),
		COMPARE_MARGIN,
		baseline,
		COMPARE_ACCENT,
	)
	baseline += COMPARE_LINE_HEIGHT
	compare_text_draw(
		&canvas,
		text,
		compare_text_fit(text, second.dir, width - COMPARE_MARGIN * 2),
		COMPARE_MARGIN,
		baseline,
		COMPARE_SECONDARY,
	)
	baseline += COMPARE_LINE_HEIGHT
	compare_text_draw(
		&canvas,
		text,
		fmt.aprintf(
			"pairs %d   page %d/%d",
			len(report.pairs),
			page + 1,
			total_pages,
			allocator = context.temp_allocator,
		),
		COMPARE_MARGIN,
		baseline,
		COMPARE_SECONDARY,
	)

	column_a := COMPARE_MARGIN
	column_b := COMPARE_MARGIN + COMPARE_COLUMN_WIDTH + COMPARE_GAP
	label_baseline := header_height - 6
	compare_text_draw(&canvas, text, "A", column_a, label_baseline, COMPARE_SECONDARY)
	compare_text_draw(&canvas, text, "B", column_b, label_baseline, COMPARE_SECONDARY)

	row_y := header_height
	for pair in pairs {
		compare_text_draw(
			&canvas,
			text,
			compare_text_fit(text, fmt.aprintf(
				"%s   %dx%d",
				pair.name,
				pair.width,
				pair.height,
				allocator = context.temp_allocator,
			), COMPARE_COLUMN_WIDTH * 2 + COMPARE_GAP),
			COMPARE_MARGIN,
			row_y + 16,
			COMPARE_TEXT,
		)
		image_y := row_y + COMPARE_ROW_LABEL_HEIGHT
		compare_draw_slot(&canvas, text, column_a, image_y, first, pair, true, allocator)
		compare_draw_slot(&canvas, text, column_b, image_y, second, pair, false, allocator)
		delta_baseline := image_y + COMPARE_COLUMN_HEIGHT + 16
		if pair.ok {
			value := "identical"
			if pair.different_pixels != 0 {
				value = fmt.aprintf(
					"different %d px   max %d   mean %.3f   >16 %d",
					pair.different_pixels,
					pair.max_delta,
					pair.mean_delta,
					pair.over_16,
					allocator = context.temp_allocator,
				)
			}
			compare_text_draw(&canvas, text, value, COMPARE_MARGIN, delta_baseline, COMPARE_SECONDARY)
		} else {
			compare_text_draw(
				&canvas,
				text,
				compare_text_fit(text, pair.error, width - COMPARE_MARGIN * 2),
				COMPARE_MARGIN,
				delta_baseline,
				COMPARE_ERROR,
			)
		}
		row_y += row_height
	}
	return canvas
}

@(private)
compare_draw_slot :: proc(
	canvas: ^Compare_Canvas,
	text: ^Compare_Text,
	x, y: int,
	run: Compare_Run,
	pair: Compare_Pair,
	is_first: bool,
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
	scale = min(scale, 1.0)
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
