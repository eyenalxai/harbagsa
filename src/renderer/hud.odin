#+vet explicit-allocators
package renderer

HUD_Menu :: struct {
	open:     bool,
	title:    string,
	lines:    []string,
	selected: int,
	note:     string,
}

HUD_Frame :: struct {
	enabled:      bool,
	status_lines: []string,
	capture_hint: string,
	captured:     bool,
	menu:         HUD_Menu,
}

HUD_CROSSHAIR_ARM :: 10.0
HUD_CROSSHAIR_GAP :: 4.0

hud_emit_textured_quad :: proc(
	o: ^Overlay,
	a, b, c, d: [2]f32,
	uv0, uv1: [2]f32,
	color: [4]f32,
) {
	append_hud_vertex(o, a, color, uv0)
	append_hud_vertex(o, b, color, {uv1.x, uv0.y})
	append_hud_vertex(o, c, color, uv1)
	append_hud_vertex(o, a, color, uv0)
	append_hud_vertex(o, c, color, uv1)
	append_hud_vertex(o, d, color, {uv0.x, uv1.y})
}

hud_emit_quad :: proc(o: ^Overlay, a, b, c, d: [2]f32, color: [4]f32) {
	hud_emit_textured_quad(o, a, b, c, d, TEXT_UV_NONE, TEXT_UV_NONE, color)
}

hud_emit_rect :: proc(o: ^Overlay, x, y, width, height: f32, color: [4]f32) {
	if width <= 0 || height <= 0 {
		return
	}
	hud_emit_quad(
		o,
		{x, y},
		{x + width, y},
		{x + width, y + height},
		{x, y + height},
		color,
	)
}

hud_panel_height :: proc(style: Text_Type, line_count: int) -> f32 {
	return f32(line_count) * style.line_height
}

hud_emit_panel :: proc(
	o: ^Overlay,
	lines: []string,
	x, y: f32,
	style: Text_Style,
	padding: f32,
) {
	width: f32
	for line in lines {
		width = max(width, text_measure(&o.atlas, style.type, line))
	}
	height := hud_panel_height(style.type, len(lines))
	hud_emit_rect(o, x, y, width + padding * 2, height + padding * 2, o.theme.surface_hud)
	baseline_offset := text_baseline(&o.atlas, style.type)
	for line, index in lines {
		text_emit(
			o,
			x + padding,
			y + padding + f32(index) * style.type.line_height + baseline_offset,
			style,
			line,
		)
	}
}

build_hud :: proc(o: ^Overlay, width, height: f32, hud: HUD_Frame) {
	if !hud.enabled {
		return
	}
	theme := o.theme
	if hud.menu.open {
		build_menu(o, width, height, hud.menu)
		return
	}

	margin := theme.spacing.md
	padding := theme.spacing.sm
	text_style := Text_Style{type = theme.type_body, color = theme.text_primary}

	hud_emit_panel(o, hud.status_lines, margin, margin, text_style, padding)

	center_x := width * 0.5
	center_y := height * 0.5
	if !hud.captured && hud.capture_hint != "" {
		text_width := text_measure(&o.atlas, text_style.type, hud.capture_hint)
		text_height := text_style.type.line_height
		text_x := center_x - text_width * 0.5
		text_y := center_y - text_height * 0.5
		panel_padding := padding * 1.5
		hud_emit_rect(
			o,
			text_x - panel_padding,
			text_y - panel_padding,
			text_width + panel_padding * 2,
			text_height + panel_padding * 2,
			theme.surface_hud,
		)
		text_emit(
			o,
			text_x,
			text_y + text_baseline(&o.atlas, text_style.type),
			text_style,
			hud.capture_hint,
		)
	}

	draw_crosshair(o, center_x, center_y)
}

@(private)
draw_crosshair :: proc(o: ^Overlay, center_x, center_y: f32) {
	theme := o.theme
	arm := HUD_CROSSHAIR_ARM * theme.density
	gap := HUD_CROSSHAIR_GAP * theme.density
	thickness := theme.hairline
	outline := theme.hairline

	hud_crosshair_arm(o, center_x - gap - arm, center_y - thickness * 0.5, arm, thickness, outline)
	hud_crosshair_arm(o, center_x + gap, center_y - thickness * 0.5, arm, thickness, outline)
	hud_crosshair_arm(o, center_x - thickness * 0.5, center_y - gap - arm, thickness, arm, outline)
	hud_crosshair_arm(o, center_x - thickness * 0.5, center_y + gap, thickness, arm, outline)
}

@(private)
hud_crosshair_arm :: proc(
	o: ^Overlay,
	x, y, width, height, outline: f32,
) {
	theme := o.theme
	hud_emit_rect(
		o,
		x - outline,
		y - outline,
		width + outline * 2,
		height + outline * 2,
		theme.crosshair_edge,
	)
	hud_emit_rect(o, x, y, width, height, theme.crosshair)
}
