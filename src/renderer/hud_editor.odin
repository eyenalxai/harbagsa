#+vet explicit-allocators
package renderer

import "core:fmt"
import "core:math"

import stb_easy_font "vendor:stb/easy_font"

build_debug_panel :: proc(o: ^Overlay, hud: HUD_State, scale, margin, padding: f32) {
	selection_buffer: [64]u8
	selection_text: string
	switch hud.debug.selection {
	case .Crate:
		if hud.debug.crate_index >= 0 && hud.debug.crate_index < hud.debug.crate_count {
			selection_text = fmt.bprintf(selection_buffer[:], "Crate %d", hud.debug.crate_index + 1)
		} else {
			selection_text = "None"
		}
	case .Light:
		selection_text = "Sun"
	case .None:
		selection_text = "None"
	}
	selected_line_buffer: [96]u8
	selected_line := fmt.bprintf(selected_line_buffer[:], "Selected %s", selection_text)

	crates_buffer: [32]u8
	crates_line := fmt.bprintf(crates_buffer[:], "Crates %d", hud.debug.crate_count)

	position_buffer: [96]u8
	position_text := fmt.bprintf(
		position_buffer[:],
		"Position %.1f  %.1f  %.1f",
		snap_near_zero(hud.position.x),
		snap_near_zero(hud.position.y),
		snap_near_zero(hud.position.z),
	)

	sun_buffer: [64]u8
	sun_text := fmt.bprintf(
		sun_buffer[:],
		"Sun az %.0f  el %.0f",
		hud.debug.light_azimuth * 180.0 / math.PI,
		hud.debug.light_elevation * 180.0 / math.PI,
	)

	lines := [5]string{"Debug mode", selected_line, crates_line, position_text, sun_text}
	panel_width := 0
	for line in lines {
		panel_width = max(panel_width, stb_easy_font.width(line))
	}
	panel_height := 5 * HUD_LINE_HEIGHT * scale
	hud_emit_rect(
		o,
		margin,
		margin,
		f32(panel_width) * scale + padding * 2,
		panel_height + padding * 2,
		HUD_PANEL_COLOR,
	)
	for line, index in lines {
		hud_emit_text(
			o,
			margin + padding,
			margin + padding + f32(index) * HUD_LINE_HEIGHT * scale,
			line,
			HUD_TEXT_COLOR,
			scale,
		)
	}
}

build_debug_hints :: proc(o: ^Overlay, height, scale, margin, padding: f32) {
	hint_lines := [5]string {
		"WASD fly    Space up    Ctrl down",
		"Click select    Drag move    Wheel height",
		"E add    Delete remove    L light",
		"F2 exit    Shift+R reset scene",
		"F1 debug view    Esc release mouse",
	}
	hint_width := 0
	for line in hint_lines {
		hint_width = max(hint_width, stb_easy_font.width(line))
	}
	hint_panel_width := f32(hint_width) * scale + padding * 2
	hint_height := 5 * HUD_LINE_HEIGHT * scale
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
}
