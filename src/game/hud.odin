#+vet explicit-allocators
#+vet !unused-procedures // main calls this API; test builds compile game as a dependency
package game

import "core:fmt"
import "core:math"

HUD_STATUS_LINE_COUNT :: 6
HUD_DEBUG_STATUS_LINE_COUNT :: 5

HUD_CAPTURE_HINT :: "Click to capture mouse"

HUD_State :: struct {
	status:       Line_Buffer,
	capture_hint: string,
	captured:     bool,
	menu:         Menu_State,
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
	menu_view(&hud.menu, sim.settings, debug.active)
	if debug.active {
		hud_debug_state_update(hud, sim, debug)
		return
	}

	grounded := "no"
	if snapshot.grounded {
		grounded = "yes"
	}

	hud.status.lines[0] = fmt.bprintf(
		hud.status.storage[0][:],
		"Stance %s",
		stance_name(snapshot.stance),
	)
	hud.status.lines[1] = fmt.bprintf(
		hud.status.storage[1][:],
		"Gait %s",
		gait_name(snapshot.gait),
	)
	hud.status.lines[2] = fmt.bprintf(
		hud.status.storage[2][:],
		"Speed %.1f m/s",
		horizontal_speed(snapshot.velocity),
	)
	hud.status.lines[3] = fmt.bprintf(hud.status.storage[3][:], "Grounded %s", grounded)
	hud.status.lines[4] = fmt.bprintf(
		hud.status.storage[4][:],
		"State %s",
		movement_state_name(snapshot.movement_state),
	)
	hud.status.lines[5] = fmt.bprintf(
		hud.status.storage[5][:],
		"Position %.1f  %.1f  %.1f",
		snap_near_zero(snapshot.position.x),
		snap_near_zero(snapshot.position.y),
		snap_near_zero(snapshot.position.z),
	)
	hud.status.count = HUD_STATUS_LINE_COUNT
}

@(private)
hud_debug_state_update :: proc(hud: ^HUD_State, sim: ^Simulation, debug: ^Debug_Mode) {
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

	hud.status.lines[0] = "Debug mode"
	hud.status.lines[1] = fmt.bprintf(hud.status.storage[1][:], "%s", selected)
	hud.status.lines[2] = fmt.bprintf(
		hud.status.storage[2][:],
		"Crates %d",
		simulation_crate_count(sim),
	)
	hud.status.lines[3] = fmt.bprintf(
		hud.status.storage[3][:],
		"Position %.1f  %.1f  %.1f",
		snap_near_zero(position.x),
		snap_near_zero(position.y),
		snap_near_zero(position.z),
	)
	hud.status.lines[4] = fmt.bprintf(
		hud.status.storage[4][:],
		"Sun az %.0f  el %.0f",
		azimuth * 180.0 / math.PI,
		elevation * 180.0 / math.PI,
	)
	hud.status.count = HUD_DEBUG_STATUS_LINE_COUNT
}

@(private)
snap_near_zero :: proc(value: f32) -> f32 {
	if value > -0.05 && value < 0.05 {
		return 0
	}
	return value
}
