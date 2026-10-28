#+vet explicit-allocators
package harness

import "core:fmt"
import "core:mem"
import "core:strings"
import "core:time"

import "src:display"
import "src:frame"
import "src:game"
import "src:renderer"

Session :: struct {
	allocator: mem.Allocator,
	sim:       game.Simulation,
	debug:     game.Debug_Mode,
	hud:       game.HUD_State,
	scratch:   ^frame.Scratch,
	input:     game.Input_Snapshot,
	view:      View,
	alpha:     f32,

	camera_override:     renderer.Camera,
	has_camera_override: bool,

	frame:      int,
	output_dir: string,

	capture:  Capture_Run,
	recorder: Recorder,
	perf:     Perf_Run,
	settle:   Settle,
	render:   Render_State,

	failures: [dynamic]string,

	quit: bool,

	has_timeout:     bool,
	timeout_start:   time.Tick,
	timeout:         time.Duration,
	timeout_seconds: f64,

	debug_renderer: bool,
}

session_create :: proc(allocator: mem.Allocator) -> (Session, string) {
	session := Session {
		allocator = allocator,
		alpha = 1.0,
		debug = game.debug_mode_create(allocator),
		render = render_state_create(),
	}
	// The scratch holds the frame's debug lines, so it is too large for a local
	// Session on the stack.
	session.scratch = new(frame.Scratch, allocator)
	session.scratch.allocator = allocator
	session.sim = game.simulation_create(session.allocator)
	if !game.simulation_is_valid(&session.sim) {
		game.debug_mode_destroy(&session.debug)
		free(session.scratch, allocator)
		return {}, format_error("%s", "simulation init failed")
	}
	session.sim.settings.display = display.fallback_list()
	session.capture = capture_run_create(allocator)
	session.recorder = recorder_create(allocator)
	session.perf = perf_run_create(allocator)
	session.failures = make([dynamic]string, 0, 8, allocator)
	return session, ""
}

@(private)
session_results_destroy :: proc(session: ^Session) {
	for failure in session.failures {
		delete(failure, session.allocator)
	}
	delete(session.failures)
}

session_destroy :: proc(session: ^Session) {
	game.debug_mode_destroy(&session.debug)
	if game.simulation_is_valid(&session.sim) {
		game.simulation_destroy(&session.sim)
	}
	session_results_destroy(session)
	capture_run_destroy(&session.capture, session.allocator)
	recorder_destroy(&session.recorder, session.allocator)
	perf_run_destroy(&session.perf, session.allocator)
	render_state_destroy(&session.render, session.allocator)
	frame.scratch_destroy(session.scratch)
	free(session.scratch, session.allocator)
	session^ = {}
}

session_set_backend :: proc(session: ^Session, backend: ^Backend, present: bool) {
	session.render.backend = backend
	session.render.present = present
}

session_reset :: proc(session: ^Session) -> string {
	game.menu_reset(&session.hud.menu)
	displays := session.sim.settings.display
	if game.simulation_is_valid(&session.sim) {
		game.simulation_destroy(&session.sim)
	}
	session.sim = game.simulation_create(session.allocator)
	if !game.simulation_is_valid(&session.sim) {
		return format_error("%s", "simulation init failed")
	}
	session.sim.settings.display = displays
	session.input = {}
	session.camera_override = {}
	session.has_camera_override = false
	session.settle.frames = 0
	session.settle.converged = false
	// The debug mode holds a saved player from the world that just went away.
	game.debug_mode_destroy(&session.debug)
	session.debug = game.debug_mode_create(session.allocator)
	return ""
}

session_restart :: proc(session: ^Session) -> string {
	capture_run_clear_pending(&session.capture, session.allocator)
	session.frame = 0
	session.view = {}
	session.alpha = 1.0
	return session_reset(session)
}
session_failure :: proc(session: ^Session, message: string) {
	append(&session.failures, strings.clone(message, session.allocator))
}

session_set_timeout :: proc(session: ^Session, seconds: f64) {
	if seconds <= 0 {
		return
	}
	session.has_timeout = true
	session.timeout_start = time.tick_now()
	session.timeout_seconds = seconds
	session.timeout = time.Duration(seconds * f64(time.Second))
}

session_check_timeout :: proc(session: ^Session) -> string {
	if !session.has_timeout {
		return ""
	}
	if time.tick_since(session.timeout_start) < session.timeout {
		return ""
	}
	return fmt.aprintf(
		"run timed out after %g seconds",
		session.timeout_seconds,
		allocator = context.allocator,
	)
}
session_apply_input :: proc(session: ^Session, command: Input_Command) {
	if command.has_forward {
		session.input.move_forward = command.forward
	}
	if command.has_right {
		session.input.move_right = command.right
	}
	if command.has_jump {
		session.input.jump_pressed = command.jump
	}
	if command.has_sprint {
		session.input.sprint_held = command.sprint
		session.input.sprint_pressed = command.sprint
	}
}
session_step :: proc(session: ^Session, frames: int) -> string {
	if frames < 1 || frames > MAX_STEP_FRAMES {
		return fmt.aprintf(
			"frames must be in [1, %d]",
			MAX_STEP_FRAMES,
			allocator = context.allocator,
		)
	}
	if session.hud.menu.open {
		return fmt.aprintf("menu is open; close the menu to step", allocator = context.allocator)
	}
	for index in 0 ..< frames {
		if timeout := session_check_timeout(session); timeout != "" {
			return timeout
		}
		input := session.input
		if index > 0 {
			input.jump_pressed = false
			input.sprint_pressed = false
		}
		if session.debug.active {
			game.simulation_step_world(&session.sim, game.SIMULATION_STEP)
		} else {
			game.simulation_step(&session.sim, input, game.SIMULATION_STEP)
		}
		game.hud_notice_update(&session.hud, game.SIMULATION_STEP)
		session.input.jump_pressed = false
		session.frame += 1
		if render_error := session_finish_frame(session); render_error != "" {
			return render_error
		}
		if session.quit {
			break
		}
	}
	return ""
}

@(private)
session_ensure_backend :: proc(session: ^Session) -> string {
	if session.render.backend != nil && session.render.backend.ready {
		return ""
	}
	if session.render.provider.ensure == nil {
		return ""
	}
	return session.render.provider.ensure(session.render.provider.ctx)
}
