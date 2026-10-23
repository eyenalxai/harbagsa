#+vet explicit-allocators
package main

import "core:log"
import "core:os"
import "core:time"

import "src:frame"
import "src:game"
import "src:platform"
import "src:renderer"

WINDOW_WIDTH :: 1280
WINDOW_HEIGHT :: 720

MAX_FRAME_DELTA :: f32(0.1)
MAX_STEPS_PER_FRAME :: 8

Input_Latches :: struct {
	jump:   bool,
	sprint: bool,
	crouch: bool,
	prone:  bool,
}

clear_latches :: proc(latches: ^Input_Latches) {
	latches^ = {}
}

main :: proc() {
	logger := log.create_console_logger(lowest = .Info, allocator = context.allocator)
	context.logger = logger

	ok := run()
	log.destroy_console_logger(logger, allocator = context.allocator)
	if !ok || renderer.validation_failed() {
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

	state, renderer_error := renderer.init(
		renderer.Config {
			platform = platform.renderer_platform(&window),
			target = .Swapchain,
			width = WINDOW_WIDTH,
			height = WINDOW_HEIGHT,
		},
		context.allocator,
	)
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
	debug := game.debug_mode_create()
	scratch: frame.Scratch
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
		if events.debug_view_pressed {
			debug_view = !debug_view
		}
		if events.debug_mode_pressed {
			game.debug_mode_toggle(&debug, &sim)
			clear_latches(&latches)
		}
		if events.taa_pressed {
			renderer.toggle_taa(&state)
		}
		if events.reset_scene_pressed {
			game.debug_mode_reset_scene(&debug, &sim)
			renderer.reset_history(&state)
			clear_latches(&latches)
		} else if events.reset_pressed {
			game.debug_mode_reset_player(&debug, &sim)
			renderer.reset_history(&state)
			clear_latches(&latches)
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
		// frame with no step. Movement input is ignored in debug mode and while
		// the cursor is free.
		if events.captured && !debug.active {
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
						sprint_held = events.sprint_held,
						sprint_pressed = latches.sprint,
						crouch_held = events.crouch_held,
						crouch_pressed = latches.crouch,
						prone_held = events.prone_held,
						prone_pressed = latches.prone,
						jump_pressed = latches.jump,
					},
					game.SIMULATION_STEP,
				)
				clear_latches(&latches)
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

		scene := frame.build(
			&sim,
			&debug,
			frame.Options {
				alpha = clamp(accumulator / game.SIMULATION_STEP, 0, 1),
				debug_view = debug_view,
				captured = events.captured,
				hud = true,
			},
			nil,
			&hud,
			&scratch,
		)

		switch frame.draw(&state, scene) {
		case .Ok:
		case .Skipped:
			continue
		case .Fatal:
			return false
		}
	}
}
