#+vet explicit-allocators
package main

import "core:log"

import "src:game"
import "src:platform"
import "src:renderer"

Editor_State :: struct {
	pointer_available: bool,
}

// The game loop owns the palette handoff and the pointer. The game only sees
// palette state and actions, and the renderer only sees a normalized pointer.
handle_editor_events :: proc(
	window: ^platform.Window,
	debug: ^game.Debug_Mode,
	sim: ^game.Simulation,
	renderer_state: ^renderer.Renderer,
	menu_open: bool,
	events: ^platform.Events,
	state: ^Editor_State,
) {
	if !debug.active || menu_open {
		return
	}

	// Esc closes the palette, then the placement, before it reaches settings.
	if events.cancel_pressed {
		if debug.palette.open {
			game.debug_palette_close(debug)
			recapture_after_palette(window, events, state)
			events.cancel_pressed = false
		} else if debug.placement.armed {
			game.debug_placement_cancel(debug)
			events.cancel_pressed = false
		}
	}

	if events.palette_toggle_pressed {
		if debug.palette.open {
			game.debug_palette_close(debug)
			recapture_after_palette(window, events, state)
		} else {
			open_palette(window, debug, events, state)
		}
		events.palette_toggle_pressed = false
	}

	if debug.palette.open && events.secondary_pressed {
		game.debug_palette_close(debug)
		recapture_after_palette(window, events, state)
		events.secondary_pressed = false
	}

	if events.flip_body_pressed {
		game.debug_palette_flip_body(debug)
	}
	if events.toggle_snap_pressed {
		game.debug_placement_toggle_snap(debug)
	}

	if !debug.palette.open {
		return
	}
	handle_palette_pointer(window, debug, sim, renderer_state, events, state)
	if !debug.palette.open {
		return
	}
	handle_palette_keys(window, debug, sim, events, state)
}

editor_input_from_events :: proc(events: platform.Events) -> game.Debug_Input {
	move_up: f32
	if events.fly_up {
		move_up += 1
	}
	if events.fly_down {
		move_up -= 1
	}
	return {
		move_forward = events.move_forward,
		move_right = events.move_right,
		move_up = move_up,
		look_delta = events.look_delta,
		wheel_delta = events.wheel_delta,
		primary_pressed = events.primary_pressed,
		primary_released = events.primary_released,
		secondary_pressed = events.secondary_pressed,
		delete_pressed = events.delete_pressed,
		rotate_left = events.rotate_left_pressed,
		rotate_right = events.rotate_right_pressed,
		large_step = events.sprint_held,
		sun_pressed = events.sun_pressed,
		captured = events.captured,
	}
}

@(private)
open_palette :: proc(
	window: ^platform.Window,
	debug: ^game.Debug_Mode,
	events: ^platform.Events,
	state: ^Editor_State,
) {
	game.debug_palette_open(debug)
	platform.set_click_capture(window, false)
	released := !platform.set_cursor_capture(window, false)
	if !released {
		log.warn("harbagsa: cursor release for the palette failed; using the keyboard path")
	}
	events.captured = !released
	state.pointer_available = released
}

@(private)
recapture_after_palette :: proc(
	window: ^platform.Window,
	events: ^platform.Events,
	state: ^Editor_State,
) {
	platform.set_click_capture(window, true)
	events.captured = platform.set_cursor_capture(window, true)
	state.pointer_available = false
}

@(private)
pick_palette :: proc(
	window: ^platform.Window,
	debug: ^game.Debug_Mode,
	sim: ^game.Simulation,
	events: ^platform.Events,
	state: ^Editor_State,
) {
	if !game.debug_palette_pick(debug, sim) {
		return
	}
	recapture_after_palette(window, events, state)
}

@(private)
handle_palette_pointer :: proc(
	window: ^platform.Window,
	debug: ^game.Debug_Mode,
	sim: ^game.Simulation,
	renderer_state: ^renderer.Renderer,
	events: ^platform.Events,
	state: ^Editor_State,
) {
	if !state.pointer_available {
		return
	}
	hit := renderer.palette_hit_test(renderer_state, events.pointer, game.PREFAB_COUNT)
	if events.pointer_moved && hit.card >= 0 {
		_ = game.debug_palette_select(debug, hit.card)
	}
	if !events.pointer_pressed {
		return
	}
	if hit.card >= 0 {
		_ = game.debug_palette_select(debug, hit.card)
		pick_palette(window, debug, sim, events, state)
	} else if !hit.inside {
		game.debug_palette_close(debug)
		recapture_after_palette(window, events, state)
	}
}

@(private)
handle_palette_keys :: proc(
	window: ^platform.Window,
	debug: ^game.Debug_Mode,
	sim: ^game.Simulation,
	events: ^platform.Events,
	state: ^Editor_State,
) {
	delta: int
	switch {
	case events.navigate_up_pressed, events.navigate_left_pressed:
		delta = -1
	case events.navigate_down_pressed, events.navigate_right_pressed:
		delta = 1
	}
	if delta != 0 {
		count := game.PREFAB_COUNT
		_ = game.debug_palette_select(debug, (debug.palette.selected + delta + count) % count)
	}
	if events.palette_number > 0 {
		_ = game.debug_palette_select(debug, events.palette_number - 1)
	}
	if events.confirm_pressed {
		pick_palette(window, debug, sim, events, state)
	}
}
