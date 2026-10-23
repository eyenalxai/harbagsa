#+vet explicit-allocators
package renderer

import stb_easy_font "vendor:stb/easy_font"

build_hints :: proc(o: ^Overlay, height: f32, hud: HUD_State, scale, margin, padding: f32) {
	if hud.debug_active {
		build_debug_hints(o, height, scale, margin, padding)
		return
	}

	hint_lines := [4]string {
		"WASD move    Mouse look",
		"Space jump    R reset",
		"F1 debug view    F2 debug mode",
		"Esc release mouse",
	}
	hint_y := height - margin - hud_panel_height(len(hint_lines), scale, padding)
	hud_emit_panel(o, margin, hint_y, hint_lines[:], scale, padding)
}

build_capture_overlay :: proc(o: ^Overlay, width, height: f32, hud: HUD_State, scale, padding: f32) {
	if hud.captured {
		return
	}

	overlay_text := "Click to capture mouse"
	overlay_scale := scale * 1.1
	text_width := f32(stb_easy_font.width(overlay_text)) * overlay_scale
	text_height := f32(stb_easy_font.height(overlay_text)) * overlay_scale
	text_x := (width - text_width) * 0.5
	text_y := height * 0.5 - text_height * 0.5
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
build_crosshair :: proc(o: ^Overlay, width, height, scale: f32) {
	center_x := width * 0.5
	center_y := height * 0.5
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
