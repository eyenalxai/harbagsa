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
	reset_latched := false
	debug_view := false
	debug_lines: game.Debug_Lines
	hud: game.HUD_State
	last_time := time.now()

	for {
		events := platform.poll_events(&window)
		if events.quit {
			return true
		}
		if events.resized {
			renderer.notify_resize(&state)
		}
		if events.debug_pressed {
			debug_view = !debug_view
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

		// Look is per frame; jump is latched so a press survives a frame with
		// no step. Both are ignored while the cursor is free.
		if events.captured {
			game.simulation_look(&sim, events.look_delta)
		} else {
			jump_latched = false
		}
		if events.captured && events.jump_pressed {
			jump_latched = true
		}
		if events.reset_pressed {
			jump_latched = false
			reset_latched = true
		}

		accumulator += delta
		steps := 0
		for accumulator >= game.SIMULATION_STEP && steps < MAX_STEPS_PER_FRAME {
			game.simulation_step(
				&sim,
				game.Input_Snapshot {
					move_forward = events.move_forward,
					move_right = events.move_right,
					jump_pressed = jump_latched,
					reset_pressed = reset_latched,
				},
				game.SIMULATION_STEP,
			)
			jump_latched = false
			reset_latched = false
			accumulator -= game.SIMULATION_STEP
			steps += 1
		}
		if steps == MAX_STEPS_PER_FRAME && accumulator >= game.SIMULATION_STEP {
			// Drop a backlog that cannot drain.
			accumulator = 0
		}

		snapshot := game.simulation_snapshot(&sim)
		alpha := clamp(accumulator / game.SIMULATION_STEP, 0, 1)
		eye := snapshot.previous_eye_position +
		       (snapshot.eye_position - snapshot.previous_eye_position) * alpha
		camera := renderer.Camera {
			position = eye,
			yaw      = snapshot.yaw,
			pitch    = snapshot.pitch,
			fov_x    = PLAYER_FOV_X,
		}

		boxes: [game.ARENA_BOX_COUNT]geometry.Box
		for box, index in game.arena_static_boxes() {
			boxes[index] = box
		}
		for box, index in game.arena_crates() {
			draw_index := game.ARENA_STATIC_BOX_COUNT + index
			boxes[draw_index] = box
			boxes[draw_index].center = game.simulation_crate_position(&sim, index)
			rotation := game.simulation_crate_rotation(&sim, index)
			boxes[draw_index].rotation = {rotation.x, rotation.y, rotation.z, rotation.w}
		}

		debug_lines.count = 0
		if debug_view {
			game.collect_debug_lines(&sim, &debug_lines)
		}

		game.hud_state_update(&hud, snapshot, events.captured)

		frame, begin_status := renderer.begin_frame(
			&state,
			camera,
			boxes[:],
			debug_lines.lines[:debug_lines.count],
			renderer.HUD_Frame {
				status_lines = hud.status_lines[:],
				control_lines = hud.control_lines[:],
				capture_hint = hud.capture_hint,
				captured = hud.captured,
			},
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
