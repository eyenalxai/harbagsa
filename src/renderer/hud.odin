#+vet explicit-allocators
package renderer

import "core:fmt"

import stb_easy_font "vendor:stb/easy_font"

HUD_Selection :: enum {
	None,
	Crate,
	Sun,
}

HUD_Debug_State :: struct {
	selection:     HUD_Selection,
	crate_index:   int,
	crate_count:   int,
	sun_azimuth:   f32,
	sun_elevation: f32,
}

HUD_State :: struct {
	speed:        f32,
	grounded:     bool,
	position:     [3]f32,
	captured:     bool,
	debug_active: bool,
	debug:        HUD_Debug_State,
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

hud_emit_panel :: proc(o: ^Overlay, x, y: f32, lines: []string, scale, padding: f32) {
	panel_width := 0
	for line in lines {
		panel_width = max(panel_width, stb_easy_font.width(line))
	}
	hud_emit_rect(
		o,
		x,
		y,
		f32(panel_width) * scale + padding * 2,
		hud_panel_height(len(lines), scale, padding),
		HUD_PANEL_COLOR,
	)
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

hud_panel_height :: proc(line_count: int, scale, padding: f32) -> f32 {
	return f32(line_count) * HUD_LINE_HEIGHT * scale + padding * 2
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

	build_state_panel(o, hud, scale, margin, padding)
	build_hints(o, height, hud, scale, margin, padding)
	build_capture_overlay(o, width, height, hud, scale, padding)
	build_crosshair(o, width, height, scale)
}

@(private)
build_state_panel :: proc(o: ^Overlay, hud: HUD_State, scale, margin, padding: f32) {
	if hud.debug_active {
		build_debug_panel(o, hud, scale, margin, padding)
		return
	}

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

	lines := [3]string{speed_text, grounded_text, position_text}
	hud_emit_panel(o, margin, margin, lines[:], scale, padding)
}
