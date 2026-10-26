#+vet explicit-allocators
package harness

import "core:math"

import b3 "libs:box3d"

import "src:display"
import "src:game"

session_scene :: proc(session: ^Session, command: Scene_Command) -> string {
	scene := command.scene
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
		session.sim.settings.display = list
	}

	if command.has_settings {
		settings := command.settings
		if name, has := settings.window_mode.?; has {
			mode, mode_ok := game.window_mode_parse(name)
			if !mode_ok {
				return format_error("%s", "scene settings hold an unknown window mode")
			}
			session.sim.settings.window.mode = mode
		}
		if index, has := settings.display.?; has {
			session.sim.settings.window.display = display.clamp_index(
				&session.sim.settings.display,
				index,
			)
		}
		if resolution, has := settings.resolution.?; has {
			session.sim.settings.window.resolution = {resolution[0], resolution[1]}
		}
		if name, has := settings.sprint_mode.?; has {
			mode, mode_ok := game.input_mode_parse(name)
			if !mode_ok {
				return format_error("%s", "scene settings hold an unknown sprint mode")
			}
			session.sim.settings.sprint_mode = mode
		}
		if name, has := settings.crouch_mode.?; has {
			mode, mode_ok := game.input_mode_parse(name)
			if !mode_ok {
				return format_error("%s", "scene settings hold an unknown crouch mode")
			}
			session.sim.settings.crouch_mode = mode
		}
		if name, has := settings.prone_mode.?; has {
			mode, mode_ok := game.input_mode_parse(name)
			if !mode_ok {
				return format_error("%s", "scene settings hold an unknown prone mode")
			}
			session.sim.settings.prone_mode = mode
		}
		if weight, has := settings.type_weight.?; has {
			session.sim.settings.type_weight = weight
		}
	}

	if command.has_objects {
		for object, index in scene.objects {
			if object.name == "" {
				continue
			}
			for previous in scene.objects[:index] {
				if previous.name == object.name {
					return format_error("scene object name %q is given twice", object.name)
				}
			}
		}
		records := make([]game.Object_Record, len(scene.objects), session.allocator)
		defer delete(records, session.allocator)
		next_id := game.Object_Id(1)
		for object, index in scene.objects {
			prefab, prefab_ok := game.prefab_parse(object.prefab)
			body, body_ok := game.body_mode_parse(object.body)
			color, color_ok := game.light_color_parse(object.light.color)
			if !prefab_ok || !body_ok || !color_ok {
				return format_error("%s", "scene object holds an unknown prefab, body, or light colour")
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
		if !game.simulation_apply_snapshot(&session.sim, snapshot) {
			return format_error("%s", "cannot apply the scene objects")
		}
	}

	if command.has_probe_volumes {
		if probe_error := session_set_probe_volumes(session, scene.probe_volumes); probe_error != "" {
			return probe_error
		}
	}

	if command.has_camera {
		yaw := f32(math.to_radians(f64(scene.camera.yaw_deg)))
		pitch := f32(math.to_radians(f64(scene.camera.pitch_deg)))
		fov := f32(math.to_radians(f64(scene.camera.fov_deg)))
		switch scene.camera.source {
		case "debug":
			if !session.debug.active {
				game.debug_mode_toggle(&session.debug, &session.sim)
			}
			session.debug.camera = {
				position = {scene.camera.position[0], scene.camera.position[1], scene.camera.position[2]},
				yaw = yaw,
				pitch = pitch,
			}
			session.has_camera_override = false
		case "player":
			if session.debug.active {
				game.debug_mode_toggle(&session.debug, &session.sim)
			}
			if player, has_player := scene.camera.player.?; has_player {
				stance, stance_ok := game.stance_parse(player.stance)
				if !stance_ok {
					return format_error("%s", "scene player holds an unknown stance")
				}
				game.player_place(
					&session.sim.player,
					b3.Vec3{player.position[0], player.position[1], player.position[2]},
					f32(math.to_radians(f64(player.yaw_deg))),
					f32(math.to_radians(f64(player.pitch_deg))),
				)
				game.commit_stance(&session.sim.player, stance)
				session.sim.player.velocity = {
					player.velocity[0],
					player.velocity[1],
					player.velocity[2],
				}
				session.sim.player.grounded = player.grounded
				session.sim.player.grounded_last_step = player.grounded
				session.sim.player.step_smoothing = player.step_smoothing
				session.sim.player.eye_height = player.eye_height
				if session.sim.player.eye_height <= 0 {
					session.sim.player.eye_height = game.stance_eye_height(stance)
				}
				session.sim.player.previous_eye_height = session.sim.player.eye_height
			}
			game.simulation_face(&session.sim, yaw, pitch)
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
		if value, has := command.view.perf.?; has {
			session.view.perf = value
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
	game.menu_close(&session.hud.menu)
	return ""
}
