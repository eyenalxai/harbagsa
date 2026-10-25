#+vet explicit-allocators
package harness

import "core:fmt"
import "core:strings"


import "src:renderer"

Reply :: struct {
	ok:       bool           `json:"ok"`,
	cmd:      string         `json:"cmd"`,
	frame:    int            `json:"frame"`,
	error:    string         `json:"error,omitempty"`,
	state:    ^State         `json:"state,omitempty"`,
	capture:  ^Capture_Result `json:"capture,omitempty"`,
	check:    ^Check_Result  `json:"check,omitempty"`,
	recorded: string         `json:"recorded,omitempty"`,
	written:  string         `json:"written,omitempty"`,
	replay:   ^Replay_Summary `json:"replay,omitempty"`,
	perf:     ^Perf_Report   `json:"perf,omitempty"`,
	trace:    string         `json:"trace,omitempty"`,
	rows:     ^Rows_State    `json:"rows,omitempty"`,
	displays: ^Displays_State `json:"displays,omitempty"`,
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
	if reply.written != "" {
		delete(reply.written, allocator)
	}
	if reply.replay != nil {
		free(reply.replay, allocator)
	}
	if reply.rows != nil {
		rows_state_destroy(reply.rows, allocator)
		free(reply.rows, allocator)
	}
	if reply.displays != nil {
		displays_state_destroy(reply.displays, allocator)
		free(reply.displays, allocator)
	}
	reply^ = {}
}

session_execute :: proc(session: ^Session, command: Command, raw_line: string) -> Reply {
	if session.quit {
		return reply_error(session, command.kind, "session is closed")
	}
	if timeout := session_check_timeout(session); timeout != "" {
		reply := reply_error(session, command.kind, timeout)
		delete(timeout, context.allocator)
		return reply
	}
	row := command_row_by_kind(command.kind)
	reply := Reply{ok = true, cmd = row.name, frame = session.frame}
	if row.backend != .None && session.render_enabled {
		if error := session_ensure_backend(session); error != "" {
			reply.ok = false
			reply.error = strings.clone(error, session.allocator)
			delete(error, context.allocator)
			return reply
		}
	}

	command_error := row.execute(session, command, &reply)
	reply.frame = session.frame
	if command_error != "" {
		reply.ok = false
		reply.error = strings.clone(command_error, session.allocator)
		delete(command_error, context.allocator)
		return reply
	}
	if session.recording && row.record != .Skip {
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
	if command.kind == .Renderer_Debug {
		session.recorded_renderer_debug = true
	}
	row := command_row_by_kind(command.kind)
	switch row.record {
	case .Raw:
		trimmed := strings.trim_space(raw_line)
		if trimmed != "" {
			append(&session.recorded, strings.clone(trimmed, session.allocator))
		}
	case .Custom:
		if command.kind == .Capture {
			record_capture_line(session, command.capture)
		}
	case .Skip:
	}
}

@(private)
record_capture_line :: proc(session: ^Session, capture: Capture_Command) {
	frame := session.frame - session.record_start_frame
	if frame < 0 {
		frame = 0
	}
	name := capture.name
	if name == "" {
		name = capture_name(session.frame, context.temp_allocator)
	}
	alpha_part := ""
	if capture.has_alpha {
		alpha_part = fmt.aprintf(
			", \"alpha\": %g",
			capture.alpha,
			allocator = context.temp_allocator,
		)
	}
	target_part := ""
	if capture.target != .Color {
		target_part = fmt.aprintf(
			`, "target": %q`,
			renderer.capture_target_name(capture.target),
			allocator = context.temp_allocator,
		)
	}
	format_part := ""
	if capture.format != .Png {
		format_part = fmt.aprintf(
			`, "format": %q`,
			capture_format_name(capture.format),
			allocator = context.temp_allocator,
		)
	}
	line := fmt.aprintf(
		`{{"cmd": "capture", "name": %q, "frame": %d%s%s%s}}`,
		name,
		frame,
		alpha_part,
		target_part,
		format_part,
		allocator = session.allocator,
	)
	append(&session.recorded, line)
}
