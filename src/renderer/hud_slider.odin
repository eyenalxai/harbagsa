#+vet explicit-allocators
package renderer

import "src:ui"

@(private)
rows_emit_slider :: proc(
	o: ^Overlay,
	theme: UI_Theme,
	inputs: ui.Layout_Inputs,
	y: f32,
	row: ui.Row,
	options: ui.Rows_Options,
) {
	if options.frame_width <= 0 {
		return
	}
	rect := ui.slider_rect(inputs, options.frame_x, options.frame_width, y)
	travel := max(rect.width - rect.knob, 0)
	center_y := ui.slider_center_y(inputs, y)
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
