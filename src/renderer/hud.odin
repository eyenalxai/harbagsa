#+vet explicit-allocators
package renderer

import "core:fmt"

import stb_easy_font "vendor:stb/easy_font"

HUD_State :: struct {
	speed:    f32,
	grounded: bool,
	position: [3]f32,
	captured: bool,
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

snap_near_zero :: proc(value: f32) -> f32 {
	if value > -0.05 && value < 0.05 {
		return 0
	}
	return value
}

build_hud :: proc(o: ^Overlay, width, height: f32, hud: HUD_State) {
	scale := 2.0 * clamp(height / 720.0, 1.0, 2.0)
	margin := 8.0 * scale
	padding := 5.0 * scale

	grounded := "no"
	if hud.grounded {
		grounded = "yes"
	}

	speed_buffer: [64]u8
	speed_text := fmt.bprintf(speed_buffer[:], "Speed %.1f m/s", hud.speed)
	grounded_buffer: [32]u8
	grounded_text := fmt.bprintf(grounded_buffer[:], "Grounded %s", grounded)
	position_buffer: [96]u8
	position_text := fmt.bprintf(
		position_buffer[:],
		"Position %.1f  %.1f  %.1f",
		snap_near_zero(hud.position.x),
		snap_near_zero(hud.position.y),
		snap_near_zero(hud.position.z),
	)

	state_width := f32(
		max(
			stb_easy_font.width(speed_text),
			max(stb_easy_font.width(grounded_text), stb_easy_font.width(position_text)),
		),
	) * scale
	state_height := 3 * HUD_LINE_HEIGHT * scale
	hud_emit_rect(
		o,
		margin,
		margin,
		state_width + padding * 2,
		state_height + padding * 2,
		HUD_PANEL_COLOR,
	)
	hud_emit_text(o, margin + padding, margin + padding, speed_text, HUD_TEXT_COLOR, scale)
	hud_emit_text(
		o,
		margin + padding,
		margin + padding + HUD_LINE_HEIGHT * scale,
		grounded_text,
		HUD_TEXT_COLOR,
		scale,
	)
	hud_emit_text(
		o,
		margin + padding,
		margin + padding + 2 * HUD_LINE_HEIGHT * scale,
		position_text,
		HUD_TEXT_COLOR,
		scale,
	)

	hint_lines := [3]string {
		"WASD move    Mouse look",
		"Space jump    R reset",
		"F1 debug view    Esc release mouse",
	}
	hint_width := 0
	for line in hint_lines {
		hint_width = max(hint_width, stb_easy_font.width(line))
	}
	hint_panel_width := f32(hint_width) * scale + padding * 2
	hint_height := 3 * HUD_LINE_HEIGHT * scale
	hint_x := margin
	hint_y := height - margin - hint_height - padding * 2
	hud_emit_rect(o, hint_x, hint_y, hint_panel_width, hint_height + padding * 2, HUD_PANEL_COLOR)
	for line, index in hint_lines {
		hud_emit_text(
			o,
			hint_x + padding,
			hint_y + padding + f32(index) * HUD_LINE_HEIGHT * scale,
			line,
			HUD_TEXT_COLOR,
			scale,
		)
	}

	center_x := width * 0.5
	center_y := height * 0.5
	if !hud.captured {
		overlay_text := "Click to capture mouse"
		overlay_scale := scale * 1.1
		text_width := f32(stb_easy_font.width(overlay_text)) * overlay_scale
		text_height := f32(stb_easy_font.height(overlay_text)) * overlay_scale
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
		hud_emit_text(o, text_x, text_y, overlay_text, HUD_TEXT_COLOR, overlay_scale)
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
