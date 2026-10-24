#+vet explicit-allocators
package harness

import "core:math"

import "src:game"

session_editor :: proc(session: ^Session, command: Editor_Command) -> string {
	if !session.debug.active {
		return format_error(
			"editor needs debug mode; send {\"cmd\": \"debug_mode\", \"active\": true} first",
		)
	}

	if command.has_camera {
		session.debug.camera = {
			position = command.camera.position,
			yaw      = command.camera.yaw,
			pitch    = command.camera.pitch,
		}
	}
	if command.has_open {
		if command.open {
			game.debug_palette_open(&session.debug)
		} else {
			game.debug_palette_close(&session.debug)
		}
	}
	if command.has_select {
		if !game.debug_palette_select(&session.debug, command.select) {
			return format_error("select index %d is out of range", command.select)
		}
	}
	if command.has_body {
		game.debug_palette_set_body(&session.debug, command.body)
	}
	if command.has_height {
		game.debug_placement_set_height(&session.debug, command.height)
	}
	if command.has_yaw {
		game.debug_placement_set_yaw(&session.debug, command.yaw)
	}
	if command.has_snap {
		game.debug_placement_set_snap(&session.debug, command.snap)
	}
	if command.pick {
		_ = game.debug_palette_pick(&session.debug, &session.sim)
	}
	if command.cancel {
		game.debug_placement_cancel(&session.debug)
	}
	if command.has_place {
		_ = game.debug_place_object(
			&session.debug,
			&session.sim,
			{
				prefab = command.place.prefab,
				body_mode = command.place.body,
				center = command.place.position,
				yaw = command.place.yaw * math.PI / 180.0,
			},
		)
	}
	if command.has_sun {
		if command.sun.has_active {
			if command.sun.active {
				game.debug_sun_enter(&session.debug, &session.sim)
			} else {
				game.debug_sun_exit(&session.debug)
			}
		}
		if command.sun.has_position {
			game.debug_sun_set_position(&session.debug, command.sun.position)
		}
		if command.sun.place {
			game.debug_sun_exit(&session.debug)
		}
		if command.sun.cancel {
			game.debug_sun_cancel(&session.debug)
		}
	}
	return ""
}
