#+vet explicit-allocators
package main

import "src:game"
import "src:input"
import "src:ui"

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
