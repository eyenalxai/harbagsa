#+vet explicit-allocators
package renderer

import stb_easy_font "vendor:stb/easy_font"

HUD_MENU_DIM_COLOR :: [4]f32{0.0, 0.0, 0.0, 0.6}
HUD_MENU_PANEL_COLOR :: [4]f32{0.02, 0.025, 0.035, 0.96}
HUD_MENU_BORDER_COLOR :: [4]f32{0.55, 0.65, 0.75, 0.22}
HUD_MENU_SEPARATOR_COLOR :: [4]f32{0.75, 0.82, 0.9, 0.18}
HUD_MENU_HIGHLIGHT_COLOR :: [4]f32{0.28, 0.45, 0.6, 0.45}
HUD_MENU_TITLE_COLOR :: [4]f32{1.0, 1.0, 1.0, 1.0}
HUD_MENU_TEXT_COLOR :: [4]f32{0.8, 0.85, 0.9, 1.0}
HUD_MENU_SELECTED_COLOR :: [4]f32{1.0, 1.0, 1.0, 1.0}
HUD_MENU_NOTE_COLOR :: [4]f32{0.6, 0.66, 0.72, 0.9}

HUD_MENU_MIN_WIDTH :: 200.0

build_menu :: proc(o: ^Overlay, width, height: f32, menu: HUD_Menu, scale: f32) {
	title_scale := scale * 1.6
	note_scale := scale * 0.85
	padding := 12.0 * scale
	row_gap := 3.0 * scale
	row_height := HUD_LINE_HEIGHT * scale + row_gap
	text_inset := 6.0 * scale
	title_height := HUD_LINE_HEIGHT * title_scale
	note_height := HUD_LINE_HEIGHT * note_scale
	border := max(1.0, scale * 0.5)
	separator_thickness := border
	separator_gap := 6.0 * scale
	note_gap := 10.0 * scale

	content_width := f32(stb_easy_font.width(menu.title)) * title_scale
	for line in menu.lines {
		line_width := f32(stb_easy_font.width(line)) * scale + text_inset * 2
		content_width = max(content_width, line_width)
	}
	content_width = max(content_width, f32(stb_easy_font.width(menu.note)) * note_scale)
	content_width = max(content_width, HUD_MENU_MIN_WIDTH * scale)

	panel_width := content_width + padding * 2
	lines_height := f32(len(menu.lines)) * row_height
	head_height := title_height + separator_gap * 2 + separator_thickness
	panel_height := padding * 2 + head_height + lines_height + note_gap + note_height
	panel_x := (width - panel_width) * 0.5
	panel_y := (height - panel_height) * 0.5

	hud_emit_rect(o, 0, 0, width, height, HUD_MENU_DIM_COLOR)
	hud_emit_rect(o, panel_x, panel_y, panel_width, panel_height, HUD_MENU_PANEL_COLOR)

	// The panel is translucent, so the border is drawn as four edges instead of a filled outline.
	hud_emit_rect(o, panel_x, panel_y, panel_width, border, HUD_MENU_BORDER_COLOR)
	hud_emit_rect(
		o,
		panel_x,
		panel_y + panel_height - border,
		panel_width,
		border,
		HUD_MENU_BORDER_COLOR,
	)
	hud_emit_rect(o, panel_x, panel_y, border, panel_height, HUD_MENU_BORDER_COLOR)
	hud_emit_rect(
		o,
		panel_x + panel_width - border,
		panel_y,
		border,
		panel_height,
		HUD_MENU_BORDER_COLOR,
	)

	title_width := f32(stb_easy_font.width(menu.title)) * title_scale
	title_x := panel_x + (panel_width - title_width) * 0.5
	title_y := panel_y + padding
	hud_emit_text(o, title_x, title_y, menu.title, HUD_MENU_TITLE_COLOR, title_scale)

	inner_x := panel_x + padding
	inner_width := panel_width - padding * 2
	separator_y := title_y + title_height + separator_gap
	hud_emit_rect(o, inner_x, separator_y, inner_width, separator_thickness, HUD_MENU_SEPARATOR_COLOR)

	rows_y := separator_y + separator_thickness + separator_gap
	selected_valid := menu.selected >= 0 && menu.selected < len(menu.lines)
	for line, index in menu.lines {
		row_y := rows_y + f32(index) * row_height
		selected := selected_valid && index == menu.selected
		if selected {
			hud_emit_rect(
				o,
				inner_x,
				row_y,
				inner_width,
				row_height,
				HUD_MENU_HIGHLIGHT_COLOR,
			)
		}
		color := HUD_MENU_TEXT_COLOR
		if selected {
			color = HUD_MENU_SELECTED_COLOR
		}
		hud_emit_text(o, inner_x + text_inset, row_y + row_gap * 0.5, line, color, scale)
	}

	note_width := f32(stb_easy_font.width(menu.note)) * note_scale
	note_x := panel_x + (panel_width - note_width) * 0.5
	note_y := rows_y + lines_height + note_gap
	hud_emit_text(o, note_x, note_y, menu.note, HUD_MENU_NOTE_COLOR, note_scale)
}
