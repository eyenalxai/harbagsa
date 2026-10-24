#+vet explicit-allocators
package renderer

import "src:ui"

Rows_Options :: struct {
	value_width: f32,
	value_align: Text_Align,
	band_x:      f32,
	band_width:  f32,
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
	case .Setting, .Action:
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
	case .Setting, .Action, .Metric:
	case .Divider, .Spacer, .Header:
		return {type = theme.type_body, color = color}
	}
	if row.numeric {
		style.weight = .Mono
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
	case .Setting, .Action:
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
	layout.value_width = max(layout.value_width, options.value_width)
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
	selectable := row.kind == .Setting || row.kind == .Action
	selected := options.band_width > 0 && index == options.selected && selectable
	if selected {
		row_style.color = theme.text_primary
	}
	baseline := y + text_baseline(atlas, row_style.type)

	switch row.kind {
	case .Divider:
		hud_emit_rect(o, x, y, max(layout.width, options.band_width), theme.hairline, theme.line_separator)
		return
	case .Spacer:
		return
	case .Header:
		text_emit(o, x, baseline, row_style, row.label)
		return
	case .Setting, .Action, .Metric, .Detail:
	}

	if selected {
		band_pad := theme.spacing.xxs
		band_height := row_height(theme, row.kind) + band_pad * 2
		hud_emit_rect(
			o,
			options.band_x,
			y - band_pad,
			options.band_width,
			band_height,
			theme.surface_raised,
		)
		hud_emit_rect(
			o,
			options.band_x,
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
}
