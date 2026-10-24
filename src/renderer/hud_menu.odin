#+vet explicit-allocators
package renderer

import "src:ui"

HUD_MENU_MAX_HINT_COLUMNS :: 8
HINT_COLUMNS :: 3

Hint_Grid :: struct {
	width:        f32,
	height:       f32,
	columns:      int,
	rows:         int,
	column_x:     [HUD_MENU_MAX_HINT_COLUMNS]f32,
	key_width:    [HUD_MENU_MAX_HINT_COLUMNS]f32,
	row_height:   f32,
}

MENU_WEIGHT_HEADROOM :: f32(1.05)

Menu_Layout :: struct {
	panel_x:      f32,
	panel_y:      f32,
	panel_width:  f32,
	panel_height: f32,
	inner_x:      f32,
	inner_width:  f32,
	separator_y:  f32,
	rows_y:       f32,
	rows_layout:  Rows_Layout,
	grid:         Hint_Grid,
	frozen_width: f32,
}

menu_layout :: proc(o: ^Overlay, width, height: f32, menu: ui.Menu) -> Menu_Layout {
	theme := o.theme
	padding := theme.spacing.xl
	gutter := theme.spacing.sm
	note_gap := theme.spacing.lg
	separator_gap := theme.spacing.sm

	layout: Menu_Layout
	layout.rows_layout = rows_measure(&o.atlas, theme, menu.rows, {value_align = .Right})
	layout.grid = hint_grid_measure(o, theme, menu)

	title_width := text_measure(&o.atlas, theme.type_title, menu.title)
	note_width := text_measure(&o.atlas, theme.type_caption, menu.note)
	content_width := max(layout.rows_layout.width, layout.grid.width)
	content_width = max(content_width, title_width)
	content_width = max(content_width, note_width)
	content_width = max(content_width, theme.menu_min_width)
	layout.frozen_width = o.menu_frozen_width
	if layout.frozen_width == 0 {
		layout.frozen_width = content_width * MENU_WEIGHT_HEADROOM
	}
	content_width = max(content_width, layout.frozen_width)

	title_height := theme.type_title.line_height
	note_height := theme.type_caption.line_height
	layout.panel_width = content_width + padding * 2
	layout.panel_height = padding * 2 +
		title_height +
		separator_gap * 2 +
		theme.hairline +
		layout.rows_layout.height +
		layout.grid.height +
		note_gap +
		note_height
	layout.panel_x = (width - layout.panel_width) * 0.5
	// The smallest supported window is 800x600 and this panel is shorter than
	// that, but an offscreen target can be any size; keep the top on screen.
	layout.panel_y = max((height - layout.panel_height) * 0.5, theme.spacing.md)
	layout.inner_x = layout.panel_x + padding
	layout.inner_width = layout.panel_width - padding * 2
	layout.separator_y = layout.panel_y + padding + title_height + separator_gap
	layout.rows_y = layout.separator_y + theme.hairline + separator_gap

	// Values sit on the panel's inner right edge, so the settings read as one
	// label column and one value column no matter how wide the legend below is.
	layout.rows_layout.value_width = max(
		layout.rows_layout.value_width,
		content_width - gutter - layout.rows_layout.label_column - theme.spacing.xl,
	)
	layout.rows_layout.width = content_width
	return layout
}

build_menu :: proc(o: ^Overlay, width, height: f32, menu: ui.Menu) {
	theme := o.theme
	padding := theme.spacing.xl
	gutter := theme.spacing.sm
	note_gap := theme.spacing.lg

	layout := menu_layout(o, width, height, menu)
	o.menu_frozen_width = layout.frozen_width
	o.menu_slider = menu_slider_in(theme, layout, menu.rows)

	hud_emit_rect(o, 0, 0, width, height, theme.scrim)
	hud_emit_rect(
		o,
		layout.panel_x,
		layout.panel_y,
		layout.panel_width,
		layout.panel_height,
		theme.surface_menu,
	)
	hud_emit_frame(
		o,
		layout.panel_x,
		layout.panel_y,
		layout.panel_width,
		layout.panel_height,
		theme.hairline,
		theme.line_hairline,
	)

	title_baseline := layout.panel_y + padding + text_baseline(&o.atlas, theme.type_title)
	text_emit_aligned(
		o,
		layout.panel_x + layout.panel_width * 0.5,
		title_baseline,
		{type = theme.type_title, color = theme.text_primary},
		menu.title,
		.Center,
	)

	hud_emit_rect(
		o,
		layout.inner_x,
		layout.separator_y,
		layout.inner_width,
		theme.hairline,
		theme.line_separator,
	)

	row_options := Rows_Options {
		value_align = .Right,
		frame_x     = layout.inner_x,
		frame_width = layout.inner_width,
		selected    = menu.selected,
	}
	rows_emit(
		o,
		theme,
		layout.inner_x + gutter,
		layout.rows_y,
		layout.rows_layout,
		menu.rows,
		row_options,
	)

	hint_grid_emit(
		o,
		theme,
		layout.inner_x,
		layout.rows_y + layout.rows_layout.height,
		layout.grid,
		menu,
	)

	text_emit_aligned(
		o,
		layout.panel_x + layout.panel_width * 0.5,
		layout.rows_y + layout.rows_layout.height + layout.grid.height + note_gap +
		text_baseline(&o.atlas, theme.type_caption),
		{type = theme.type_caption, color = theme.text_tertiary},
		menu.note,
		.Center,
	)
}

@(private)
hint_grid_measure :: proc(o: ^Overlay, theme: UI_Theme, menu: ui.Menu) -> Hint_Grid {
	grid: Hint_Grid
	columns := menu.hint_columns
	if columns <= 0 {
		columns = HINT_COLUMNS
	}
	grid.columns = clamp(columns, 1, HUD_MENU_MAX_HINT_COLUMNS)
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
