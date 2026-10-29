#+vet explicit-allocators
package harness

import "core:strings"

Reply :: struct {
	ok:     bool   `json:"ok"`,
	cmd:    string `json:"cmd"`,
	frame:  int    `json:"frame"`,
	placed: u32    `json:"placed,omitempty"`,

	// Owned strings; reply_destroy frees each one.
	error:    string `json:"error,omitempty"`,
	recorded: string `json:"recorded,omitempty"`,
	written:  string `json:"written,omitempty"`,

	// Owned pointers; reply_destroy frees each one.
	state:    ^State          `json:"state,omitempty"`,
	replay:   ^Replay_Summary `json:"replay,omitempty"`,
	rows:     ^Rows_State     `json:"rows,omitempty"`,
	displays: ^Displays_State `json:"displays,omitempty"`,
	get:      ^Get_Result     `json:"get,omitempty"`,

	// Borrowed from the session; valid until the next command.
	capture:   ^Capture_Result   `json:"capture,omitempty"`,
	pick:      ^Pick_Result      `json:"pick,omitempty"`,
	perf:      ^Perf_Report      `json:"perf,omitempty"`,
	trace:     string            `json:"trace,omitempty"`,
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
	if reply.get != nil {
		delete(reply.get.field, allocator)
		if reply.get.value.kind == .String {
			delete(reply.get.value.text, allocator)
		}
		free(reply.get, allocator)
		reply.get = nil
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
	if row.backend != .None && session.render.enabled {
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
	if session.recorder.recording && row.record != .Skip {
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
		session.recorder.recorded_renderer_debug = true
	}
	row := command_row_by_kind(command.kind)
	switch row.record {
	case .Raw:
		trimmed := strings.trim_space(raw_line)
		if trimmed != "" {
			append(&session.recorder.recorded, strings.clone(trimmed, session.allocator))
		}
	case .Custom:
		if command.kind == .Capture {
			record_capture_line(session, command.capture)
		} else if command.kind == .Captures {
			record_captures_line(session, command.captures)
		}
	case .Skip:
	}
}

@(private)
record_capture_frame :: proc(
	session: ^Session,
	has_frame: bool,
	frame: int,
) -> (
	relative: int,
	resolved: int,
) {
	resolved = has_frame ? frame : session.frame
	relative = max(resolved - session.recorder.start_frame, 0)
	return
}

@(private)
record_captures_line :: proc(session: ^Session, captures: Captures_Command) {
	recorded := captures
	recorded.has_frame = true
	relative, _ := record_capture_frame(session, captures.has_frame, captures.frame)
	recorded.frame = relative
	line := captures_command_json(recorded, session.allocator)
	append(&session.recorder.recorded, line)
}

@(private)
record_capture_line :: proc(session: ^Session, capture: Capture_Command) {
	recorded := capture
	recorded.has_frame = true
	relative, resolved := record_capture_frame(session, capture.has_frame, capture.frame)
	recorded.frame = relative
	if recorded.name == "" {
		recorded.name = capture_name(resolved, context.temp_allocator)
	}
	line := capture_command_json(recorded, session.allocator)
	append(&session.recorder.recorded, line)
}
