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
