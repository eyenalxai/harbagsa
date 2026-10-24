#+vet explicit-allocators
package renderer

import "src:ui"

// frame_x and frame_width are the panel's inner rectangle. The selection band
// and every divider use it, so both share one edge; a zero width means the
// caller has no panel and the row block is its own frame.
Rows_Options :: struct {
	value_align: Text_Align,
	frame_x:     f32,
	frame_width: f32,
	selected:    int,
}

Rows_Layout :: struct {
	width:        f32,
	height:       f32,
	label_column: f32,
	value_column: f32,
	value_width:  f32,
}

row_label_style :: proc(theme: UI_Theme, kind: ui.Row_Kind) -> Text_Style {
	switch kind {
	case .Setting, .Action, .Slider:
		return {type = theme.type_body_strong, color = theme.text_secondary}
	case .Metric:
		return {type = theme.type_body, color = theme.text_secondary}
	case .Detail:
		return {type = theme.type_caption, color = theme.text_tertiary}
	case .Header:
		return {type = theme.type_caption_caps, color = theme.text_tertiary}
	case .Divider, .Spacer:
	}
	return {type = theme.type_body, color = theme.text_secondary}
}

row_value_style :: proc(theme: UI_Theme, row: ui.Row) -> Text_Style {
	style := theme.type_body
	color := theme.text_primary
	switch row.kind {
	case .Detail:
		style = theme.type_caption
		color = theme.text_tertiary
	case .Setting, .Action, .Metric, .Slider:
	case .Divider, .Spacer, .Header:
		return {type = theme.type_body, color = color}
	}
	if row.numeric {
		style.face = .Mono
		style.weight = min(style.weight, MONO_MAX_WEIGHT)
	}
	return {type = style, color = color}
}

row_gap :: proc(theme: UI_Theme, kind: ui.Row_Kind) -> f32 {
	switch kind {
	case .Header:
		return theme.spacing.lg
	case .Divider:
		return theme.spacing.sm
	case .Spacer:
		return 0
	case .Setting, .Action, .Slider:
		return theme.spacing.sm
	case .Metric, .Detail:
	}
	return theme.spacing.xs
}

row_height :: proc(theme: UI_Theme, kind: ui.Row_Kind) -> f32 {
	switch kind {
	case .Header, .Detail:
		return theme.type_caption.line_height
	case .Divider:
		return theme.hairline
	case .Spacer:
		return theme.spacing.sm
	case .Slider:
		return theme.type_body.line_height + theme.spacing.sm + theme.spacing.lg
	case .Setting, .Action, .Metric:
	}
	return theme.type_body.line_height
}

rows_measure :: proc(atlas: ^Text_Atlas, theme: UI_Theme, rows: []ui.Row, options: Rows_Options) -> Rows_Layout {
	layout: Rows_Layout
	for row, index in rows {
		if index > 0 {
			layout.height += row_gap(theme, row.kind)
		}
		layout.height += row_height(theme, row.kind)
		if row.label != "" {
			layout.label_column = max(
				layout.label_column,
				text_measure(atlas, row_label_style(theme, row.kind).type, row.label),
			)
		}
		if row.value != "" {
			layout.value_width = max(
				layout.value_width,
				text_measure(atlas, row_value_style(theme, row).type, row.value),
			)
		}
	}
	layout.value_column = layout.label_column + theme.spacing.xl
	layout.width = layout.value_column + layout.value_width
	return layout
}

rows_emit :: proc(
	o: ^Overlay,
	theme: UI_Theme,
	x, y: f32,
	layout: Rows_Layout,
	rows: []ui.Row,
	options: Rows_Options,
) {
	row_y := y
	for row, index in rows {
		if index > 0 {
			row_y += row_gap(theme, row.kind)
		}
		rows_emit_row(o, theme, x, row_y, layout, row, index, options)
		row_y += row_height(theme, row.kind)
	}
}

@(private)
rows_emit_row :: proc(
	o: ^Overlay,
	theme: UI_Theme,
	x, y: f32,
	layout: Rows_Layout,
	row: ui.Row,
	index: int,
	options: Rows_Options,
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
	case .Spacer:
		return
	case .Header:
		text_emit(o, x, baseline, row_style, row.label)
		return
	case .Setting, .Action, .Metric, .Detail, .Slider:
	}

	if selected {
		band_pad := theme.spacing.xxs
		band_height := row_height(theme, row.kind) + band_pad * 2
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
	case .Center:
		text_emit_aligned(
			o,
			x + layout.value_column + layout.value_width * 0.5,
			baseline,
			value_style,
			row.value,
			.Center,
		)
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
		rows_emit_slider(o, theme, y, row, options)
	}
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
	knob := theme.spacing.md
	track_x := options.frame_x
	track_width := options.frame_width
	travel := max(track_width - knob, 0)
	center_y := y + theme.type_body.line_height + theme.spacing.sm + theme.spacing.lg * 0.5
	thickness := max(theme.hairline * 2, 2)
	track_y := hud_snap(center_y - thickness * 0.5)
	ratio := clamp(row.ratio, 0, 1)
	knob_center := track_x + knob * 0.5 + ratio * travel

	hud_emit_rect(o, track_x, track_y, track_width, thickness, theme.line_separator)
	hud_emit_rect(o, track_x, track_y, max(knob_center - track_x, 0), thickness, theme.text_secondary)
	if row.ticks >= 2 {
		pitch := travel / f32(row.ticks - 1)
		tick_y := hud_snap(center_y - theme.spacing.sm * 0.5)
		for tick in 0 ..< row.ticks {
			tick_center := track_x + knob * 0.5 + f32(tick) * pitch
			tick_x := hud_snap(tick_center - theme.hairline * 0.5)
			hud_emit_rect(o, tick_x, tick_y, theme.hairline, theme.spacing.sm, theme.text_tertiary)
		}
	}
	hud_emit_rect(
		o,
		hud_snap(knob_center - knob * 0.5),
		hud_snap(center_y - knob * 0.5),
		knob,
		knob,
		theme.text_primary,
	)
	o.menu_slider = {
		x      = track_x + knob * 0.5,
		y      = hud_snap(center_y - theme.spacing.lg * 0.5),
		width  = travel,
		height = theme.spacing.lg,
	}
}

@(private)
rows_frame :: proc(x: f32, layout: Rows_Layout, options: Rows_Options) -> (frame_x, frame_width: f32) {
	if options.frame_width > 0 {
		return options.frame_x, options.frame_width
	}
	return x, layout.width
}
