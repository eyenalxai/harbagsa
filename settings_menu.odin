#+vet explicit-allocators
package main

import "src:game"
import "src:platform"

@(private)
open_settings_menu :: proc(window: ^platform.Window, menu: ^game.Menu_State) -> bool {
	game.menu_open(menu)
	platform.set_click_capture(window, false)
	return platform.set_cursor_capture(window, false)
}

@(private)
close_settings_menu :: proc(
	window: ^platform.Window,
	menu: ^game.Menu_State,
	recapture: bool,
) -> bool {
	game.menu_close(menu)
	platform.set_click_capture(window, true)
	if recapture {
		return platform.set_cursor_capture(window, true)
	}
	return false
}

@(private)
handle_settings_menu_events :: proc(
	window: ^platform.Window,
	menu: ^game.Menu_State,
	settings: ^game.Settings,
	events: ^platform.Events,
	accumulator: ^f32,
	recapture: ^bool,
	latches: ^Input_Latches,
) {
	if events.menu_toggle_pressed {
		if menu.open {
			events.captured = close_settings_menu(window, menu, recapture^)
			accumulator^ = 0
		} else {
			recapture^ = events.captured
			events.captured = open_settings_menu(window, menu)
			accumulator^ = game.SIMULATION_STEP
			clear_latches(latches)
		}
	}

	if !menu.open {
		return
	}
	if events.menu_up_pressed {
		game.menu_move(menu, -1)
	}
	if events.menu_down_pressed {
		game.menu_move(menu, 1)
	}
	if events.menu_left_pressed {
		_ = game.menu_change_setting(menu, settings, -1)
	}
	if events.menu_right_pressed {
		_ = game.menu_change_setting(menu, settings, 1)
	}
	if events.menu_confirm_pressed && game.menu_activate(menu, settings) {
		events.captured = close_settings_menu(window, menu, recapture^)
		accumulator^ = 0
	}
}
