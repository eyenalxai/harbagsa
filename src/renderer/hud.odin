#+vet explicit-allocators
package renderer

import stb_easy_font "vendor:stb/easy_font"

HUD_Frame :: struct {
	enabled:       bool,
	status_lines:  []string,
	control_lines: []string,
	capture_hint:  string,
	captured:      bool,
}

HUD_TEXT_COLOR :: [4]f32{1.0, 1.0, 1.0, 1.0}
HUD_CROSSHAIR_COLOR :: [4]f32{1.0, 1.0, 1.0, 0.9}
HUD_PANEL_COLOR :: [4]f32{0.01, 0.015, 0.02, 0.65}
HUD_LINE_HEIGHT :: 12.0

hud_emit_quad :: proc(o: ^Overlay, a, b, c, d: [2]f32, color: [4]f32) {
	append_hud_vertex(o, a, color)
	append_hud_vertex(o, b, color)
	append_hud_vertex(o, c, color)
	append_hud_vertex(o, a, color)
	append_hud_vertex(o, c, color)
	append_hud_vertex(o, d, color)
}

hud_emit_rect :: proc(o: ^Overlay, x, y, width, height: f32, color: [4]f32) {
	if width <= 0 || height <= 0 {
		return
	}
	top_left := [2]f32{x, y}
	top_right := [2]f32{x + width, y}
	bottom_right := [2]f32{x + width, y + height}
	bottom_left := [2]f32{x, y + height}
	hud_emit_quad(o, top_left, top_right, bottom_right, bottom_left, color)
}

hud_emit_text :: proc(o: ^Overlay, x, y: f32, text: string, color: [4]f32, scale: f32) {
	quad_count := stb_easy_font.print(x, y, text, {255, 255, 255, 255}, o.quads, scale)
	for i in 0 ..< quad_count {
		quad := o.quads[i]
		top_left := [2]f32{quad.tl.v.x, quad.tl.v.y}
		top_right := [2]f32{quad.tr.v.x, quad.tr.v.y}
		bottom_right := [2]f32{quad.br.v.x, quad.br.v.y}
		bottom_left := [2]f32{quad.bl.v.x, quad.bl.v.y}
		hud_emit_quad(o, top_left, top_right, bottom_right, bottom_left, color)
	}
}

hud_panel_height :: proc(lines: []string, scale: f32) -> f32 {
	return f32(len(lines)) * HUD_LINE_HEIGHT * scale
}

hud_emit_panel :: proc(o: ^Overlay, lines: []string, x, y, scale, padding: f32) {
	width: f32
	for line in lines {
		width = max(width, f32(stb_easy_font.width(line)) * scale)
	}
	height := hud_panel_height(lines, scale)
	hud_emit_rect(o, x, y, width + padding * 2, height + padding * 2, HUD_PANEL_COLOR)
	for line, index in lines {
		hud_emit_text(
			o,
			x + padding,
			y + padding + f32(index) * HUD_LINE_HEIGHT * scale,
			line,
			HUD_TEXT_COLOR,
			scale,
		)
	}
}

build_hud :: proc(o: ^Overlay, width, height: f32, hud: HUD_Frame) {
	if !hud.enabled {
		return
	}
	scale := 2.0 * clamp(height / 720.0, 1.0, 2.0)
	margin := 8.0 * scale
	padding := 5.0 * scale

	hud_emit_panel(o, hud.status_lines, margin, margin, scale, padding)

	control_y := height - margin - hud_panel_height(hud.control_lines, scale) - padding * 2
	hud_emit_panel(o, hud.control_lines, margin, control_y, scale, padding)

	center_x := width * 0.5
	center_y := height * 0.5
	if !hud.captured {
		overlay_scale := scale * 1.1
		text_width := f32(stb_easy_font.width(hud.capture_hint)) * overlay_scale
		text_height := f32(stb_easy_font.height(hud.capture_hint)) * overlay_scale
		text_x := (width - text_width) * 0.5
		text_y := center_y - text_height * 0.5
		panel_padding := padding * 1.5
		hud_emit_rect(
			o,
			text_x - panel_padding,
			text_y - panel_padding,
			text_width + panel_padding * 2,
			text_height + panel_padding * 2,
			HUD_PANEL_COLOR,
		)
		hud_emit_text(o, text_x, text_y, hud.capture_hint, HUD_TEXT_COLOR, overlay_scale)
	}

	// The crosshair is emitted last so it stays on top of the panels.
	arm := 10.0 * (scale * 0.5)
	gap := 4.0 * (scale * 0.5)
	thickness := max(1.0, scale * 0.5)
	outline := max(1.0, scale * 0.5)
	crosshair_outline := [4]f32{0, 0, 0, 0.55}
	hud_emit_rect(
		o,
		center_x - gap - arm - outline,
		center_y - thickness * 0.5 - outline,
		arm + 2 * outline,
		thickness + 2 * outline,
		crosshair_outline,
	)
	hud_emit_rect(
		o,
		center_x - gap - arm,
		center_y - thickness * 0.5,
		arm,
		thickness,
		HUD_CROSSHAIR_COLOR,
	)
	hud_emit_rect(
		o,
		center_x + gap - outline,
		center_y - thickness * 0.5 - outline,
		arm + 2 * outline,
		thickness + 2 * outline,
		crosshair_outline,
	)
	hud_emit_rect(
		o,
		center_x + gap,
		center_y - thickness * 0.5,
		arm,
		thickness,
		HUD_CROSSHAIR_COLOR,
	)
	hud_emit_rect(
		o,
		center_x - thickness * 0.5 - outline,
		center_y - gap - arm - outline,
		thickness + 2 * outline,
		arm + 2 * outline,
		crosshair_outline,
	)
	hud_emit_rect(
		o,
		center_x - thickness * 0.5,
		center_y - gap - arm,
		thickness,
		arm,
		HUD_CROSSHAIR_COLOR,
	)
	hud_emit_rect(
		o,
		center_x - thickness * 0.5 - outline,
		center_y + gap - outline,
		thickness + 2 * outline,
		arm + 2 * outline,
		crosshair_outline,
	)
	hud_emit_rect(
		o,
		center_x - thickness * 0.5,
		center_y + gap,
		thickness,
		arm,
		HUD_CROSSHAIR_COLOR,
	)
}
