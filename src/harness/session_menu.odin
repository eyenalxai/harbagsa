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
	if command.has_set && !will_open {
		return "menu must be open to set a value"
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
		direction := 1
		if command.has_direction {
			direction = command.direction
		}
		_ = game.menu_activate(&session.hud.menu, &session.sim.settings, direction)
	}
	if command.has_set {
		_ = game.menu_set_type_weight(&session.hud.menu, &session.sim.settings, f32(command.set))
	}
	return ""
}
