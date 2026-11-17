#+vet explicit-allocators
package harness

import "core:fmt"
import "core:mem"
import "core:strings"
import "core:time"

import "src:appframe"
import "src:display"
import "src:frame"
import "src:platform"
import "src:renderer"

Held_Input :: struct {
	move_forward: f32,
	move_right:   f32,
	sprint_held:  bool,
}

Session :: struct {
	allocator:      mem.Allocator,
	app:            appframe.State,
	held:           Held_Input,
	pending_jump:   bool,
	pending_sprint: bool,
	view:           View,
	captured:       bool,
	pointer:        [2]f32,
	pad:            platform.Gamepad_State,
	default_alpha:  f32,
	drawn_alpha:    f32,
	drawn_frame:    int,

	camera_override:     renderer.Camera,
	has_camera_override: bool,

	frame:      int,
	output_dir: string,

	capture:  Capture_Run,
	picks:    [dynamic]Pick_Result,
	recorder: Recorder,
	perf:     Perf_Run,
	settle:   Settle,
	render:   Render_State,

	ui_actions:      [dynamic]renderer.Ui_Action,
	collect_actions: bool,
	ui_tree:         []Ui_Tree_Node,
	has_ui_tree:     bool,

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
		allocator     = allocator,
		captured      = true,
		default_alpha = 1.0,
		drawn_alpha   = 1.0,
		render        = render_state_create(),
	}
	session.app.last_alpha = 1.0
	session.app.runtime = frame.runtime_create(allocator)
	if !frame.runtime_is_valid(&session.app.runtime) {
		frame.runtime_destroy(&session.app.runtime)
		return {}, format_error("%s", "simulation init failed")
	}
	session.app.runtime.sim.settings.display = display.fallback_list()
	session.capture = capture_run_create(allocator)
	session.picks = make([dynamic]Pick_Result, 0, 8, allocator)
	session.recorder = recorder_create(allocator)
	session.perf = perf_run_create(allocator)
	session.failures = make([dynamic]string, 0, 8, allocator)
	session.ui_actions = make([dynamic]renderer.Ui_Action, 0, 8, allocator)
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
	frame.runtime_destroy(&session.app.runtime)
	session_results_destroy(session)
	capture_run_destroy(&session.capture, session.allocator)
	for &pick in session.picks {
		pick_result_destroy(&pick, session.allocator)
	}
	delete(session.picks)
	recorder_destroy(&session.recorder, session.allocator)
	perf_run_destroy(&session.perf, session.allocator)
	render_state_destroy(&session.render, session.allocator)
	ui_run_destroy(session, session.allocator)
	session^ = {}
}

session_set_backend :: proc(session: ^Session, backend: ^Backend, present: bool) {
	session.render.backend = backend
	session.render.present = present
	if backend.ready && backend.acquire != nil {
		session.app.renderer = backend.acquire(backend.ctx)
	}
}

session_override_camera :: proc(session: ^Session) -> ^renderer.Camera {
	if session.has_camera_override {
		return &session.camera_override
	}
	return nil
}

// The harness view flag is a run-level override; the inspector's physics switch
// writes the runtime flag. Either one asks for the physics draw.
session_debug_view :: proc(session: ^Session) -> bool {
	return session.view.debug || session.app.runtime.debug.physics_debug
}

// The state names the frame the renderer last built. A step with no draw falls
// back to the default alpha instead of pairing a new player with an old frame.
session_view_alpha :: proc(session: ^Session) -> f32 {
	if session.drawn_frame == session.frame {
		return session.drawn_alpha
	}
	return session.default_alpha
}

session_reset :: proc(session: ^Session) -> string {
	if !frame.runtime_reset(&session.app.runtime) {
		return format_error("%s", "simulation init failed")
	}
	session.held = {}
	session.pending_jump = false
	session.pending_sprint = false
	session.captured = !session.view.hint
	session.pointer = {}
	session.pad = {}
	session.app.resolver = {}
	session.app.accumulator = 0
	session.app.last_alpha = 1.0
	session.app.has_routed = false
	session.camera_override = {}
	session.has_camera_override = false
	session.drawn_alpha = 1.0
	session.drawn_frame = session.frame
	session.settle.frames = 0
	session.settle.converged = false
	ui_run_reset(session, session.allocator)
	return ""
}

session_restart :: proc(session: ^Session) -> string {
	capture_run_clear_pending(&session.capture, session.allocator)
	session.frame = 0
	session.view = {}
	session.default_alpha = 1.0
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

// The axes are the held state the platform polls; jump and sprint queue one
// Space or Shift press so they take the same route a key does.
session_apply_input :: proc(session: ^Session, command: Input_Command) {
	if command.has_forward {
		session.held.move_forward = command.forward
	}
	if command.has_right {
		session.held.move_right = command.right
	}
	if command.has_jump && command.jump {
		session.pending_jump = true
	}
	if command.has_sprint {
		session.held.sprint_held = command.sprint
		if command.sprint {
			session.pending_sprint = true
		}
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
	if session.app.runtime.hud.menu.open {
		return fmt.aprintf("menu is open; close the menu to step", allocator = context.allocator)
	}
	due := make([dynamic]int, 0, 4, context.temp_allocator)
	defer delete(due)
	requests := make([dynamic]Capture_Request, 0, 4, context.temp_allocator)
	defer delete(requests)
	for _ in 0 ..< frames {
		if timeout := session_check_timeout(session); timeout != "" {
			return timeout
		}
		events := session_frame_events(session)
		session.frame += 1
		clear(&due)
		clear(&requests)
		session_due_captures(session, &due, &requests)
		if render_error := session_frame(
			session,
			events,
			1,
			session.default_alpha,
			requests[:],
		); render_error != "" {
			return render_error
		}
		if expect_error := session_check_due_expects(session, due[:]); expect_error != "" {
			session_release_captures(session, due[:])
			return expect_error
		}
		session_release_captures(session, due[:])
		if session.quit {
			break
		}
	}
	return ""
}

// session_due_captures collects the captures whose frame has arrived. The
// pending entries stay until the frame that draws them succeeds.
@(private)
session_due_captures :: proc(
	session: ^Session,
	due: ^[dynamic]int,
	requests: ^[dynamic]Capture_Request,
) {
	for pending, index in session.capture.pending {
		if pending.frame > session.frame {
			continue
		}
		append(due, index)
		append(requests, ..pending.requests)
	}
}

@(private)
session_check_due_expects :: proc(session: ^Session, due: []int) -> string {
	for index in due {
		if expect_error := check_state_expects(
			session,
			session.capture.pending[index].expect_state,
		); expect_error != "" {
			return expect_error
		}
	}
	return ""
}

@(private)
session_release_captures :: proc(session: ^Session, due: []int) {
	for cursor := len(due) - 1; cursor >= 0; cursor -= 1 {
		index := due[cursor]
		pending_capture_destroy(&session.capture.pending[index], session.allocator)
		ordered_remove(&session.capture.pending, index)
	}
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
