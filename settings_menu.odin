#+vet explicit-allocators
package main

import "src:game"
import "src:platform"
import "src:renderer"
import "src:ui"

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
	slider: ui.Slider_Rect,
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
	apply_weight_drag(menu, settings, events, slider)
}

@(private)
menu_slider_for_window :: proc(r: ^renderer.Renderer, window: ^platform.Window) -> ui.Slider_Rect {
	slider := renderer.menu_slider_track(r)
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

@(private)
apply_weight_drag :: proc(
	menu: ^game.Menu_State,
	settings: ^game.Settings,
	events: ^platform.Events,
	slider: ui.Slider_Rect,
) {
	if !menu.open || slider.width <= 0 {
		return
	}
	ratio, inside := ui.slider_hit(slider, {events.pointer.x, events.pointer.y})
	if events.pointer_pressed && inside {
		game.menu_select(menu, int(game.Menu_Item.Type_Weight))
		menu.dragging_weight = true
	}
	if !menu.dragging_weight {
		return
	}
	if !events.pointer_down {
		menu.dragging_weight = false
		return
	}
	_ = game.menu_set_type_weight_ratio(menu, settings, ratio)
}
