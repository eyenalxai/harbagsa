#+vet explicit-allocators
package appframe

import "core:log"

import "src:display"
import "src:frame"
import "src:game"
import "src:input"
import "src:perf"
import "src:platform"
import rnd "src:renderer"
import "src:uiaction"

MAX_STEPS_PER_FRAME :: 8
MAX_FRAME_ACTIONS :: 64

// Hooks are the live window's side effects. The harness passes none: it has no
// window, cursor, or repro directory.
Hooks :: struct {
	user:         rawptr,
	apply_window: proc(user: rawptr, previous: display.Window_Settings),
	sync_cursor:  proc(user: rawptr, pointer_free: bool, captured: bool),
	write_repro:  proc(app: ^State, user: rawptr),
}

// The window loop and the harness share this frame state.
State :: struct {
	runtime:        frame.Runtime,
	renderer:       ^rnd.Renderer,
	resolver:       input.Resolver,
	accumulator:    f32,
	last_alpha:     f32,
	captured:       bool,
	ui_events:      UI_Event_Buffer,
	routed:         input.Routed_Frame,
	has_routed:     bool,
	actions:        [MAX_FRAME_ACTIONS]rnd.Ui_Action,
	action_applied: [MAX_FRAME_ACTIONS]bool,
	action_reason:  [MAX_FRAME_ACTIONS]game.Edit_Reason,
	action_count:   int,
}

// The resolved intent comes from the route, never from the caller.
Input :: struct {
	events: platform.Events,
	delta:  f32,
	steps:  int,
}

// The draw inputs that are not input events.
Options :: struct {
	alpha:      f32,
	debug_view: bool,
	fx_view:    bool,
	hud:        bool,
	capture:    rnd.Frame_Capture,
	perf:       ^perf.State,
	// Land running UI tracks on this frame. The harness sets it for the last
	// frame of a recipe; the live loop never does.
	settle_ui: bool,
	// Step the simulation without composing or drawing. The harness draws a
	// due capture as its own group instead.
	skip_draw: bool,
}

// pace adds one frame's delta and resolves the fixed steps that are due. A menu
// owns the accumulator, so a paused frame neither steps nor banks the pause.
pace :: proc(app: ^State, delta: f32) -> int {
	if app.runtime.hud.menu.open {
		return 0
	}
	app.accumulator += delta
	steps := 0
	for app.accumulator >= game.SIMULATION_STEP && steps < MAX_STEPS_PER_FRAME {
		app.accumulator -= game.SIMULATION_STEP
		steps += 1
	}
	if steps == MAX_STEPS_PER_FRAME && app.accumulator >= game.SIMULATION_STEP {
		// Drop a backlog that cannot drain.
		app.accumulator = 0
	}
	return steps
}

alpha :: proc(app: ^State) -> f32 {
	return clamp(app.accumulator / game.SIMULATION_STEP, 0, 1)
}

// run is the one frame path. It routes the raw events to exactly one sink,
// applies the frame's game intent, steps, composes, draws, and applies the UI
// action queue that the draw emitted.
run :: proc(app: ^State, frame_input: Input, options: Options, hooks: Hooks) -> rnd.Frame_Result {
	if frame_input.events.resized && app.renderer != nil {
		rnd.notify_resize(app.renderer)
	}

	focus := game.focus(&app.runtime.debug, &app.runtime.hud.menu)
	app.routed = input.route(&app.resolver, frame_input.events, focus)
	app.has_routed = true
	app.captured = frame_input.events.captured
	apply_frame_input(app, app.routed.game, hooks)
	if options.perf != nil {
		perf.mark(options.perf, .Events)
	}

	// Look is per frame and does not need a fixed step. Action edges are latched
	// so a press survives a frame with no step.
	if !app.runtime.hud.menu.open && !app.runtime.debug.active {
		game.simulation_look(&app.runtime.sim, app.routed.game.look_delta)
	}
	frame.runtime_step(&app.runtime, frame.Frame_Step {
		fixed_steps = frame_input.steps,
		delta = frame_input.delta,
		snapshot = app.routed.game.snapshot,
		motion = app.routed.game.motion,
		actions = app.routed.game.actions[:app.routed.game.action_count],
	})
	if !app.runtime.debug.active && frame_input.steps > 0 {
		input.clear_latches(&app.resolver)
	}
	if options.perf != nil {
		perf.mark(options.perf, .Simulation)
	}

	app.last_alpha = options.alpha
	app.action_count = 0
	if options.skip_draw || app.renderer == nil {
		return {status = .Ok, slot = -1}
	}

	ui_events := build_ui_events(
		app.routed.ui_events[:app.routed.ui_event_count],
		&app.ui_events,
	)
	scene := compose(app, options, frame_input.delta, ui_events)
	if options.perf != nil {
		perf.mark(options.perf, .Build)
	}
	if options.settle_ui {
		rnd.ui_settle()
	}
	result := rnd.render_frame(app.renderer, scene, options.capture)
	apply_ui_actions(app, hooks)
	rnd.ui_actions_clear()

	// Capture follows the surface that is open after this frame's actions, so an
	// opening or closing surface takes effect before the next frame.
	end_focus := game.focus(&app.runtime.debug, &app.runtime.hud.menu)
	if hooks.sync_cursor != nil {
		hooks.sync_cursor(hooks.user, end_focus.pointer_free, app.captured)
	}
	return result
}

// compose builds one frame's scene. `run` passes the batch the route produced;
// the harness pick passes none, because a pick draws a query frame, not an input
// frame.
compose :: proc(
	app: ^State,
	options: Options,
	delta: f32,
	ui_events: []rnd.UI_Event,
) -> rnd.Render_Input {
	static := game.simulation_bake_input(
		&app.runtime.sim,
		&app.runtime.scratch.bake,
		app.runtime.allocator,
	)
	bake := rnd.Bake_Report{}
	if app.renderer != nil {
		rnd.refresh_bake(app.renderer, static)
		bake = rnd.bake_report(app.renderer)
		if options.perf != nil {
			app.renderer.recorder = &options.perf.recorder
		}
	}
	return frame.runtime_compose(
		&app.runtime,
		frame.Options {
			alpha = options.alpha,
			delta_seconds = delta,
			debug_view = options.debug_view,
			fx_view = options.fx_view,
			captured = app.captured,
			hud = options.hud,
			bake = bake,
			ui_events = ui_events,
		},
		nil,
		static,
	)
}

@(private)
apply_frame_input :: proc(app: ^State, intent: input.Frame_Input, hooks: Hooks) {
	// The engine opens the menu. Rune owns closing it through Close_Menu, so a
	// game menu-toggle never closes an open dialog.
	if intent.view.menu_toggle && !app.runtime.hud.menu.open {
		game.debug_mode_open_menu(&app.runtime.debug, &app.runtime.hud.menu)
		app.accumulator = game.SIMULATION_STEP
		input.clear_latches(&app.resolver)
		game.menu_view(&app.runtime.hud.menu, app.runtime.debug.active, 0)
	}

	if app.runtime.hud.menu.open {
		return
	}
	if intent.view.debug_view {
		app.runtime.debug.physics_debug = !app.runtime.debug.physics_debug
	}
	if intent.view.debug_mode {
		game.debug_mode_toggle(&app.runtime.debug, &app.runtime.sim)
		input.clear_latches(&app.resolver)
	}
	if intent.view.taa && app.renderer != nil {
		rnd.toggle_taa(app.renderer)
	}
	if intent.view.repro && hooks.write_repro != nil {
		hooks.write_repro(app, hooks.user)
	}
	if intent.view.reset_scene {
		game.debug_mode_reset_scene(&app.runtime.debug, &app.runtime.sim)
		if app.renderer != nil {
			rnd.reset_history(app.renderer, .Scene_Reset)
		}
		input.clear_latches(&app.resolver)
	} else if intent.view.reset_player {
		game.debug_mode_reset_player(&app.runtime.debug, &app.runtime.sim)
		if app.renderer != nil {
			rnd.reset_history(app.renderer, .Player_Reset)
		}
		input.clear_latches(&app.resolver)
	}
}

@(private)
apply_ui_actions :: proc(app: ^State, hooks: Hooks) {
	ui_context := uiaction.Context {
		sim      = &app.runtime.sim,
		debug    = &app.runtime.debug,
		menu     = &app.runtime.hud.menu,
		captured = app.captured,
	}
	for action in rnd.ui_actions_slice() {
		previous_window := app.runtime.sim.settings.window
		applied := uiaction.apply(ui_context, action)
		if !applied.handled {
			log.warnf("appframe: unknown UI action kind %d", action.kind)
		}
		if app.action_count < len(app.actions) {
			index := app.action_count
			app.actions[index] = action
			app.action_applied[index] = applied.applied
			app.action_reason[index] = applied.reason
			app.action_count += 1
		}
		if applied.window_changed && hooks.apply_window != nil {
			hooks.apply_window(hooks.user, previous_window)
		}
		if applied.closed_menu {
			app.accumulator = 0
		}
	}
}
