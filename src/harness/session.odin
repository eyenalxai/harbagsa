#+vet explicit-allocators
package harness

import "core:fmt"
import "core:mem"
import "core:strings"

import "src:frame"
import "src:game"
import "src:renderer"

View :: struct {
	hud:   bool,
	debug: bool,
	hint:  bool,
}

Pending_Capture :: struct {
	name:  string,
	frame: int,
	alpha: f32,
}

Backend :: struct {
	ready:    bool,
	ctx:      rawptr,
	render:   proc(
		ctx: rawptr,
		session: ^Session,
		capture: bool,
		name: string,
		alpha: f32,
	) -> (Capture_Result, string),
	shutdown: proc(ctx: rawptr),
}

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

	backend:       ^Backend,
	present:       bool,
	render_failed: bool,

	pending:  [dynamic]Pending_Capture,
	captures: [dynamic]Capture_Result,
	checks:   [dynamic]Check_Result,
	failures: [dynamic]string,

	quit: bool,

	recording:          bool,
	record_path:        string,
	record_start_frame: int,
	recorded:           [dynamic]string,
}

session_create :: proc(allocator: mem.Allocator) -> (Session, string) {
	session := Session {
		allocator = allocator,
		alpha = 1.0,
		debug = game.debug_mode_create(),
	}
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

@(private)
session_finish_frame :: proc(session: ^Session) -> string {
	due := make([dynamic]int, 0, 4, context.temp_allocator)
	defer delete(due)
	for pending, index in session.pending {
		if pending.frame <= session.frame {
			append(&due, index)
		}
	}
	if session.present && len(due) == 0 {
		return session_draw(session, false, "", session.alpha)
	}
	render_error := ""
	for index in due {
		pending := session.pending[index]
		error := session_draw(session, true, pending.name, pending.alpha)
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
session_draw :: proc(session: ^Session, capture: bool, name: string, alpha: f32) -> string {
	if session.backend == nil {
		if capture {
			return format_error("capture requires rendering")
		}
		return ""
	}
	result, error := session.backend.render(session.backend.ctx, session, capture, name, alpha)
	if error != "" {
		session.render_failed = true
		session_failure(session, error)
		return error
	}
	if capture {
		append(&session.captures, result)
	}
	return ""
}

session_state :: proc(session: ^Session) -> State {
	return state_build(&session.sim, session.frame, &session.hud.menu, session.allocator)
}

session_queue_capture :: proc(
	session: ^Session,
	command: Capture_Command,
) -> (
	immediate: bool,
	error: string,
) {
	frame := command.has_frame ? command.frame : session.frame
	if frame < session.frame {
		return false, fmt.aprintf(
			"capture frame %d is in the past (current frame %d)",
			frame,
			session.frame,
			allocator = context.allocator,
		)
	}
	name := command.name
	owned_name := false
	if name == "" {
		name = capture_name(frame, session.allocator)
		owned_name = true
	}
	defer if owned_name {
		delete(name, session.allocator)
	}
	alpha := command.has_alpha ? command.alpha : session.alpha
	if frame == session.frame {
		return true, session_draw(session, true, name, alpha)
	}
	append(
		&session.pending,
		Pending_Capture{name = strings.clone(name, session.allocator), frame = frame, alpha = alpha},
	)
	return false, ""
}

@(private)
ordered_remove :: proc(array: ^[dynamic]Pending_Capture, index: int) {
	for next in index ..< len(array^) - 1 {
		array[next] = array[next + 1]
	}
	resize(array, len(array^) - 1)
}
