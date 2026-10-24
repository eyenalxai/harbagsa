#+vet explicit-allocators
package main

import "src:game"
import "src:platform"
import "src:renderer"
import "src:ui"

@(private)
open_settings_menu :: proc(
	window: ^platform.Window,
	menu: ^game.Menu_State,
	debug: ^game.Debug_Mode,
) -> bool {
	game.menu_open(menu)
	game.debug_mode_cancel_editing(debug)
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
	r: ^renderer.Renderer,
	window: ^platform.Window,
	menu: ^game.Menu_State,
	debug: ^game.Debug_Mode,
	settings: ^game.Settings,
	debug_active: bool,
	events: ^platform.Events,
	accumulator: ^f32,
	recapture: ^bool,
	latches: ^Input_Latches,
) {
	if events.cancel_pressed {
		if menu.open {
			events.captured = close_settings_menu(window, menu, recapture^)
			accumulator^ = 0
		} else {
			recapture^ = events.captured
			events.captured = open_settings_menu(window, menu, debug)
			accumulator^ = game.SIMULATION_STEP
			clear_latches(latches)
			// The rows and the track rect normally come from the previous draw.
			// Neither exists yet, so build them before this frame reads input.
			game.menu_view(menu, settings^, debug_active, 0)
		}
	}

	if !menu.open {
		return
	}
	if events.navigate_up_pressed {
		game.menu_move(menu, -1)
	}
	if events.navigate_down_pressed {
		game.menu_move(menu, 1)
	}
	if events.navigate_left_pressed {
		_ = game.menu_change_setting(menu, settings, -1)
	}
	if events.navigate_right_pressed {
		_ = game.menu_change_setting(menu, settings, 1)
	}
	if events.confirm_pressed && game.menu_activate(menu, settings) {
		events.captured = close_settings_menu(window, menu, recapture^)
		accumulator^ = 0
	}
	game.menu_weight_input(
		menu,
		settings,
		menu_slider_for_window(r, window, menu.view),
		events.pointer,
		events.pointer_pressed,
		events.pointer_down,
	)
}

@(private)
menu_slider_for_window :: proc(
	r: ^renderer.Renderer,
	window: ^platform.Window,
	menu: ui.Menu,
) -> ui.Slider_Rect {
	slider := renderer.menu_slider_rect(r, menu)
	window_width, window_height := platform.window_size(window)
	if window_width <= 0 || window_height <= 0 {
		return slider
	}
	width, height := renderer.target_extent(r)
	scale_x := f32(width) / window_width
	scale_y := f32(height) / window_height
	slider.x *= scale_x
	slider.width *= scale_x
	slider.knob *= scale_x
	slider.y *= scale_y
	slider.height *= scale_y
	return slider
}
