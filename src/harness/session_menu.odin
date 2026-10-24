#+vet explicit-allocators
package harness

import "src:game"

session_menu :: proc(session: ^Session, command: Menu_Command) -> string {
	will_open := session.hud.menu.open
	if command.has_open {
		will_open = command.open
	}
	if command.has_select && !will_open {
		return "menu must be open to select a row"
	}
	if command.has_activate && !will_open {
		return "menu must be open to activate a row"
	}

	if command.has_open {
		if command.open {
			game.menu_open(&session.hud.menu)
		} else {
			game.menu_close(&session.hud.menu)
		}
	}
	if command.has_select {
		game.menu_select(&session.hud.menu, command.select)
	}
	if command.activate {
		_ = game.menu_activate(&session.hud.menu, &session.sim.settings)
	}
	return ""
}
