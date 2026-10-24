#+vet explicit-allocators
package harness

import "core:fmt"
import "core:mem"
import "core:strings"

import "src:digest"
import "src:display"
import "src:frame"
import "src:game"
import perf_pkg "src:perf"
import "src:renderer"

Session :: struct {
	allocator: mem.Allocator,

	sim:      game.Simulation,
	debug:    game.Debug_Mode,
	hud:      game.HUD_State,
	scratch:  frame.Scratch,
	input:    game.Input_Snapshot,
	view:     View,
	alpha:    f32,

	camera_override:     renderer.Camera,
	has_camera_override: bool,

	frame: int,

	backend:           ^Backend,
	present:           bool,
	render_every_step: bool,
	render_failed:     bool,

	renderer_report:   renderer.Renderer_Report,
	render_digest:     digest.FNV,
	has_render_digest: bool,
	render_digest_text: string,

	pending:  [dynamic]Pending_Capture,
	captures: [dynamic]Capture_Result,
	checks:   [dynamic]Check_Result,
	failures: [dynamic]string,

	quit: bool,

	recording:          bool,
	record_path:        string,
	record_start_frame: int,
	recorded:           [dynamic]string,

	perf:            perf_pkg.State,
	perf_report:     Perf_Report,
	has_perf_report: bool,
	trace_name:      string,
	trace_samples:   [dynamic]perf_pkg.Sample,
	trace_path:      string,
	has_trace:       bool,

	debug_renderer: bool,

	analysis_config: Analysis_Config,
	analysis:        Analysis_Summary,
	has_analysis:    bool,
}

session_create :: proc(allocator: mem.Allocator) -> (Session, string) {
	session := Session {
		allocator = allocator,
		alpha = 1.0,
		debug = game.debug_mode_create(),
		analysis_config = analysis_config_default(),
	}
	session.hud.menu.displays = display.fallback_list()
	session.sim = game.simulation_create()
	if !game.simulation_is_valid(&session.sim) {
		return {}, "simulation init failed"
	}
	session.pending = make([dynamic]Pending_Capture, 0, 8, allocator)
	session.captures = make([dynamic]Capture_Result, 0, 8, allocator)
	session.checks = make([dynamic]Check_Result, 0, 8, allocator)
	session.failures = make([dynamic]string, 0, 8, allocator)
	session.recorded = make([dynamic]string, 0, 16, allocator)
	return session, ""
}

session_destroy :: proc(session: ^Session) {
	if game.simulation_is_valid(&session.sim) {
		game.simulation_destroy(&session.sim)
	}
	for pending in session.pending {
		delete(pending.name, session.allocator)
	}
	delete(session.pending)
	for &capture in session.captures {
		capture_result_destroy(&capture, session.allocator)
	}
	delete(session.captures)
	for &check in session.checks {
		check_result_destroy(&check, session.allocator)
	}
	delete(session.checks)
	for failure in session.failures {
		delete(failure, session.allocator)
	}
	delete(session.failures)
	for line in session.recorded {
		delete(line, session.allocator)
	}
	delete(session.recorded)
	if session.record_path != "" {
		delete(session.record_path, session.allocator)
	}
	if session.trace_name != "" {
		delete(session.trace_name, session.allocator)
	}
	if session.trace_path != "" {
		delete(session.trace_path, session.allocator)
	}
	if session.render_digest_text != "" {
		delete(session.render_digest_text, session.allocator)
	}
	delete(session.trace_samples)
	session^ = {}
}

session_set_backend :: proc(session: ^Session, backend: ^Backend, present: bool) {
	session.backend = backend
	session.present = present
}

session_reset :: proc(session: ^Session) -> string {
	game.menu_reset(&session.hud.menu)
	if game.simulation_is_valid(&session.sim) {
		game.simulation_destroy(&session.sim)
	}
	session.sim = game.simulation_create()
	if !game.simulation_is_valid(&session.sim) {
		return "simulation init failed"
	}
	session.input = {}
	session.camera_override = {}
	session.has_camera_override = false
	// The debug mode holds a saved player from the world that just went away.
	session.debug = game.debug_mode_create()
	return ""
}

session_restart :: proc(session: ^Session) -> string {
	for pending in session.pending {
		delete(pending.name, session.allocator)
	}
	clear(&session.pending)
	session.frame = 0
	session.view = {}
	session.alpha = 1.0
	return session_reset(session)
}

session_failure :: proc(session: ^Session, message: string) {
	append(&session.failures, strings.clone(message, session.allocator))
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
		input := session.input
		if index > 0 {
			input.jump_pressed = false
		}
		game.simulation_step(&session.sim, input, game.SIMULATION_STEP)
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

// Settle renders every step without writing a screenshot, so a scenario can
// reach a steady temporal state before it starts capturing.
session_settle :: proc(session: ^Session, frames: int) -> string {
	session.render_every_step = true
	defer session.render_every_step = false
	return session_step(session, frames)
}

@(private)
session_finish_frame :: proc(session: ^Session) -> string {
	due := make([dynamic]int, 0, 4, context.temp_allocator)
	defer delete(due)
	for pending, index in session.pending {
		if pending.frame <= session.frame {
			append(&due, index)
		}
	}
	if (session.present || session.render_every_step) && len(due) == 0 {
		return session_draw(session, {})
	}
	render_error := ""
	for index in due {
		pending := session.pending[index]
		request := Capture_Request {
			name    = pending.name,
			alpha   = pending.alpha,
			target  = pending.target,
			format  = pending.format,
			enabled = true,
		}
		error := session_draw(session, request)
		if error != "" && render_error == "" {
			render_error = error
		}
	}
	for cursor := len(due) - 1; cursor >= 0; cursor -= 1 {
		index := due[cursor]
		delete(session.pending[index].name, session.allocator)
		ordered_remove(&session.pending, index)
	}
	return render_error
}

@(private)
session_draw :: proc(session: ^Session, request: Capture_Request) -> string {
	if session.backend == nil {
		if request.enabled {
			return format_error("capture requires rendering")
		}
		return ""
	}
	result, error := session.backend.render(session.backend.ctx, session, request)
	if error != "" {
		session.render_failed = true
		session_failure(session, error)
		return error
	}
	if request.enabled {
		append(&session.captures, result)
		session_refresh_analysis(session)
	}
	session_refresh_renderer(session)
	return ""
}
