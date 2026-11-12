#+vet explicit-allocators
package harness

import "core:math"

import b3 "libs:box3d"

import "src:display"
import "src:game"

session_scene :: proc(session: ^Session, command: Scene_Command) -> string {
	scene := command.scene

	// A rejected object snapshot must not leave the settings or display blocks
	// applied, so the object block runs first.
	if command.has_objects {
		records := make([]game.Object_Record, len(scene.objects), session.allocator)
		defer delete(records, session.allocator)
		next_id := game.Object_Id(1)
		for object, index in scene.objects {
			prefab, prefab_ok := game.prefab_parse(object.prefab)
			body, body_ok := game.body_mode_parse(object.body)
			color, color_ok := game.light_color_parse(object.light.color)
			kind, kind_ok := game.lamp_kind_parse(object.light.kind)
			if !prefab_ok || !body_ok || !color_ok || !kind_ok {
				return format_error("%s", "scene object holds an unknown prefab, body, light kind, or light colour")
			}
			record := game.Object_Record {
				id = game.Object_Id(object.id),
				prefab = prefab,
				body_mode = body,
				center = {object.position[0], object.position[1], object.position[2]},
				rotation = quaternion(
					x = object.rotation[0],
					y = object.rotation[1],
					z = object.rotation[2],
					w = object.rotation[3],
				),
				color = object.color,
				light = {
					active = object.light.active,
					kind = kind,
					color = color,
					intensity = object.light.intensity,
					range = object.light.range,
					emissive = object.light.emissive,
				},
			}
			record.name_length = u8(len(object.name))
			copy(record.name[:], object.name)
			records[index] = record
			next_id = max(next_id, game.Object_Id(object.id) + 1)
		}
		snapshot := game.Object_Snapshot {
			objects = records,
			next_object_id = next_id,
		}
		if failure := game.simulation_apply_snapshot(
			&session.runtime.sim,
			snapshot,
		); failure.error != .None {
			return format_error(
				"cannot apply the scene objects: %s",
				game.snapshot_apply_error_message(failure),
			)
		}
		game.editor_reset(&session.runtime.debug.editor)
	}

	if command.has_displays {
		list: display.List
		list.count = len(scene.displays)
		for scene_display, index in scene.displays {
			info := &list.items[index]
			display.set_name(info, scene_display.name)
			display.set_desktop(info, {scene_display.desktop[0], scene_display.desktop[1]})
			for mode in scene_display.modes {
				display.add_mode(info, {mode[0], mode[1]})
			}
			display.sort_modes(info)
		}
		session.runtime.sim.settings.display = list
	}

	if command.has_settings {
		settings := command.settings
		if name, has := settings.window_mode.?; has {
			mode, mode_ok := game.window_mode_parse(name)
			if !mode_ok {
				return format_error("%s", "scene settings hold an unknown window mode")
			}
			session.runtime.sim.settings.window.mode = mode
		}
		if index, has := settings.display.?; has {
			session.runtime.sim.settings.window.display = display.clamp_index(
				&session.runtime.sim.settings.display,
				index,
			)
		}
		if resolution, has := settings.resolution.?; has {
			session.runtime.sim.settings.window.resolution = {resolution[0], resolution[1]}
		}
		if name, has := settings.sprint_mode.?; has {
			mode, mode_ok := game.input_mode_parse(name)
			if !mode_ok {
				return format_error("%s", "scene settings hold an unknown sprint mode")
			}
			session.runtime.sim.settings.sprint_mode = mode
		}
		if weight, has := settings.type_weight.?; has {
			session.runtime.sim.settings.type_weight = weight
		}
	}

	if command.has_camera {
		yaw := f32(math.to_radians(f64(scene.camera.yaw_deg)))
		pitch := f32(math.to_radians(f64(scene.camera.pitch_deg)))
		fov := f32(math.to_radians(f64(scene.camera.fov_deg)))
		switch scene.camera.source {
		case "debug":
			if !session.runtime.debug.active {
				game.debug_mode_toggle(&session.runtime.debug, &session.runtime.sim)
			}
			session.runtime.debug.camera = {
				position = {scene.camera.position[0], scene.camera.position[1], scene.camera.position[2]},
				yaw = yaw,
				pitch = pitch,
			}
			session.has_camera_override = false
		case "player", "third_person":
			if session.runtime.debug.active {
				game.debug_mode_toggle(&session.runtime.debug, &session.runtime.sim)
			}
			if player, has_player := scene.camera.player.?; has_player {
				game.player_place(
					&session.runtime.sim.player,
					b3.Vec3{player.position[0], player.position[1], player.position[2]},
					f32(math.to_radians(f64(player.yaw_deg))),
					0.0,
				)
				session.runtime.sim.player.camera_yaw = f32(
					math.to_radians(f64(player.camera_yaw_deg)),
				)
				session.runtime.sim.player.camera_pitch = f32(
					math.to_radians(f64(player.camera_pitch_deg)),
				)
				session.runtime.sim.player.velocity = {
					player.velocity[0],
					player.velocity[1],
					player.velocity[2],
				}
				session.runtime.sim.player.grounded = player.grounded
				session.runtime.sim.player.grounded_last_step = player.grounded
				game.spider_plant_legs(&session.runtime.sim)
			}
			session.has_camera_override = false
		case "override":
			session.camera_override = {
				position = {scene.camera.position[0], scene.camera.position[1], scene.camera.position[2]},
				yaw = yaw,
				pitch = pitch,
				fov_x = fov,
			}
			session.has_camera_override = true
		}
	}

	if command.has_view {
		if value, has := command.view.hud.?; has {
			session.view.hud = value
		}
		if value, has := command.view.debug.?; has {
			session.view.debug = value
		}
		if value, has := command.view.hint.?; has {
			session.view.hint = value
		}
		if value, has := command.view.fx.?; has {
			session.view.fx = value
		}
	}
	if debug, has := command.renderer_debug.?; has {
		if session.render.backend == nil || !session.render.backend.ready {
			if ensure_error := session_ensure_backend(session); ensure_error != "" {
				return ensure_error
			}
		}
		if debug_error := session_renderer_debug(session, debug); debug_error != "" {
			return debug_error
		}
	}
	game.menu_close(&session.runtime.hud.menu)
	return ""
}
