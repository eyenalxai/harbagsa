#+vet explicit-allocators
package renderer

import "src:ui"

// The published rect and the drawn track both come from here, so the pointer
// cannot aim at a track the draw does not use.
@(private)
slider_center_y :: proc(theme: UI_Theme, row_y: f32) -> f32 {
	return row_y + theme.type_body.line_height + theme.spacing.sm + theme.spacing.lg * 0.5
}

@(private)
slider_rect :: proc(theme: UI_Theme, frame_x, frame_width, row_y: f32) -> ui.Slider_Rect {
	center_y := slider_center_y(theme, row_y)
	return {
		x      = frame_x,
		y      = hud_snap(center_y - theme.spacing.lg * 0.5),
		width  = frame_width,
		height = theme.spacing.lg,
		knob   = theme.spacing.md,
	}
}

@(private)
menu_slider_in :: proc(theme: UI_Theme, layout: Menu_Layout, rows: []ui.Row) -> ui.Slider_Rect {
	for row, index in rows {
		if row.kind == .Slider {
			row_y := layout.rows_y + rows_row_y(theme, rows, index)
			return slider_rect(theme, layout.inner_x, layout.inner_width, row_y)
		}
	}
	return {}
}

// The pointer needs the track on the opening frame, before the draw publishes
// one, so this measures the same menu layout without emitting vertices.
menu_slider_rect :: proc(r: ^Renderer, menu: ui.Menu) -> ui.Slider_Rect {
	width, height := target_extent(r)
	layout := menu_layout(&r.overlay, f32(width), f32(height), menu)
	return menu_slider_in(r.overlay.theme, layout, menu.rows)
}

@(private)
rows_emit_slider :: proc(
	o: ^Overlay,
	theme: UI_Theme,
	y: f32,
	row: ui.Row,
	options: Rows_Options,
) {
	if options.frame_width <= 0 {
		return
	}
	rect := slider_rect(theme, options.frame_x, options.frame_width, y)
	travel := max(rect.width - rect.knob, 0)
	center_y := slider_center_y(theme, y)
	thickness := max(theme.hairline * 2, 2)
	track_y := hud_snap(center_y - thickness * 0.5)
	ratio := clamp(row.ratio, 0, 1)
	knob_center := rect.x + rect.knob * 0.5 + ratio * travel

	hud_emit_rect(o, rect.x, track_y, rect.width, thickness, theme.slider_track)
	hud_emit_rect(o, rect.x, track_y, max(knob_center - rect.x, 0), thickness, theme.text_secondary)
	if row.ticks >= 2 {
		pitch := travel / f32(row.ticks - 1)
		tick_y := hud_snap(center_y - theme.spacing.sm * 0.5)
		for tick in 0 ..< row.ticks {
			tick_center := rect.x + rect.knob * 0.5 + f32(tick) * pitch
			tick_x := hud_snap(tick_center - theme.hairline * 0.5)
			hud_emit_rect(o, tick_x, tick_y, theme.hairline, theme.spacing.sm, theme.text_tertiary)
		}
	}
	hud_emit_rect(
		o,
		hud_snap(knob_center - rect.knob * 0.5),
		hud_snap(center_y - rect.knob * 0.5),
		rect.knob,
		rect.knob,
		theme.text_primary,
	)
}
