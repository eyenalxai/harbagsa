#+vet explicit-allocators
package renderer

import "core:fmt"
import "core:math"

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
	case .Sun:
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
		hud.debug.sun_azimuth * 180.0 / math.PI,
		hud.debug.sun_elevation * 180.0 / math.PI,
	)

	lines := [5]string{"Debug mode", selected_line, crates_line, position_text, sun_text}
	hud_emit_panel(o, margin, margin, lines[:], scale, padding)
}

build_debug_hints :: proc(o: ^Overlay, height, scale, margin, padding: f32) {
	hint_lines := [5]string {
		"WASD fly    Space up    Ctrl down",
		"Click select    Drag move    Wheel height",
		"E add    Delete or X remove    L sun",
		"R reset player    F2 exit    Shift+R scene",
		"F1 debug view    Esc release mouse",
	}
	hint_y := height - margin - hud_panel_height(len(hint_lines), scale, padding)
	hud_emit_panel(o, margin, hint_y, hint_lines[:], scale, padding)
}
