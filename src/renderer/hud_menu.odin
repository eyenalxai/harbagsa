#+vet explicit-allocators
package renderer

import "src:ui"

build_menu :: proc(o: ^Overlay, width, height: f32, menu: ui.Menu) {
	theme := o.theme
	ctx: Layout_Context
	layout_context_init(&ctx, theme, &o.atlas, width, height)
	layout := ui.menu_layout(ctx.inputs, menu)

	hud_emit_rect(o, 0, 0, width, height, theme.scrim)
	hud_emit_rect(
		o,
		layout.panel.x,
		layout.panel.y,
		layout.panel.width,
		layout.panel.height,
		theme.surface_menu,
	)
	hud_emit_frame(
		o,
		layout.panel.x,
		layout.panel.y,
		layout.panel.width,
		layout.panel.height,
		theme.hairline,
		theme.line_hairline,
	)

	title_baseline := layout.inner.y + text_baseline(&o.atlas, theme.type_title)
	text_emit_aligned(
		o,
		layout.panel.x + layout.panel.width * 0.5,
		title_baseline,
		{type = theme.type_title, color = theme.text_primary},
		menu.title,
		.Center,
	)

	hud_emit_rect(
		o,
		layout.inner.x,
		layout.separator_y,
		layout.inner.width,
		theme.hairline,
		theme.line_separator,
	)

	row_options := ui.Rows_Options {
		value_align = .Right,
		frame_x     = layout.inner.x,
		frame_width = layout.inner.width,
		selected    = menu.selected,
	}
	rows_emit(
		o,
		theme,
		layout.inner.x + theme.spacing.sm,
		layout.rows_y,
		ctx.inputs,
		layout.rows,
		menu.rows,
		row_options,
	)

	hint_grid_emit(
		o,
		theme,
		layout.inner.x,
		layout.rows_y + layout.rows.height,
		layout.grid,
		menu,
	)

	text_emit_aligned(
		o,
		layout.panel.x + layout.panel.width * 0.5,
		layout.note_baseline,
		{type = theme.type_caption, color = theme.text_tertiary},
		menu.note,
		.Center,
	)
}

@(private)
hint_grid_emit :: proc(
	o: ^Overlay,
	theme: UI_Theme,
	x, y: f32,
	grid: ui.Hint_Grid,
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
