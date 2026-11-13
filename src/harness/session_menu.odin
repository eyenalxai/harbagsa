#+vet explicit-allocators
package harness

import "src:game"

session_menu :: proc(session: ^Session, command: Menu_Command) -> string {
	will_open := session.runtime.hud.menu.open
	if command.has_open {
		will_open = command.open
	}
	if command.has_item && !will_open {
		return format_error("%s", "menu must be open to select a row")
	}
	if command.has_activate && !will_open {
		return format_error("%s", "menu must be open to activate a row")
	}
	if (command.has_opacity || command.has_reduce_motion) && !will_open {
		return format_error("%s", "menu must be open to set a value")
	}

	if command.has_open {
		if command.open {
			game.menu_open(&session.runtime.hud.menu)
			game.debug_mode_cancel_editing(&session.runtime.debug)
		} else {
			game.menu_close(&session.runtime.hud.menu)
		}
	}
	if command.has_item {
		game.menu_select(&session.runtime.hud.menu, int(command.item))
	}
	if command.activate {
		direction := 1
		if command.has_direction {
			direction = command.direction
		}
		_ = game.menu_activate(&session.runtime.hud.menu, &session.runtime.sim.settings, direction)
	}
	if command.has_opacity {
		_ = game.settings_set(
			&session.runtime.sim.settings,
			.Hud_Opacity,
			0,
			f32(command.opacity) / 100.0,
		)
	}
	if command.has_reduce_motion {
		value := command.reduce_motion ? 1 : 0
		_ = game.settings_set(&session.runtime.sim.settings, .Reduce_Motion, value, 0)
	}
	return ""
}
