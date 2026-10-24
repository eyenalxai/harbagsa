#+vet explicit-allocators
package harness

import "core:fmt"
import "core:strings"

import b3 "libs:box3d"

import "src:frame"
import "src:game"

Reply :: struct {
	ok:       bool           `json:"ok"`,
	cmd:      string         `json:"cmd"`,
	frame:    int            `json:"frame"`,
	error:    string         `json:"error,omitempty"`,
	state:    ^State         `json:"state,omitempty"`,
	capture:  ^Capture_Result `json:"capture,omitempty"`,
	check:    ^Check_Result  `json:"check,omitempty"`,
	recorded: string         `json:"recorded,omitempty"`,
	replay:   ^Replay_Summary `json:"replay,omitempty"`,
}

Replay_Summary :: struct {
	commands: int  `json:"commands"`,
	ok:       bool `json:"ok"`,
}

reply_destroy :: proc(reply: ^Reply, allocator := context.allocator) {
	if reply.state != nil {
		state_destroy(reply.state, allocator)
		free(reply.state, allocator)
		reply.state = nil
	}
	if reply.error != "" {
		delete(reply.error, allocator)
	}
	if reply.recorded != "" {
		delete(reply.recorded, allocator)
	}
	if reply.replay != nil {
		free(reply.replay, allocator)
	}
	reply^ = {}
}

session_execute :: proc(session: ^Session, command: Command, raw_line: string) -> Reply {
	if session.quit {
		return reply_error(session, command.kind, "session is closed")
	}
	reply := Reply{ok = true, cmd = command_name(command.kind), frame = session.frame}
	command_error: string
	owns_error := false

	switch command.kind {
	case .Reset:
		command_error = session_reset(session)
	case .Look:
		game.simulation_look(&session.sim, b3.Vec2{command.look.dx, command.look.dy})
	case .Face:
		game.simulation_face(&session.sim, command.face.yaw, command.face.pitch)
	case .Input:
		session_apply_input(session, command.input)
	case .Step:
		command_error = session_step(session, command.step.frames)
		owns_error = true
	case .State:
		reply.state = new(State, session.allocator)
		reply.state^ = session_state(session)
	case .Capture:
		immediate, capture_error := session_queue_capture(session, command.capture)
		command_error = capture_error
		owns_error = true
		if command_error == "" && immediate && len(session.captures) > 0 {
			reply.capture = &session.captures[len(session.captures) - 1]
		}
	case .Camera:
		if command.camera.clear {
			session.camera_override = {}
			session.has_camera_override = false
		} else {
			session.camera_override = {
				position = command.camera.position,
				yaw      = command.camera.yaw,
				pitch    = command.camera.pitch,
				fov_x    = frame.PLAYER_FOV_X,
			}
			session.has_camera_override = true
		}
	case .View:
		if command.view.has_hud {
			session.view.hud = command.view.hud
		}
		if command.view.has_debug {
			session.view.debug = command.view.debug
		}
		if command.view.has_hint {
			session.view.hint = command.view.hint
		}
	case .Menu:
		command_error = session_menu(session, command.menu)
	case .Check:
		state := session_state(session)
		result := check_evaluate(command.check, state, session.allocator)
		state_destroy(&state, session.allocator)
		append(&session.checks, result)
		reply.check = &session.checks[len(session.checks) - 1]
		reply.ok = result.ok
		if !result.ok {
			message := fmt.aprintf(
				"check failed: %s %s %s (actual %s)",
				result.field,
				result.op,
				result.expected,
				result.actual,
				allocator = session.allocator,
			)
			session_failure(session, message)
			delete(message, session.allocator)
		}
	case .Record:
		if command.record.has_path {
			command_error = session_record_start(session, command.record.path)
		} else {
			recorded, record_error := session_record_stop(session)
			command_error = record_error
			reply.recorded = recorded
		}
	case .Replay:
		summary, replay_error := session_replay(session, command.replay.path)
		command_error = replay_error
		if command_error == "" {
			reply.replay = new(Replay_Summary, session.allocator)
			reply.replay^ = summary
		}
	case .Quit:
		if session.recording {
			recorded, _ := session_record_stop(session)
			if recorded != "" {
				delete(recorded, session.allocator)
			}
		}
		session.quit = true
	}

	reply.frame = session.frame
	if command_error != "" {
		reply.ok = false
		reply.error = strings.clone(command_error, session.allocator)
		if owns_error {
			delete(command_error, context.allocator)
		}
		return reply
	}
	if session.recording &&
	   command.kind != .Record &&
	   command.kind != .Replay &&
	   command.kind != .Quit {
		session_record_command(session, command, raw_line)
	}
	return reply
}

reply_error :: proc(session: ^Session, kind: Command_Kind, message: string) -> Reply {
	return {
		ok = false,
		cmd = command_name(kind),
		frame = session.frame,
		error = strings.clone(message, session.allocator),
	}
}

session_record_command :: proc(session: ^Session, command: Command, raw_line: string) {
	#partial switch command.kind {
	case .Capture:
		frame := session.frame - session.record_start_frame
		if frame < 0 {
			frame = 0
		}
		name := command.capture.name
		if name == "" {
			name = capture_name(session.frame, context.temp_allocator)
		}
		alpha_part := ""
		if command.capture.has_alpha {
			alpha_part = fmt.aprintf(
				", \"alpha\": %g",
				command.capture.alpha,
				allocator = context.temp_allocator,
			)
		}
		line := fmt.aprintf(
			`{{"cmd": "capture", "name": %q, "frame": %d%s}}`,
			name,
			frame,
			alpha_part,
			allocator = session.allocator,
		)
		append(&session.recorded, line)
	case .Record, .Replay, .Quit:
	case:
		trimmed := strings.trim_space(raw_line)
		if trimmed != "" {
			append(&session.recorded, strings.clone(trimmed, session.allocator))
		}
	}
}
