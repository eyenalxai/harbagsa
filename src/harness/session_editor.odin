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
	if command.object.has_select_object {
		id := game.Object_Id(command.object.select_object)
		if !game.debug_select_object(&session.debug, &session.sim, id) {
			return format_error("object id %d does not exist", command.object.select_object)
		}
	}
	if command.has_body {
		if session.debug.palette.open {
			game.debug_palette_set_body(&session.debug, command.body)
		} else if _, selected := game.debug_selected_object_id(&session.debug, &session.sim); selected {
			if !game.debug_convert_selected(&session.debug, &session.sim, command.body) {
				return format_error("body conversion failed")
			}
		} else {
			game.debug_palette_set_body(&session.debug, command.body)
		}
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
	if command.light.has_color {
		if !game.debug_light_set_color(&session.debug, &session.sim, command.light.color) {
			return format_error("light_color needs a lamp placement or a selected lamp")
		}
	}
	if command.light.has_intensity {
		if !game.debug_light_set_intensity(
			&session.debug,
			&session.sim,
			command.light.intensity,
		) {
			return format_error("light_intensity needs a lamp placement or a selected lamp")
		}
	}
	if command.light.has_range {
		if !game.debug_light_set_range(&session.debug, &session.sim, command.light.range) {
			return format_error("light_range needs a lamp placement or a selected lamp")
		}
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
				light = placement_light(&session.debug, command.place.prefab),
			},
		)
	}
	if command.object.has_move {
		if !game.debug_move_selected(&session.debug, &session.sim, command.object.move) {
			return format_error("move needs a selected object")
		}
	}
	if command.object.has_rotate {
		if !game.debug_rotate_selected(&session.debug, &session.sim, command.object.rotate) {
			return format_error("rotate needs a selected object")
		}
	}
	if command.object.delete {
		if !game.debug_delete_selected(&session.debug, &session.sim) {
			return format_error("delete needs a selected object")
		}
	}
	if command.object.duplicate {
		if _, selected := game.debug_selected_object_id(&session.debug, &session.sim); !selected {
			return format_error("duplicate needs a selected object")
		}
		_ = game.debug_duplicate_selected(&session.debug, &session.sim)
	}
	if command.object.undo {
		_ = game.debug_undo(&session.debug, &session.sim)
	}
	if command.object.redo {
		_ = game.debug_redo(&session.debug, &session.sim)
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

// A direct place carries the tuned next-placement light only when it places the
// prefab the palette currently holds; another lamp prefab starts from its own
// defaults.
@(private)
placement_light :: proc(debug: ^game.Debug_Mode, prefab_id: game.Prefab_Id) -> game.Light_Settings {
	if !game.prefab_has_light(prefab_id) {
		return {}
	}
	if prefab_id == game.palette_selected(debug.palette) {
		return debug.palette.light
	}
	return game.prefab_light(prefab_id)
}
