#+vet explicit-allocators
package main

import "src:game"
import "src:platform"

Input_Latches :: struct {
	jump:   bool,
	sprint: bool,
	crouch: bool,
	prone:  bool,
}

clear_latches :: proc(latches: ^Input_Latches) {
	latches^ = {}
}

// The platform polls movement with the cursor free so the debug camera can
// fly, but the player must not move until the cursor is captured again.
player_input :: proc(events: platform.Events, latches: Input_Latches) -> game.Input_Snapshot {
	captured := events.captured
	return {
		move_forward = captured ? events.move_forward : 0,
		move_right = captured ? events.move_right : 0,
		sprint_held = captured && events.sprint_held,
		sprint_pressed = latches.sprint,
		crouch_held = captured && events.crouch_held,
		crouch_pressed = latches.crouch,
		prone_held = captured && events.prone_held,
		prone_pressed = latches.prone,
		jump_pressed = latches.jump,
		jump_held = captured && events.jump_held,
	}
}
