#+vet explicit-allocators
package harness

import "src:game"

session_menu :: proc(session: ^Session, command: Menu_Command) -> string {
	will_open := session.app.runtime.hud.menu.open
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
			game.debug_mode_open_menu(&session.app.runtime.debug, &session.app.runtime.hud.menu)
		} else {
			game.menu_close(&session.app.runtime.hud.menu)
		}
	}
	if command.has_item {
		game.menu_select(&session.app.runtime.hud.menu, int(command.item))
	}
	if command.activate {
		direction := 1
		if command.has_direction {
			direction = command.direction
		}
		if session.app.runtime.hud.menu.selected == .Resume {
			if !game.menu_activate(&session.app.runtime.hud.menu, &session.app.runtime.sim.settings) {
				return format_error("%s", "Resume did not close the settings dialog")
			}
		} else {
			result := game.menu_change_setting(
				&session.app.runtime.hud.menu,
				&session.app.runtime.sim.settings,
				direction,
			)
			if result != .Changed && !(result == .Blocked && command.allow_blocked) {
				message := session.app.runtime.hud.menu.status
				if message == "" {
					message = "the setting did not change"
				}
				return format_error("settings change failed: %s", message)
			}
		}
	}
	if command.has_opacity {
		if !game.settings_set(
			&session.app.runtime.sim.settings,
			.Hud_Opacity,
			0,
			f32(command.opacity) / 100.0,
		) && !command.allow_blocked {
			return format_error("%s", "HUD opacity did not change")
		}
	}
	if command.has_reduce_motion {
		value := command.reduce_motion ? 1 : 0
		if !game.settings_set(&session.app.runtime.sim.settings, .Reduce_Motion, value, 0) &&
		   !command.allow_blocked {
			return format_error("%s", "Reduce motion did not change")
		}
	}
	return ""
}
