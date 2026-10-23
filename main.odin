#+vet explicit-allocators
package main

import "core:log"
import "core:math"
import "core:os"
import "core:time"

import "src:game"
import "src:geometry"
import "src:platform"
import "src:renderer"

WINDOW_WIDTH :: 1280
WINDOW_HEIGHT :: 720

PLAYER_FOV_X :: f32(90.0 * math.PI / 180.0)
MAX_FRAME_DELTA :: f32(0.1)
MAX_STEPS_PER_FRAME :: 8

main :: proc() {
	logger := log.create_console_logger(lowest = .Info, allocator = context.allocator)
	context.logger = logger

	ok := run()
	log.destroy_console_logger(logger, allocator = context.allocator)
	if !ok {
		os.exit(1)
	}
}

run :: proc() -> bool {
	window, platform_error := platform.init("harbagsa", WINDOW_WIDTH, WINDOW_HEIGHT)
	if platform_error != .None {
		log.errorf("harbagsa: platform init failed: %v", platform_error)
		return false
	}
	defer platform.deinit(&window)

	state, renderer_error := renderer.init(&window, context.allocator)
	if renderer_error != .None {
		log.errorf("harbagsa: renderer init failed: %v", renderer_error)
		return false
	}
	defer renderer.deinit(&state)

	sim := game.simulation_create()
	if !game.simulation_is_valid(&sim) {
		log.error("harbagsa: simulation init failed")
		return false
	}
	defer game.simulation_destroy(&sim)

	accumulator: f32 = 0
	jump_latched := false
	debug_view := false
	debug := game.debug_mode_create()
	debug_lines: game.Debug_Lines
	last_time := time.now()

	for {
		events := platform.poll_events(&window)
		if events.quit {
			return true
		}
		if events.resized {
			renderer.notify_resize(&state)
		}
		if events.debug_view_pressed {
			debug_view = !debug_view
		}
		if events.debug_mode_pressed {
			game.debug_mode_toggle(&debug, &sim)
			jump_latched = false
		}
		if events.reset_scene_pressed {
			game.debug_mode_reset_scene(&debug, &sim)
			jump_latched = false
		} else if events.reset_pressed {
			game.debug_mode_reset_player(&debug, &sim)
			jump_latched = false
		}

		width, height := platform.pixel_size(&window)
		if platform.is_minimized(&window) || width == 0 || height == 0 {
			// Block while minimized; do not spin.
			waited := platform.wait_events(&window, 100)
			if waited.quit {
				return true
			}
			if waited.resized {
				renderer.notify_resize(&state)
			}
			// Drop the wait time so the first restored frame does not step the whole pause.
			last_time = time.now()
			continue
		}

		now := time.now()
		delta := f32(time.duration_seconds(time.diff(last_time, now)))
		last_time = now
		delta = clamp(delta, 0, MAX_FRAME_DELTA)

		// Look is per frame; jump is latched so a press survives a frame with no step.
		if events.captured && !debug.active {
			game.simulation_look(&sim, events.look_delta)
		}
		if !events.captured {
			jump_latched = false
		}
		if events.captured && events.jump_pressed && !debug.active {
			jump_latched = true
		}

		accumulator += delta
		steps := 0
		for accumulator >= game.SIMULATION_STEP && steps < MAX_STEPS_PER_FRAME {
			if debug.active {
				game.simulation_step_world(&sim, game.SIMULATION_STEP)
			} else {
				game.simulation_step(
					&sim,
					game.Input_Snapshot {
						move_forward = events.move_forward,
						move_right = events.move_right,
						jump_pressed = jump_latched,
					},
					game.SIMULATION_STEP,
				)
				jump_latched = false
			}
			accumulator -= game.SIMULATION_STEP
			steps += 1
		}
		if steps == MAX_STEPS_PER_FRAME && accumulator >= game.SIMULATION_STEP {
			// Drop a backlog that cannot drain.
			accumulator = 0
		}

		// Edit after the fixed steps so a dragged transform is the one rendered.
		move_up: f32
		if events.fly_up {
			move_up += 1
		}
		if events.fly_down {
			move_up -= 1
		}
		if debug.active {
			game.debug_mode_update(
				&debug,
				&sim,
				game.Debug_Input {
					move_forward = events.move_forward,
					move_right = events.move_right,
					move_up = move_up,
					look_delta = events.look_delta,
					wheel_delta = events.wheel_delta,
					primary_pressed = events.primary_pressed,
					primary_released = events.primary_released,
					add_pressed = events.add_pressed,
					delete_pressed = events.delete_pressed,
					sun_pressed = events.sun_pressed,
					captured = events.captured,
				},
				delta,
			)
		}

		snapshot := game.simulation_snapshot(&sim)
		camera: renderer.Camera
		hud_position: [3]f32
		if debug.active {
			debug_camera := debug.camera
			camera = renderer.Camera {
				position = debug_camera.position,
				yaw      = debug_camera.yaw,
				pitch    = debug_camera.pitch,
				fov_x    = PLAYER_FOV_X,
			}
			hud_position = debug_camera.position
		} else {
			alpha := clamp(accumulator / game.SIMULATION_STEP, 0, 1)
			eye := snapshot.previous_eye_position +
			       (snapshot.eye_position - snapshot.previous_eye_position) * alpha
			camera = renderer.Camera {
				position = eye,
				yaw      = snapshot.yaw,
				pitch    = snapshot.pitch,
				fov_x    = PLAYER_FOV_X,
			}
			hud_position = snapshot.position
		}

		boxes: [game.MAX_SCENE_BOXES]geometry.Box
		box_count := 0
		for box in game.arena_static_boxes() {
			boxes[box_count] = box
			box_count += 1
		}
		for index in 0 ..< game.simulation_crate_count(&sim) {
			boxes[box_count] = game.simulation_crate_box(&sim, index)
			box_count += 1
		}

		debug_lines.count = 0
		if debug_view {
			game.collect_world_lines(&sim, &debug_lines)
		}
		if debug.active {
			game.collect_editor_lines(&debug, &sim, &debug_lines)
		}

		debug_selection := renderer.HUD_Selection.None
		#partial switch debug.selection {
		case .Crate:
			debug_selection = .Crate
		case .Sun:
			debug_selection = .Sun
		}
		sun_azimuth, sun_elevation := game.debug_mode_sun_angles(&debug)

		hud := renderer.HUD_State {
			speed = math.sqrt(
				snapshot.velocity.x * snapshot.velocity.x +
				snapshot.velocity.z * snapshot.velocity.z,
			),
			grounded = snapshot.grounded,
			position = hud_position,
			captured = events.captured,
			debug_active = debug.active,
			debug = renderer.HUD_Debug_State {
				selection = debug_selection,
				crate_index = debug.selected_crate,
				crate_count = game.simulation_crate_count(&sim),
				sun_azimuth = sun_azimuth,
				sun_elevation = sun_elevation,
			},
		}

		frame, begin_status := renderer.begin_frame(
			&state,
			camera,
			game.debug_mode_sun_direction(&debug),
			boxes[:box_count],
			debug_lines.lines[:debug_lines.count],
			hud,
		)
		switch begin_status {
		case .Ok:
		case .Skipped:
			continue
		case .Fatal:
			return false
		}

		switch renderer.end_frame(&state, frame) {
		case .Ok:
		case .Skipped:
		case .Fatal:
			return false
		}
	}
}
