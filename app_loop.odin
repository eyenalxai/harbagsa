#+vet explicit-allocators
package main

import "core:log"

import "src:display"
import "src:frame"
import "src:game"
import "src:input"
import "src:platform"
import "src:renderer"
import "src:ui"

// Loop is the mutable state of the window loop. main owns the lifetime; the
// loop module owns the phases.
Loop :: struct {
	sim:            game.Simulation,
	debug:          game.Debug_Mode,
	hud:            game.HUD_State,
	scratch:        frame.Scratch,
	renderer:       ^renderer.Renderer,
	resolver:       input.Resolver,
	cursor:         Cursor_State,
	accumulator:    f32,
	debug_view:     bool,
	menu_recapture: bool,
	displays:       platform.Displays,
	applied_window: display.Window_Settings,
}

@(private)
apply_frame_input :: proc(
	loop: ^Loop,
	window: ^platform.Window,
	events: ^platform.Events,
	intent: input.Frame_Input,
) {
	if intent.view.perf {
		loop.hud.perf.visible = !loop.hud.perf.visible
	}

	// The menu owns the cursor and the accumulator while it is open.
	if intent.view.menu_toggle {
		if loop.hud.menu.open {
			events.captured = close_settings_menu(window, &loop.hud.menu, loop.menu_recapture)
			loop.accumulator = 0
		} else {
			loop.menu_recapture = events.captured
			events.captured = open_settings_menu(window, &loop.hud.menu, &loop.debug)
			loop.accumulator = game.SIMULATION_STEP
			input.clear_latches(&loop.resolver)
			game.menu_view(&loop.hud.menu, loop.sim.settings, loop.debug.active, 0)
		}
	}

	if !loop.hud.menu.open {
		if intent.view.debug_view {
			loop.debug_view = !loop.debug_view
		}
		if intent.view.debug_mode {
			game.debug_mode_toggle(&loop.debug, &loop.sim)
			input.clear_latches(&loop.resolver)
		}
		if intent.view.taa {
			renderer.toggle_taa(loop.renderer)
		}
		if intent.view.repro {
			_ = write_repro(
				&loop.sim,
				&loop.debug,
				&loop.hud,
				frame.Options {
					debug_view = loop.debug_view,
					captured = events.captured,
					hud = true,
					perf = loop.hud.perf.visible,
				},
			)
		}
		if intent.view.reset_scene {
			game.debug_mode_reset_scene(&loop.debug, &loop.sim)
			renderer.reset_history(loop.renderer, .Scene_Reset)
			input.clear_latches(&loop.resolver)
		} else if intent.view.reset_player {
			game.debug_mode_reset_player(&loop.debug, &loop.sim)
			renderer.reset_history(loop.renderer, .Player_Reset)
			input.clear_latches(&loop.resolver)
		}
	}

	sync_palette_cursor(
		window,
		loop.debug.active,
		loop.hud.menu.open,
		intent.want_cursor_free,
		&loop.cursor,
	)

	if loop.hud.menu.open {
		layout := renderer.menu_layout_for(loop.renderer, loop.hud.menu.view)
		target_width, target_height := renderer.target_extent(loop.renderer)
		pointer := ui.pointer_to_target(
			intent.menu.pointer,
			f32(target_width),
			f32(target_height),
		)
		if apply_menu_input(&loop.hud.menu, &loop.sim.settings, intent.menu, layout.slider, pointer) {
			events.captured = close_settings_menu(window, &loop.hud.menu, loop.menu_recapture)
			loop.accumulator = 0
		}
	}
}

@(private)
sync_window :: proc(loop: ^Loop, window: ^platform.Window) {
	if loop.sim.settings.window == loop.applied_window {
		return
	}
	if platform.apply_window_state(window, &loop.displays, loop.sim.settings.window) {
		loop.applied_window = loop.sim.settings.window
	} else {
		log.warn("harbagsa: the window settings were not applied")
		loop.sim.settings.window = loop.applied_window
	}
	renderer.notify_resize(loop.renderer)
}

@(private)
step_simulation :: proc(loop: ^Loop, delta: f32, intent: ^input.Frame_Input) {
	frame := intent^
	// Look is per frame. Action edges are latched so a press survives a frame
	// with no step.
	if !loop.hud.menu.open && !loop.debug.active {
		game.simulation_look(&loop.sim, frame.look_delta)
	}

	if !loop.hud.menu.open {
		loop.accumulator += delta
		steps := 0
		snapshot := frame.snapshot
		for loop.accumulator >= game.SIMULATION_STEP && steps < MAX_STEPS_PER_FRAME {
			if loop.debug.active {
				game.simulation_step_world(&loop.sim, game.SIMULATION_STEP)
			} else {
				game.simulation_step(&loop.sim, snapshot, game.SIMULATION_STEP)
				input.clear_latches(&loop.resolver)
				snapshot.jump_pressed = false
				snapshot.sprint_pressed = false
				snapshot.crouch_pressed = false
				snapshot.prone_pressed = false
			}
			loop.accumulator -= game.SIMULATION_STEP
			steps += 1
		}
		if steps == MAX_STEPS_PER_FRAME && loop.accumulator >= game.SIMULATION_STEP {
			// Drop a backlog that cannot drain.
			loop.accumulator = 0
		}
	}

	// Edit after the fixed steps so a dragged transform is the one rendered.
	if loop.debug.active && !loop.hud.menu.open {
		game.debug_mode_update(
			&loop.debug,
			&loop.sim,
			frame.motion,
			frame.actions[:frame.action_count],
			loop.hud.menu.open,
			delta,
		)
	}
}
