#+vet explicit-allocators
#+vet !unused-procedures // main calls this API; test builds compile game as a dependency
package game

import "core:fmt"
import "core:math"

HUD_STATUS_LINE_COUNT :: 3
HUD_CONTROL_LINE_COUNT :: 3
HUD_LINE_BYTES :: 96

HUD_CONTROL_LINES := [HUD_CONTROL_LINE_COUNT]string {
	"WASD move    Mouse look",
	"Space jump    R reset",
	"F1 debug view    Esc release mouse",
}

HUD_CAPTURE_HINT :: "Click to capture mouse"

HUD_State :: struct {
	status_lines:   [HUD_STATUS_LINE_COUNT]string,
	control_lines:  [HUD_CONTROL_LINE_COUNT]string,
	capture_hint:   string,
	captured:       bool,
	status_storage: [HUD_STATUS_LINE_COUNT][HUD_LINE_BYTES]u8,
}

hud_state_update :: proc(hud: ^HUD_State, snapshot: Render_Snapshot, captured: bool) {
	hud.captured = captured
	hud.capture_hint = HUD_CAPTURE_HINT
	hud.control_lines = HUD_CONTROL_LINES

	grounded := "no"
	if snapshot.grounded {
		grounded = "yes"
	}

	speed := math.sqrt(
		snapshot.velocity.x * snapshot.velocity.x +
		snapshot.velocity.z * snapshot.velocity.z,
	)

	hud.status_lines[0] = fmt.bprintf(hud.status_storage[0][:], "Speed %.1f m/s", speed)
	hud.status_lines[1] = fmt.bprintf(hud.status_storage[1][:], "Grounded %s", grounded)
	hud.status_lines[2] = fmt.bprintf(
		hud.status_storage[2][:],
		"Position %.1f  %.1f  %.1f",
		snap_near_zero(snapshot.position.x),
		snap_near_zero(snapshot.position.y),
		snap_near_zero(snapshot.position.z),
	)
}

@(private)
snap_near_zero :: proc(value: f32) -> f32 {
	if value > -0.05 && value < 0.05 {
		return 0
	}
	return value
}
