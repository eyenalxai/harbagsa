#+vet explicit-allocators
package main

import "core:log"

import "src:display"
import "src:frame"
import "src:game"
import "src:input"
import "src:perf"
import "src:platform"
import "src:renderer"
import "src:ui"

// Loop is the mutable state of the window loop. main owns the lifetime; the
// loop module owns the phases.
Loop :: struct {
	runtime:        frame.Runtime,
	renderer:       ^renderer.Renderer,
	resolver:       input.Resolver,
	cursor:         Cursor_State,
	accumulator:    f32,
	last_alpha:     f32, // the last built frame; the repro path runs before this frame's alpha
	debug_view:     bool,
	perf_visible:   bool,
	displays:       platform.Displays,
	repro_dir:      string,
}

@(private)
apply_frame_input :: proc(
	loop: ^Loop,
	window: ^platform.Window,
	events: ^platform.Events,
	intent: input.Frame_Input,
) {
	if intent.view.perf {
		loop.perf_visible = !loop.perf_visible
	}

	// The menu owns the accumulator while it is open. The cursor sync reads the
	// menu after the edit actions.
	if intent.view.menu_toggle {
		if loop.runtime.hud.menu.open {
			game.menu_close(&loop.runtime.hud.menu)
			loop.accumulator = 0
		} else {
			game.menu_open(&loop.runtime.hud.menu)
			game.debug_mode_cancel_editing(&loop.runtime.debug)
			loop.accumulator = game.SIMULATION_STEP
			input.clear_latches(&loop.resolver)
			game.menu_view(&loop.runtime.hud.menu, &loop.runtime.sim.settings, loop.runtime.debug.active, 0)
		}
	}

	if !loop.runtime.hud.menu.open {
		if intent.view.debug_view {
			loop.debug_view = !loop.debug_view
		}
		if intent.view.debug_mode {
			game.debug_mode_toggle(&loop.runtime.debug, &loop.runtime.sim)
			input.clear_latches(&loop.resolver)
		}
		if intent.view.taa {
			renderer.toggle_taa(loop.renderer)
		}
		if intent.view.repro {
			renderer_debug := renderer.renderer_debug(loop.renderer)
			perf_stats: Maybe(perf.Stats)
			if loop.perf_visible {
				perf_stats = perf.Stats{}
			}
			_ = write_repro(
				&loop.runtime.sim,
				&loop.runtime.debug,
				&loop.runtime.hud,
				frame.Options {
					alpha = loop.last_alpha,
					debug_view = loop.debug_view,
					captured = events.captured,
					hud = true,
					perf_stats = perf_stats,
				},
				&renderer_debug,
				loop.repro_dir,
			)
		}
		if intent.view.reset_scene {
			game.debug_mode_reset_scene(&loop.runtime.debug, &loop.runtime.sim)
			renderer.reset_history(loop.renderer, .Scene_Reset)
			input.clear_latches(&loop.resolver)
		} else if intent.view.reset_player {
			game.debug_mode_reset_player(&loop.runtime.debug, &loop.runtime.sim)
			renderer.reset_history(loop.renderer, .Player_Reset)
			input.clear_latches(&loop.resolver)
		}
	}

	if loop.runtime.hud.menu.open {
		layout := renderer.menu_layout_for(loop.renderer, loop.runtime.hud.menu.view)
		target_width, target_height := renderer.target_extent(loop.renderer)
		pointer := ui.pointer_to_target(
			intent.menu.pointer,
			f32(target_width),
			f32(target_height),
		)
		previous_window := loop.runtime.sim.settings.window
		if apply_menu_input(
			&loop.runtime.hud.menu,
			&loop.runtime.sim.settings,
			intent.menu,
			layout.slider,
			pointer,
		) {
			game.menu_close(&loop.runtime.hud.menu)
			loop.accumulator = 0
		}
		if loop.runtime.sim.settings.window != previous_window {
			apply_window_settings(loop, window, previous_window)
		}
	}
}

@(private)
apply_window_settings :: proc(
	loop: ^Loop,
	window: ^platform.Window,
	previous: display.Window_Settings,
) {
	result := platform.apply_window_state(window, &loop.displays, loop.runtime.sim.settings.window)
	if result == .Applied {
		renderer.notify_resize(loop.renderer)
		return
	}
	loop.runtime.sim.settings.window = previous
	restore := platform.apply_window_state(window, &loop.displays, previous)
	restored := restore == .Applied
	if restored {
		renderer.notify_resize(loop.renderer)
	} else {
		log.warnf(
			"harbagsa: the previous window settings were not restored: %s",
			platform.window_apply_name(restore),
		)
	}
	game.menu_window_apply_failed(&loop.runtime.hud.menu, platform.window_apply_name(result), restored)
}
