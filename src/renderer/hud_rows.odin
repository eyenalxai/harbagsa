#+vet explicit-allocators
package renderer

import "src:ui"

// frame_x and frame_width are the panel's inner rectangle. The selection band
// and every divider use it, so both share one edge; a zero width means the
// caller has no panel and the row block is its own frame.
row_label_style :: proc(theme: UI_Theme, kind: ui.Row_Kind) -> Text_Style {
	role := ui.row_label_role(kind)
	color := theme.text_secondary
	if kind == .Detail || kind == .Header {
		color = theme.text_tertiary
	}
	return text_style_for_role(theme, role, color)
}

row_value_style :: proc(theme: UI_Theme, row: ui.Row) -> Text_Style {
	role := ui.row_value_role(row)
	color := theme.text_primary
	if row.kind == .Detail {
		color = theme.text_tertiary
	}
	if row.blocked {
		color = theme.text_secondary
	}
	return text_style_for_role(theme, role, color)
}

rows_emit :: proc(
	o: ^Overlay,
	theme: UI_Theme,
	x, y: f32,
	inputs: ui.Layout_Inputs,
	layout: ui.Rows_Layout,
	rows: []ui.Row,
	options: ui.Rows_Options,
) {
	for row, index in rows {
		rows_emit_row(
			o,
			theme,
			x,
			y + ui.rows_row_y(inputs, rows, index),
			inputs,
			layout,
			row,
			index,
			options,
		)
	}
}

@(private)
rows_emit_row :: proc(
	o: ^Overlay,
	theme: UI_Theme,
	x, y: f32,
	inputs: ui.Layout_Inputs,
	layout: ui.Rows_Layout,
	row: ui.Row,
	index: int,
	options: ui.Rows_Options,
) {
	atlas := &o.atlas
	row_style := row_label_style(theme, row.kind)
	selectable := row.kind == .Setting || row.kind == .Action || row.kind == .Slider
	selected := options.frame_width > 0 && index == options.selected && selectable
	if selected {
		row_style.color = theme.text_primary
	}
	baseline := y + text_baseline(atlas, row_style.type)

	switch row.kind {
	case .Divider:
		frame_x, frame_width := rows_frame(x, layout, options)
		hud_emit_rect(o, frame_x, y, frame_width, theme.hairline, theme.line_separator)
		return
	case .Header:
		text_emit(o, x, baseline, row_style, row.label)
		return
	case .Setting, .Action, .Metric, .Detail, .Slider:
	}

	if selected {
		band_pad := theme.spacing.xxs
		band_height := ui.row_height(inputs, row.kind) + band_pad * 2
		hud_emit_rect(
			o,
			options.frame_x,
			y - band_pad,
			options.frame_width,
			band_height,
			theme.surface_raised,
		)
		hud_emit_rect(
			o,
			options.frame_x,
			y - band_pad,
			max(theme.hairline * 2, 2),
			band_height,
			theme.accent,
		)
	}

	text_emit(o, x, baseline, row_style, row.label)

	value_style := row_value_style(theme, row)
	switch options.value_align {
	case .Left:
		text_emit(o, x + layout.value_column, baseline, value_style, row.value)
	case .Right:
		text_emit_aligned(
			o,
			x + layout.value_column + layout.value_width,
			baseline,
			value_style,
			row.value,
			.Right,
		)
	}
	if row.kind == .Slider {
		rows_emit_slider(o, theme, inputs, y, row, options)
	}
}

@(private)
rows_frame :: proc(x: f32, layout: ui.Rows_Layout, options: ui.Rows_Options) -> (frame_x, frame_width: f32) {
	if options.frame_width > 0 {
		return options.frame_x, options.frame_width
	}
	return x, layout.width
}
