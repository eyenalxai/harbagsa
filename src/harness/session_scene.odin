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
			info.desktop = {scene_display.desktop[0], scene_display.desktop[1]}
			for mode in scene_display.modes {
				display.add_mode(info, {mode[0], mode[1]})
			}
		}
		session.hud.menu.displays = list
	}

	if command.has_settings {
		window_mode, window_ok := game.window_mode_parse(scene.settings.window_mode)
		sprint, sprint_ok := game.input_mode_parse(scene.settings.sprint_mode)
		crouch, crouch_ok := game.input_mode_parse(scene.settings.crouch_mode)
		prone, prone_ok := game.input_mode_parse(scene.settings.prone_mode)
		if !window_ok || !sprint_ok || !crouch_ok || !prone_ok {
			return format_error("%s", "scene settings hold an unknown mode")
		}
		session.sim.settings.window.mode = window_mode
		session.sim.settings.window.display = display.clamp_index(
			&session.hud.menu.displays,
			scene.settings.display,
		)
		session.sim.settings.window.resolution = {
			scene.settings.resolution[0],
			scene.settings.resolution[1],
		}
		session.sim.settings.sprint_mode = sprint
		session.sim.settings.crouch_mode = crouch
		session.sim.settings.prone_mode = prone
		session.sim.settings.type_weight = scene.settings.type_weight
	}

	if command.has_objects {
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
			records[index] = {
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

	if command.has_sun {
		session.debug.sun.position = scene.sun.position
		session.debug.sun_angular_diameter = f32(math.to_radians(f64(scene.sun.angular_diameter_deg)))
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
		session.view = {
			hud = scene.view.hud,
			debug = scene.view.debug,
			hint = scene.view.hint,
			perf = scene.view.perf,
		}
	}
	game.menu_close(&session.hud.menu)
	return ""
}
