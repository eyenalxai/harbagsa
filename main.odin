#+vet explicit-allocators
package main

import "core:log"
import "core:os"
import "core:time"

import "src:frame"
import "src:game"
import "src:perf"
import "src:platform"
import "src:renderer"

MAX_FRAME_DELTA :: f32(0.1)
MAX_STEPS_PER_FRAME :: 8

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
	initial := game.settings_default()
	window, platform_error := platform.init(
		"harbagsa",
		i32(initial.window.resolution.width),
		i32(initial.window.resolution.height),
		initial.window.mode == .Borderless,
	)
	if platform_error != .None {
		log.errorf("harbagsa: platform init failed: %v", platform_error)
		return false
	}
	defer platform.deinit(&window)
	platform.sync_window(&window)

	pixel_width, pixel_height := platform.pixel_size(&window)
	if pixel_width == 0 || pixel_height == 0 {
		log.error("harbagsa: window pixel size is zero")
		return false
	}
	perf_state: perf.State
	state, renderer_error := renderer.init(
		renderer.Config {
			platform = platform.renderer_platform(&window),
			target = .Swapchain,
			width = pixel_width,
			height = pixel_height,
			recorder = &perf_state.recorder,
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
	menu_recapture := false
	last_time := time.now()

	displays := platform.query_displays()
	if displays.list.count == 0 {
		log.warn("harbagsa: SDL reported no displays; keeping the created window")
	}
	hud.menu.displays = displays.list
	initial_display := platform.display_index_for_window(&window, &displays)
	if initial_display >= 0 {
		sim.settings.window.display = initial_display
	} else {
		log.warn("harbagsa: the launch display is not in the display list")
	}
	applied_window := sim.settings.window
	if initial_display >= 0 && !platform.apply_window_state(&window, &displays, applied_window) {
		log.warn("harbagsa: the initial window settings were not applied")
	}
	renderer.notify_resize(&state)

	for {
		perf.begin_frame(&perf_state)
		events := platform.poll_events(&window)
		if events.quit {
			return true
		}
		if events.resized {
			renderer.notify_resize(&state)
		}

		handle_settings_menu_events(
			&state,
			&window,
			&hud.menu,
			&sim.settings,
			debug.active,
			&events,
			&accumulator,
			&menu_recapture,
			&latches,
		)

		if events.perf_pressed {
			hud.perf.visible = !hud.perf.visible
		}

		if !hud.menu.open {
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
				renderer.reset_history(&state, .Scene_Reset)
				clear_latches(&latches)
			} else if events.reset_pressed {
				game.debug_mode_reset_player(&debug, &sim)
				renderer.reset_history(&state, .Player_Reset)
				clear_latches(&latches)
			}
		}

		if sim.settings.window != applied_window {
			if platform.apply_window_state(&window, &displays, sim.settings.window) {
				applied_window = sim.settings.window
			} else {
				log.warn("harbagsa: the window settings were not applied")
				sim.settings.window = applied_window
			}
			renderer.notify_resize(&state)
		}

		perf.mark(&perf_state, .Events)

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
			perf.discard_frame(&perf_state)
			continue
		}

		now := time.now()
		delta := f32(time.duration_seconds(time.diff(last_time, now)))
		last_time = now
		delta = clamp(delta, 0, MAX_FRAME_DELTA)

		// Look is per frame. Action edges are latched so a press survives a
		// frame with no step. Movement input is ignored in debug mode and while
		// the cursor is free.
		if !hud.menu.open && events.captured && !debug.active {
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

		if !hud.menu.open {
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
							jump_held = events.jump_held,
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
		}

		// Edit after the fixed steps so a dragged transform is the one rendered.
		move_up: f32
		if events.fly_up {
			move_up += 1
		}
		if events.fly_down {
			move_up -= 1
		}
		if debug.active && !hud.menu.open {
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

		perf.mark(&perf_state, .Simulation)

		if hud.perf.visible {
			hud.perf.stats = perf.stats(&perf_state)
		}

		alpha := clamp(accumulator / game.SIMULATION_STEP, 0, 1)
		scene := frame.build(
			&sim,
			&debug,
			frame.Options {
				alpha = alpha,
				debug_view = debug_view,
				captured = events.captured,
				hud = true,
			},
			nil,
			&hud,
			&scratch,
		)
		perf.mark(&perf_state, .Build)

		switch frame.draw(&state, scene) {
		case .Ok:
			perf.mark(&perf_state, .Present)
			perf.set_gpu(&perf_state, renderer.gpu_times(&state))
			perf.end_frame(&perf_state)
		case .Skipped:
			perf.discard_frame(&perf_state)
			continue
		case .Fatal:
			return false
		}
	}
}
