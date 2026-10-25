#+vet explicit-allocators
package main

import "src:game"
import "src:input"
import "src:platform"
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

// apply_menu_input applies one frame of navigation and the weight slider. It
// returns true when the menu asked to close.
@(private)
apply_menu_input :: proc(
	menu: ^game.Menu_State,
	settings: ^game.Settings,
	frame: input.Menu_Input,
	slider: ui.Slider_Rect,
	pointer: [2]f32,
) -> bool {
	if frame.up {
		game.menu_move(menu, -1)
	}
	if frame.down {
		game.menu_move(menu, 1)
	}
	if frame.left {
		_ = game.menu_change_setting(menu, settings, -1)
	}
	if frame.right {
		_ = game.menu_change_setting(menu, settings, 1)
	}
	closed := false
	if frame.confirm && game.menu_activate(menu, settings) {
		closed = true
	}
	game.menu_weight_input(
		menu,
		settings,
		slider,
		pointer,
		frame.pointer_pressed,
		frame.pointer_down,
	)
	return closed
}
