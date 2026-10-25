#+vet explicit-allocators
package main

import "core:log"
import "core:math"

import "src:game"
import "src:platform"
import "src:renderer"

Editor_State :: struct {
	pointer_available: bool,
	palette_was_open:  bool,
	actions:           [game.MAX_EDIT_ACTIONS]game.Edit_Action,
	action_count:      int,
}

// The window loop owns the pointer and the cursor. It turns events into edit
// intents; `game.edit_apply` owns every rule those intents follow.
handle_editor_events :: proc(
	window: ^platform.Window,
	debug: ^game.Debug_Mode,
	sim: ^game.Simulation,
	renderer_state: ^renderer.Renderer,
	menu_open: bool,
	events: ^platform.Events,
	state: ^Editor_State,
) {
	state.action_count = 0
	if !debug.active || menu_open {
		return
	}
	palette_open := debug.palette.open

	// Esc closes the nearest mode. If none is active it stays with the settings
	// menu, so the caller must not consume it.
	if events.cancel_pressed && (palette_open || debug.placement.armed || debug.sun.active) {
		add_action(state, game.Cancel{})
		events.cancel_pressed = false
	}

	if events.palette_toggle_pressed {
		if palette_open {
			add_action(state, game.Palette_Close{})
			palette_open = false
		} else {
			add_action(state, game.Palette_Open{})
			palette_open = true
		}
		events.palette_toggle_pressed = false
	}

	// The palette owns the cursor, so close it before a right click reaches the
	// world. The same press must not also clear an object selection.
	if palette_open && events.secondary_pressed {
		add_action(state, game.Palette_Close{})
		palette_open = false
		events.secondary_pressed = false
	}

	// L hands the cursor back before the sun mode takes the same key.
	if palette_open && events.sun_placement_pressed {
		add_action(state, game.Palette_Close{})
		palette_open = false
	}

	if events.flip_body_pressed {
		add_action(state, game.Flip_Body{})
		events.flip_body_pressed = false
	}
	if events.toggle_snap_pressed {
		add_action(state, game.Placement_Toggle_Snap{})
		events.toggle_snap_pressed = false
	}

	sun_action := false
	if events.sun_placement_pressed {
		add_action(state, game.Sun_Toggle{})
		sun_action = true
		events.sun_placement_pressed = false
	}

	if palette_open {
		palette_open = collect_palette_actions(renderer_state, events, state, palette_open)
	}
	// The sun mode owns the click that commits or cancels it and blocks the
	// light keys, exactly like the keyboard path before the action set existed.
	if debug.sun.active || sun_action {
		if debug.sun.active && !sun_action {
			collect_sun_pointer_actions(events, state)
		}
		return
	}

	collect_light_actions(events, state)
	if palette_open {
		return
	}

	if events.undo_pressed {
		add_action(state, game.Undo{})
		events.undo_pressed = false
	}
	if events.redo_pressed {
		add_action(state, game.Redo{})
		events.redo_pressed = false
	}
	if events.duplicate_pressed {
		add_action(state, game.Duplicate_Selected{})
		events.duplicate_pressed = false
	}
	if events.delete_pressed {
		add_action(state, game.Delete_Selected{})
		events.delete_pressed = false
	}
	if events.rotate_left_pressed {
		add_action(state, game.Turn{steps = -1, large = events.sprint_held})
		events.rotate_left_pressed = false
	}
	if events.rotate_right_pressed {
		add_action(state, game.Turn{steps = 1, large = events.sprint_held})
		events.rotate_right_pressed = false
	}
	if events.primary_pressed {
		add_action(state, game.Primary_Press{})
		events.primary_pressed = false
	}
	if events.primary_released {
		add_action(state, game.Primary_Release{})
		events.primary_released = false
	}
	if events.secondary_pressed {
		add_action(state, game.Secondary_Press{})
		events.secondary_pressed = false
	}
	if events.wheel_delta != 0.0 {
		add_action(
			state,
			game.Wheel{steps = int(math.round(events.wheel_delta)), large = events.sprint_held},
		)
		events.wheel_delta = 0
	}
	if debug.dragging == .Object {
		add_action(state, game.Drag_Move{look_delta = events.look_delta})
	}
}

editor_motion :: proc(events: platform.Events) -> game.Debug_Motion {
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
		captured = events.captured,
	}
}

// The cursor follows the palette. The menu owns it separately, so leave the
// palette flag alone while the menu is open.
editor_sync_cursor :: proc(
	window: ^platform.Window,
	debug: ^game.Debug_Mode,
	menu_open: bool,
	state: ^Editor_State,
) {
	if !debug.active || menu_open {
		state.palette_was_open = debug.palette.open
		return
	}
	if debug.palette.open == state.palette_was_open {
		return
	}
	state.palette_was_open = debug.palette.open
	if debug.palette.open {
		platform.set_click_capture(window, false)
		released := !platform.set_cursor_capture(window, false)
		state.pointer_available = released
		if !released {
			log.warn("harbagsa: cursor release for the palette failed; using the keyboard path")
		}
		return
	}
	platform.set_click_capture(window, true)
	_ = platform.set_cursor_capture(window, true)
	state.pointer_available = false
}

@(private)
add_action :: proc(state: ^Editor_State, action: game.Edit_Action) {
	if state.action_count >= len(state.actions) {
		log.warn("harbagsa: the editor action buffer is full")
		return
	}
	state.actions[state.action_count] = action
	state.action_count += 1
}

@(private)
collect_sun_pointer_actions :: proc(events: ^platform.Events, state: ^Editor_State) {
	if events.primary_pressed {
		add_action(state, game.Primary_Press{})
		events.primary_pressed = false
	}
	if events.secondary_pressed {
		add_action(state, game.Secondary_Press{})
		events.secondary_pressed = false
	}
}

@(private)
collect_light_actions :: proc(events: ^platform.Events, state: ^Editor_State) {
	if events.light_color_pressed {
		add_action(state, game.Light_Adjust{change = .Color})
		events.light_color_pressed = false
	}
	if events.light_intensity_down_pressed {
		add_action(state, game.Light_Adjust{change = .Intensity_Down})
		events.light_intensity_down_pressed = false
	}
	if events.light_intensity_up_pressed {
		add_action(state, game.Light_Adjust{change = .Intensity_Up})
		events.light_intensity_up_pressed = false
	}
	if events.light_range_down_pressed {
		add_action(state, game.Light_Adjust{change = .Range_Down})
		events.light_range_down_pressed = false
	}
	if events.light_range_up_pressed {
		add_action(state, game.Light_Adjust{change = .Range_Up})
		events.light_range_up_pressed = false
	}
}

@(private)
collect_palette_actions :: proc(
	renderer_state: ^renderer.Renderer,
	events: ^platform.Events,
	state: ^Editor_State,
	palette_open: bool,
) -> bool {
	open := palette_open
	if state.pointer_available {
		hit := renderer.palette_hit_test(renderer_state, events.pointer, game.PREFAB_COUNT)
		if events.pointer_moved && hit.card >= 0 {
			add_action(state, game.Palette_Select{index = hit.card})
		}
		if events.pointer_pressed {
			if hit.card >= 0 {
				add_action(state, game.Palette_Select{index = hit.card})
				add_action(state, game.Palette_Pick{})
				open = false
			} else if !hit.inside {
				add_action(state, game.Palette_Close{})
				open = false
			}
			events.pointer_pressed = false
		}
	}

	delta: int
	switch {
	case events.navigate_up_pressed, events.navigate_left_pressed:
		delta = -1
	case events.navigate_down_pressed, events.navigate_right_pressed:
		delta = 1
	}
	if delta != 0 {
		add_action(state, game.Palette_Step{delta = delta})
	}
	if events.palette_number > 0 {
		add_action(state, game.Palette_Select{index = events.palette_number - 1})
	}
	if events.confirm_pressed {
		add_action(state, game.Palette_Pick{})
		open = false
	}
	events.navigate_up_pressed = false
	events.navigate_down_pressed = false
	events.navigate_left_pressed = false
	events.navigate_right_pressed = false
	events.confirm_pressed = false
	events.palette_number = 0
	return open
}
