#+vet explicit-allocators
#+vet !unused-procedures // @(test) procs are called by the test runner, not by name
package frame_test

import "core:testing"

import "src:ui"

fake_measure :: proc(ctx: rawptr, role: ui.Text_Role, text: string) -> f32 {
	return f32(len(text)) * 8.0
}

fake_line_height :: proc(ctx: rawptr, role: ui.Text_Role) -> f32 {
	return 20.0
}

fake_baseline :: proc(ctx: rawptr, role: ui.Text_Role) -> f32 {
	return 15.0
}

fake_inputs :: proc() -> ui.Layout_Inputs {
	return {
		width = 1280,
		height = 720,
		spacing = {xxs = 2, xs = 4, sm = 6, md = 8, lg = 12, xl = 16, xxl = 24},
		hairline = 1,
		density = 1,
		menu_min_width = 200,
		metrics = {
			measure = fake_measure,
			line_height = fake_line_height,
			baseline = fake_baseline,
		},
	}
}

@(test)
layout_runs_without_a_renderer_or_an_atlas :: proc(t: ^testing.T) {
	rows := []ui.Row {
		{kind = .Setting, label = "Window mode", value = "Borderless"},
		{kind = .Slider, label = "Type weight", value = "400", numeric = true, ratio = 0.5, ticks = 9},
	}
	menu := ui.Menu {
		title = "Settings",
		rows = rows,
		selected = 1,
		hints = []ui.Hint_Cell{{keys = "Esc", action = "close"}},
		hint_columns = 3,
		note = "Up/Down select",
	}
	layout := ui.menu_layout(fake_inputs(), menu)
	testing.expect(t, layout.panel.width > 0, "the menu has no panel")
	testing.expect(t, layout.slider.width > 0, "the menu has no slider")
	testing.expect(
		t,
		layout.slider.y >= layout.panel.y &&
		layout.slider.y + layout.slider.height <= layout.panel.y + layout.panel.height,
		"the slider leaves the panel",
	)
	testing.expect(t, layout.rows.height > 0, "the rows have no height")

	palette := ui.palette_layout(fake_inputs(), 11)
	testing.expect_value(t, palette.card_count, 11)
	testing.expect(t, palette.panel.width > 0, "the palette has no panel")
	testing.expect(t, palette.preview.width > 0, "the palette has no preview")
}

@(test)
pointer_maps_to_target_pixels_once :: proc(t: ^testing.T) {
	testing.expect_value(t, ui.pointer_to_target({0.5, 0.5}, 1280, 720), [2]f32{640, 360})
	testing.expect_value(t, ui.pointer_to_target({0, 1}, 800, 600), [2]f32{0, 600})
	testing.expect_value(t, ui.pointer_to_target({1, 0}, 2560, 1440), [2]f32{2560, 0})
}
