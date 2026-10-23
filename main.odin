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

Input_Latches :: struct {
	jump:   bool,
	sprint: bool,
	crouch: bool,
	prone:  bool,
	reset:  bool,
}

clear_latches :: proc(latches: ^Input_Latches) {
	latches^ = {}
}

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
	latches: Input_Latches
	debug_view := false
	debug_lines: Debug_Lines
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

		// Look is per frame. Action edges are latched so a press survives a
		// frame with no step. All movement input is ignored while the cursor
		// is free.
		if events.captured {
			game.simulation_look(&sim, events.look_delta)
			if events.jump_pressed {
				latches.jump = true
			}
			if events.sprint_pressed {
				latches.sprint = true
			}
			if events.crouch_pressed {
				latches.crouch = true
			}
			if events.prone_pressed {
				latches.prone = true
			}
		} else {
			clear_latches(&latches)
		}
		if events.reset_pressed {
			clear_latches(&latches)
			latches.reset = true
		}

		accumulator += delta
		steps := 0
		for accumulator >= game.SIMULATION_STEP && steps < MAX_STEPS_PER_FRAME {
			game.simulation_step(
				&sim,
				game.Input_Snapshot {
					move_forward = events.move_forward,
					move_right = events.move_right,
					sprint_held = events.sprint_held,
					sprint_pressed = latches.sprint,
					crouch_held = events.crouch_held,
					crouch_pressed = latches.crouch,
					prone_held = events.prone_held,
					prone_pressed = latches.prone,
					jump_pressed = latches.jump,
					reset_pressed = latches.reset,
				},
				game.SIMULATION_STEP,
			)
			clear_latches(&latches)
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
			collect_debug_lines(&sim, &debug_lines)
		}

		hud := renderer.HUD_State {
			speed    = game.horizontal_speed(snapshot.velocity),
			grounded = snapshot.grounded,
			position = {snapshot.position.x, snapshot.position.y, snapshot.position.z},
			captured = events.captured,
			stance = game.stance_name(snapshot.stance),
			gait = game.gait_name(snapshot.gait),
			state = game.movement_state_name(snapshot.movement_state),
		}

		frame, begin_status := renderer.begin_frame(
			&state,
			camera,
			boxes[:],
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
