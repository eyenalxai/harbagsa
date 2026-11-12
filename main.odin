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
	loop.last_alpha = 1.0
	loop.runtime = frame.runtime_create(context.allocator)
	defer frame.runtime_destroy(&loop.runtime)
	if !frame.runtime_is_valid(&loop.runtime) {
		log.error("harbagsa: simulation init failed")
		return false
	}
	loop.renderer = &state
	loop.repro_dir = repro_dir
	loop.displays = platform.query_displays()
	if loop.displays.list.count == 0 {
		log.warn("harbagsa: SDL reported no displays; keeping the created window")
	}
	loop.runtime.sim.settings.display = loop.displays.list
	initial_display := platform.display_index_for_window(&window, &loop.displays)
	if initial_display >= 0 {
		loop.runtime.sim.settings.window.display = initial_display
		result := platform.apply_window_state(
			&window,
			&loop.displays,
			loop.runtime.sim.settings.window,
		)
		if result != .Applied {
			log.warnf(
				"harbagsa: the initial window settings were not applied: %s",
				platform.window_apply_name(result),
			)
			game.hud_notice_window_failed(&loop.runtime.hud, platform.window_apply_name(result))
		}
	} else {
		log.warn("harbagsa: the launch display is not in the display list")
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
			game = game.focus(&loop.runtime.debug, &loop.runtime.hud.menu),
			captured = events.captured,
			pointer_available = loop.cursor.pointer_available,
		}
		hit: input.Palette_Hit
		intent := input.resolve(&loop.resolver, events, focus, hit)

		apply_frame_input(&loop, &window, &events, intent)
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

		// Look is per frame. Action edges are latched so a press survives a frame
		// with no step.
		if !loop.runtime.hud.menu.open && !loop.runtime.debug.active {
			game.simulation_look(&loop.runtime.sim, intent.look_delta)
		}
		steps := 0
		if !loop.runtime.hud.menu.open {
			loop.accumulator += delta
			for loop.accumulator >= game.SIMULATION_STEP && steps < MAX_STEPS_PER_FRAME {
				loop.accumulator -= game.SIMULATION_STEP
				steps += 1
			}
			if steps == MAX_STEPS_PER_FRAME && loop.accumulator >= game.SIMULATION_STEP {
				// Drop a backlog that cannot drain.
				loop.accumulator = 0
			}
		}
		frame.runtime_step(&loop.runtime, frame.Frame_Step {
			fixed_steps = steps,
			delta = delta,
			snapshot = intent.snapshot,
			motion = intent.motion,
			actions = intent.actions[:intent.action_count],
		})
		if !loop.runtime.debug.active && steps > 0 {
			input.clear_latches(&loop.resolver)
		}
		// The edit actions above can open or close the palette, so the cursor
		// sync runs after them and sees the tool the frame applied.
		sync_cursor(
			&window,
			game.focus(&loop.runtime.debug, &loop.runtime.hud.menu),
			events.captured,
			&loop.cursor,
		)

		alpha := clamp(loop.accumulator / game.SIMULATION_STEP, 0, 1)
		loop.last_alpha = alpha
		static := game.simulation_bake_input(
			&loop.runtime.sim,
			&loop.runtime.scratch.bake,
			context.allocator,
		)
		renderer.refresh_bake(&state, static)
		perf_stats: Maybe(perf.Stats)
		if loop.perf_visible {
			perf_stats = perf.stats(&perf_state)
		}
		ui_keys: renderer.UI_KEYS
		if intent.menu.up {
			ui_keys += {.Up}
		}
		if intent.menu.down {
			ui_keys += {.Down}
		}
		if intent.menu.left {
			ui_keys += {.Left}
		}
		if intent.menu.right {
			ui_keys += {.Right}
		}
		if intent.menu.confirm {
			ui_keys += {.Confirm}
		}
		scene := frame.runtime_compose(
			&loop.runtime,
			frame.Options {
				alpha = alpha,
				delta_seconds = delta,
				debug_view = loop.debug_view,
				captured = events.captured,
				hud = true,
				perf_stats = perf_stats,
				bake = renderer.bake_report(&state),
				pointer = intent.menu.pointer,
				pointer_pressed = intent.menu.pointer_pressed,
				pointer_down = intent.menu.pointer_down,
				ui_keys = ui_keys,
			},
			nil,
			static,
		)
		perf.mark(&perf_state, .Build)

		status := frame.draw(&state, scene)
		for action in renderer.ui_actions_slice() {
			#partial switch renderer.UI_Action_Kind(action.kind) {
			case .Close_Menu:
				if loop.runtime.hud.menu.open {
					game.menu_close(&loop.runtime.hud.menu)
					loop.accumulator = 0
				}
			case .Toggle_Debug:
				loop.debug_view = !loop.debug_view
			case .Palette_Select:
				if loop.runtime.debug.active {
					_ = game.editor_apply(
						&loop.runtime.debug.editor,
						&loop.runtime.sim,
						game.Palette_Select{index = int(action.value)},
						{
							active = loop.runtime.debug.active,
							menu_open = loop.runtime.hud.menu.open,
							captured = events.captured,
							camera = loop.runtime.debug.camera,
						},
					)
				}
			}
		}
		renderer.ui_actions_clear()
		switch status {
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
