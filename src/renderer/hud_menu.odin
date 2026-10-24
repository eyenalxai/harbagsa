#+vet explicit-allocators
package renderer

import "src:ui"

HUD_MENU_MAX_HINT_COLUMNS :: 8

Hint_Grid :: struct {
	width:        f32,
	height:       f32,
	columns:      int,
	rows:         int,
	column_x:     [HUD_MENU_MAX_HINT_COLUMNS]f32,
	key_width:    [HUD_MENU_MAX_HINT_COLUMNS]f32,
	row_height:   f32,
}

build_menu :: proc(o: ^Overlay, width, height: f32, menu: ui.Menu) {
	theme := o.theme
	padding := theme.spacing.xl
	gutter := theme.spacing.sm
	note_gap := theme.spacing.lg
	separator_gap := theme.spacing.sm

	row_options := Rows_Options{value_align = .Right}
	rows_layout := rows_measure(&o.atlas, theme, menu.rows, row_options)
	grid := hint_grid_measure(o, theme, menu)

	title_width := text_measure(&o.atlas, theme.type_title, menu.title)
	note_width := text_measure(&o.atlas, theme.type_caption, menu.note)
	content_width := max(rows_layout.width, grid.width)
	content_width = max(content_width, title_width)
	content_width = max(content_width, note_width)
	content_width = max(content_width, theme.menu_min_width)

	title_height := theme.type_title.line_height
	note_height := theme.type_caption.line_height
	panel_width := content_width + padding * 2
	panel_height := padding * 2 +
		title_height +
		separator_gap * 2 +
		theme.hairline +
		rows_layout.height +
		grid.height +
		note_gap +
		note_height
	panel_x := (width - panel_width) * 0.5
	// The smallest supported window is 800x600 and this panel is shorter than
	// that, but an offscreen target can be any size; keep the top on screen.
	panel_y := max((height - panel_height) * 0.5, theme.spacing.md)

	hud_emit_rect(o, 0, 0, width, height, theme.scrim)
	hud_emit_rect(o, panel_x, panel_y, panel_width, panel_height, theme.surface_menu)
	hud_emit_frame(o, panel_x, panel_y, panel_width, panel_height, theme.hairline, theme.line_hairline)

	title_baseline := panel_y + padding + text_baseline(&o.atlas, theme.type_title)
	text_emit_aligned(
		o,
		panel_x + panel_width * 0.5,
		title_baseline,
		{type = theme.type_title, color = theme.text_primary},
		menu.title,
		.Center,
	)

	inner_x := panel_x + padding
	inner_width := panel_width - padding * 2
	separator_y := panel_y + padding + title_height + separator_gap
	hud_emit_rect(o, inner_x, separator_y, inner_width, theme.hairline, theme.line_separator)

	// Values sit on the panel's inner right edge, so the settings read as one
	// label column and one value column no matter how wide the legend below is.
	rows_layout.value_width = max(
		rows_layout.value_width,
		content_width - gutter - rows_layout.label_column - theme.spacing.xl,
	)
	rows_layout.width = content_width

	rows_y := separator_y + theme.hairline + separator_gap
	row_options.frame_x = inner_x
	row_options.frame_width = inner_width
	row_options.selected = menu.selected
	rows_emit(o, theme, inner_x + gutter, rows_y, rows_layout, menu.rows, row_options)

	hint_grid_emit(o, theme, inner_x, rows_y + rows_layout.height, grid, menu)

	text_emit_aligned(
		o,
		panel_x + panel_width * 0.5,
		rows_y + rows_layout.height + grid.height + note_gap +
		text_baseline(&o.atlas, theme.type_caption),
		{type = theme.type_caption, color = theme.text_tertiary},
		menu.note,
		.Center,
	)
}

@(private)
hint_grid_measure :: proc(o: ^Overlay, theme: UI_Theme, menu: ui.Menu) -> Hint_Grid {
	grid: Hint_Grid
	grid.columns = clamp(menu.hint_columns, 1, HUD_MENU_MAX_HINT_COLUMNS)
	if len(menu.hints) == 0 {
		return grid
	}
	grid.rows = (len(menu.hints) + grid.columns - 1) / grid.columns
	grid.row_height = theme.type_caption.line_height + theme.spacing.xxs

	action_width: [HUD_MENU_MAX_HINT_COLUMNS]f32
	for cell, index in menu.hints {
		if cell.keys == "" {
			continue
		}
		column := index % grid.columns
		grid.key_width[column] = max(
			grid.key_width[column],
			text_measure(&o.atlas, theme.type_caption_caps, cell.keys),
		)
		action_width[column] = max(
			action_width[column],
			text_measure(&o.atlas, theme.type_caption, cell.action),
		)
	}

	offset: f32
	for column in 0 ..< grid.columns {
		grid.column_x[column] = offset
		offset += grid.key_width[column] + theme.spacing.xs + action_width[column]
		if column < grid.columns - 1 {
			offset += theme.spacing.xl
		}
	}
	grid.width = offset
	grid.height = f32(grid.rows) * grid.row_height
	return grid
}

@(private)
hint_grid_emit :: proc(
	o: ^Overlay,
	theme: UI_Theme,
	x, y: f32,
	grid: Hint_Grid,
	menu: ui.Menu,
) {
	keys_style := Text_Style{type = theme.type_caption_caps, color = theme.text_secondary}
	action_style := Text_Style{type = theme.type_caption, color = theme.text_tertiary}
	baseline := text_baseline(&o.atlas, theme.type_caption_caps)

	for cell, index in menu.hints {
		if cell.keys == "" {
			continue
		}
		column := index % grid.columns
		row := index / grid.columns
		cell_x := x + grid.column_x[column]
		cell_y := y + f32(row) * grid.row_height
		// Keys sit against their action, so a one-letter key does not float in a
		// column sized by the longest shortcut.
		text_emit_aligned(
			o,
			cell_x + grid.key_width[column],
			cell_y + baseline,
			keys_style,
			cell.keys,
			.Right,
		)
		text_emit(
			o,
			cell_x + grid.key_width[column] + theme.spacing.xs,
			cell_y + baseline,
			action_style,
			cell.action,
		)
	}
}
