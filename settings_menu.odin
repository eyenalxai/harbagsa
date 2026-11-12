#+vet explicit-allocators
package main

import "src:game"
import "src:input"

// apply_menu_input applies one frame of navigation. It returns true when the
// menu asked to close. The Rune view also returns click actions through the
// renderer; this path owns the keyboard and the setting values.
@(private)
apply_menu_input :: proc(
	menu: ^game.Menu_State,
	settings: ^game.Settings,
	frame: input.Menu_Input,
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
	if frame.confirm && game.menu_activate(menu, settings) {
		return true
	}
	return false
}
