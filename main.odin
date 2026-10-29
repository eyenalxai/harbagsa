#+vet explicit-allocators
package main

import "core:log"
import "core:os"
import "core:time"

import "src:frame"
import "src:game"
import "src:input"
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
	repro_dir, repro_dir_ok := repro_directory(os.args[1:])
	if !repro_dir_ok {
		return false
	}

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

	loop: Loop
	defer frame.scratch_destroy(&loop.scratch)
	loop.sim = game.simulation_create(context.allocator)
	if !game.simulation_is_valid(&loop.sim) {
		log.error("harbagsa: simulation init failed")
		return false
	}
	defer game.simulation_destroy(&loop.sim)
	loop.debug = game.debug_mode_create(context.allocator)
	defer game.debug_mode_destroy(&loop.debug)
	loop.renderer = &state
	loop.repro_dir = repro_dir
	loop.displays = platform.query_displays()
	if loop.displays.list.count == 0 {
		log.warn("harbagsa: SDL reported no displays; keeping the created window")
	}
	loop.sim.settings.display = loop.displays.list
	initial_display := platform.display_index_for_window(&window, &loop.displays)
	if initial_display >= 0 {
		loop.sim.settings.window.display = initial_display
	} else {
		log.warn("harbagsa: the launch display is not in the display list")
	}
	loop.applied_window = loop.sim.settings.window
	if initial_display >= 0 &&
	   !platform.apply_window_state(&window, &loop.displays, loop.applied_window) {
		log.warn("harbagsa: the initial window settings were not applied")
	}
	renderer.notify_resize(&state)
	last_time := time.now()

	for {
		perf.begin_frame(&perf_state)
		events := platform.poll_events(&window)
		if events.quit {
			return true
		}
		if events.resized {
			renderer.notify_resize(&state)
		}

		focus := input.Focus {
			game = game.focus(&loop.debug, &loop.hud.menu),
			captured = events.captured,
			pointer_available = loop.cursor.pointer_available,
		}
		hit: input.Palette_Hit
		if focus.game.tool == .Palette && loop.cursor.pointer_available {
			palette_hit := renderer.palette_hit_test(&state, events.pointer, game.PREFAB_COUNT)
			hit = {inside = palette_hit.inside, card = palette_hit.card}
		}
		intent := input.resolve(&loop.resolver, events, focus, hit)

		apply_frame_input(&loop, &window, &events, intent)
		sync_window(&loop, &window)
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

		step_simulation(&loop, delta, &intent)

		if loop.hud.perf.visible {
			loop.hud.perf.stats = perf.stats(&perf_state)
		}

		alpha := clamp(loop.accumulator / game.SIMULATION_STEP, 0, 1)
		static := game.simulation_bake_input(&loop.sim, &loop.scratch.bake, context.allocator)
		renderer.refresh_bake(&state, static)
		scene := frame.build(
			&loop.sim,
			&loop.debug,
			frame.Options {
				alpha = alpha,
				delta_seconds = delta,
				debug_view = loop.debug_view,
				captured = events.captured,
				hud = true,
				perf = loop.hud.perf.visible,
				bake = renderer.bake_report(&state),
			},
			nil,
			&loop.hud,
			&loop.scratch,
			static,
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
