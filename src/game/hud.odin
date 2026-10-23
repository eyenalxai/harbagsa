#+vet explicit-allocators
#+vet !unused-procedures // main calls this API; test builds compile game as a dependency
package game

import "core:fmt"
import "core:math"

HUD_STATUS_LINE_COUNT :: 6
HUD_DEBUG_STATUS_LINE_COUNT :: 5
HUD_MAX_STATUS_LINES :: 6
HUD_LINE_BYTES :: 96

HUD_CONTROL_LINES := [5]string {
	"WASD move    Mouse look    Left click capture",
	"Shift sprint    Space jump or hold to mantle",
	"C crouch or slide    Z prone, crawl, or dive",
	"R reset    Shift+R scene    F1 debug view",
	"F2 debug mode    Esc release mouse",
}

HUD_DEBUG_CONTROL_LINES := [5]string {
	"WASD fly    Space up    Ctrl down",
	"Click select    Drag move    Wheel height",
	"E add    Delete or X remove    L sun",
	"R reset player    F2 exit    Shift+R scene",
	"F1 debug view    Esc release mouse",
}

HUD_CAPTURE_HINT :: "Click to capture mouse"

HUD_State :: struct {
	status_lines:   []string,
	control_lines:  []string,
	capture_hint:   string,
	captured:       bool,
	status_strings: [HUD_MAX_STATUS_LINES]string,
	status_storage: [HUD_MAX_STATUS_LINES][HUD_LINE_BYTES]u8,
}

hud_state_update :: proc(
	hud: ^HUD_State,
	sim: ^Simulation,
	debug: ^Debug_Mode,
	snapshot: Render_Snapshot,
	captured: bool,
) {
	hud.captured = captured
	hud.capture_hint = HUD_CAPTURE_HINT
	if debug.active {
		hud_debug_state_update(hud, sim, debug)
		return
	}

	hud.control_lines = HUD_CONTROL_LINES[:]

	grounded := "no"
	if snapshot.grounded {
		grounded = "yes"
	}

	hud.status_strings[0] = fmt.bprintf(
		hud.status_storage[0][:],
		"Stance %s",
		stance_name(snapshot.stance),
	)
	hud.status_strings[1] = fmt.bprintf(
		hud.status_storage[1][:],
		"Gait %s",
		gait_name(snapshot.gait),
	)
	hud.status_strings[2] = fmt.bprintf(
		hud.status_storage[2][:],
		"Speed %.1f m/s",
		horizontal_speed(snapshot.velocity),
	)
	hud.status_strings[3] = fmt.bprintf(hud.status_storage[3][:], "Grounded %s", grounded)
	hud.status_strings[4] = fmt.bprintf(
		hud.status_storage[4][:],
		"State %s",
		movement_state_name(snapshot.movement_state),
	)
	hud.status_strings[5] = fmt.bprintf(
		hud.status_storage[5][:],
		"Position %.1f  %.1f  %.1f",
		snap_near_zero(snapshot.position.x),
		snap_near_zero(snapshot.position.y),
		snap_near_zero(snapshot.position.z),
	)
	hud.status_lines = hud.status_strings[:HUD_STATUS_LINE_COUNT]
}

@(private)
hud_debug_state_update :: proc(hud: ^HUD_State, sim: ^Simulation, debug: ^Debug_Mode) {
	hud.control_lines = HUD_DEBUG_CONTROL_LINES[:]

	selection: [32]u8
	selected := "Selected None"
	switch debug.selection {
	case .Crate:
		if debug.selected_crate >= 0 && debug.selected_crate < simulation_crate_count(sim) {
			selected = fmt.bprintf(selection[:], "Selected Crate %d", debug.selected_crate + 1)
		}
	case .Sun:
		selected = "Selected Sun"
	case .None:
	}

	azimuth, elevation := debug_mode_sun_angles(debug)
	position := debug.camera.position

	hud.status_strings[0] = "Debug mode"
	hud.status_strings[1] = fmt.bprintf(hud.status_storage[1][:], "%s", selected)
	hud.status_strings[2] = fmt.bprintf(
		hud.status_storage[2][:],
		"Crates %d",
		simulation_crate_count(sim),
	)
	hud.status_strings[3] = fmt.bprintf(
		hud.status_storage[3][:],
		"Position %.1f  %.1f  %.1f",
		snap_near_zero(position.x),
		snap_near_zero(position.y),
		snap_near_zero(position.z),
	)
	hud.status_strings[4] = fmt.bprintf(
		hud.status_storage[4][:],
		"Sun az %.0f  el %.0f",
		azimuth * 180.0 / math.PI,
		elevation * 180.0 / math.PI,
	)
	hud.status_lines = hud.status_strings[:HUD_DEBUG_STATUS_LINE_COUNT]
}

@(private)
snap_near_zero :: proc(value: f32) -> f32 {
	if value > -0.05 && value < 0.05 {
		return 0
	}
	return value
}
