#+vet explicit-allocators
#+vet !unused-procedures // the renderer and frame tests call this API; the game binary does not
package ui

MENU_WEIGHT_HEADROOM :: f32(1.05)

Menu_Layout :: struct {
	panel:         Rect,
	inner:         Rect,
	separator_y:   f32,
	rows_y:        f32,
	rows:          Rows_Layout,
	grid:          Hint_Grid,
	note_baseline: f32,
	slider:        Slider_Rect,
}

menu_layout :: proc(inputs: Layout_Inputs, menu: Menu) -> Menu_Layout {
	padding := inputs.spacing.xl
	gutter := inputs.spacing.sm
	note_gap := inputs.spacing.lg
	separator_gap := inputs.spacing.sm

	layout: Menu_Layout
	layout.rows = rows_layout(inputs, menu.rows, {value_align = .Right})
	layout.grid = hint_grid(inputs, menu)

	title_width := inputs.metrics.measure(inputs.metrics.ctx, .Title, menu.title)
	note_width := inputs.metrics.measure(inputs.metrics.ctx, .Caption, menu.note)
	content_width := max(layout.rows.width, layout.grid.width)
	content_width = max(content_width, title_width)
	content_width = max(content_width, note_width)
	content_width = max(content_width, inputs.menu_min_width)
	content_width *= MENU_WEIGHT_HEADROOM

	title_height := inputs.metrics.line_height(inputs.metrics.ctx, .Title)
	note_height := inputs.metrics.line_height(inputs.metrics.ctx, .Caption)
	panel_width := content_width + padding * 2
	panel_height := padding * 2 +
		title_height +
		separator_gap * 2 +
		inputs.hairline +
		layout.rows.height +
		layout.grid.height +
		note_gap +
		note_height
	panel_x := (inputs.width - panel_width) * 0.5
	// The smallest supported window is 800x600 and this panel is shorter than
	// that, but an offscreen target can be any size; keep the top on screen.
	panel_y := max((inputs.height - panel_height) * 0.5, inputs.spacing.md)

	layout.panel = {panel_x, panel_y, panel_width, panel_height}
	layout.inner = {
		panel_x + padding,
		panel_y + padding,
		panel_width - padding * 2,
		panel_height - padding * 2,
	}
	layout.separator_y = panel_y + padding + title_height + separator_gap
	layout.rows_y = layout.separator_y + inputs.hairline + separator_gap

	// Values sit on the panel's inner right edge, so the settings read as one
	// label column and one value column no matter how wide the legend below is.
	layout.rows.value_width = max(
		layout.rows.value_width,
		content_width - gutter - layout.rows.label_column - inputs.spacing.xl,
	)
	layout.rows.width = content_width
	layout.note_baseline = layout.rows_y +
		layout.rows.height +
		layout.grid.height +
		note_gap +
		inputs.metrics.baseline(inputs.metrics.ctx, .Caption)
	layout.slider = menu_slider_in(inputs, layout, menu.rows)
	return layout
}

menu_slider_in :: proc(
	inputs: Layout_Inputs,
	layout: Menu_Layout,
	rows: []Row,
) -> Slider_Rect {
	for row, index in rows {
		if row.kind == .Slider {
			row_y := layout.rows_y + rows_row_y(inputs, rows, index)
			return slider_rect(inputs, layout.inner.x, layout.inner.width, row_y)
		}
	}
	return {}
}
