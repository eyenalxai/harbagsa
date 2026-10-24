#+vet explicit-allocators
package renderer

HUD_MENU_MIN_WIDTH :: 200.0

build_menu :: proc(o: ^Overlay, width, height: f32, menu: HUD_Menu) {
	theme := o.theme
	title_style := Text_Style{type = theme.type_title, color = theme.text_primary}
	row_style := Text_Style{type = theme.type_body, color = theme.text_secondary}
	row_selected_style := Text_Style{type = theme.type_body, color = theme.text_primary}
	note_style := Text_Style{type = theme.type_caption, color = theme.text_tertiary}

	padding := theme.spacing.lg
	row_gap := theme.spacing.xs
	row_height := theme.type_body.line_height + row_gap
	text_inset := theme.spacing.sm
	title_height := theme.type_title.line_height
	note_height := theme.type_caption.line_height
	border := theme.hairline
	separator_gap := theme.spacing.sm
	note_gap := theme.spacing.md

	content_width := text_measure(&o.atlas, theme.type_title, menu.title)
	for line in menu.lines {
		line_width := text_measure(&o.atlas, theme.type_body, line) + text_inset * 2
		content_width = max(content_width, line_width)
	}
	content_width = max(content_width, text_measure(&o.atlas, theme.type_caption, menu.note))
	content_width = max(content_width, HUD_MENU_MIN_WIDTH * theme.density)

	panel_width := content_width + padding * 2
	lines_height := f32(len(menu.lines)) * row_height
	head_height := title_height + separator_gap * 2 + border
	panel_height := padding * 2 + head_height + lines_height + note_gap + note_height
	panel_x := (width - panel_width) * 0.5
	panel_y := (height - panel_height) * 0.5

	hud_emit_rect(o, 0, 0, width, height, theme.scrim)
	hud_emit_rect(o, panel_x, panel_y, panel_width, panel_height, theme.surface_menu)

	// The panel is translucent, so the ring is drawn as four edges instead of a
	// filled outline.
	hud_emit_rect(o, panel_x, panel_y, panel_width, border, theme.line_hairline)
	hud_emit_rect(
		o,
		panel_x,
		panel_y + panel_height - border,
		panel_width,
		border,
		theme.line_hairline,
	)
	hud_emit_rect(o, panel_x, panel_y, border, panel_height, theme.line_hairline)
	hud_emit_rect(
		o,
		panel_x + panel_width - border,
		panel_y,
		border,
		panel_height,
		theme.line_hairline,
	)

	title_y := panel_y + padding
	text_emit_aligned(
		o,
		panel_x + panel_width * 0.5,
		title_y + text_baseline(&o.atlas, theme.type_title),
		title_style,
		menu.title,
		.Center,
	)

	inner_x := panel_x + padding
	inner_width := panel_width - padding * 2
	separator_y := title_y + title_height + separator_gap
	hud_emit_rect(o, inner_x, separator_y, inner_width, border, theme.line_separator)

	rows_y := separator_y + border + separator_gap
	selected_valid := menu.selected >= 0 && menu.selected < len(menu.lines)
	baseline_offset := text_baseline(&o.atlas, theme.type_body)
	for line, index in menu.lines {
		row_y := rows_y + f32(index) * row_height
		selected := selected_valid && index == menu.selected
		color_style := row_style
		if selected {
			hud_emit_rect(o, inner_x, row_y, inner_width, row_height, theme.surface_raised)
			hud_emit_rect(o, inner_x, row_y, theme.hairline * 2, row_height, theme.accent)
			color_style = row_selected_style
		}
		text_emit(
			o,
			inner_x + text_inset,
			row_y + row_gap * 0.5 + baseline_offset,
			color_style,
			line,
		)
	}

	text_emit_aligned(
		o,
		panel_x + panel_width * 0.5,
		rows_y + lines_height + note_gap + text_baseline(&o.atlas, theme.type_caption),
		note_style,
		menu.note,
		.Center,
	)
}
