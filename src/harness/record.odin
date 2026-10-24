#+vet explicit-allocators
package harness

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"

session_record_start :: proc(session: ^Session, path: string) -> string {
	if session.recording {
		return "already recording; send 'record' without a path to stop"
	}
	if path == "" {
		return "record needs a path to start"
	}
	session.recording = true
	session.record_path = strings.clone(path, session.allocator)
	session.record_start_frame = session.frame
	clear(&session.recorded)

	append(&session.recorded, strings.clone(`{"cmd": "reset"}`, session.allocator))
	view_line := fmt.aprintf(
		`{{"cmd": "view", "hud": %v, "debug": %v, "hint": %v, "perf": %v}}`,
		session.view.hud,
		session.view.debug,
		session.view.hint,
		session.view.perf,
		allocator = session.allocator,
	)
	append(&session.recorded, view_line)
	if session.debug.active {
		append(
			&session.recorded,
			strings.clone(`{"cmd": "debug_mode", "active": true}`, session.allocator),
		)
	}
	if session.input.move_forward != 0 || session.input.move_right != 0 || session.input.jump_pressed {
		input_line := fmt.aprintf(
			`{{"cmd": "input", "forward": %g, "right": %g, "jump": %v}}`,
			session.input.move_forward,
			session.input.move_right,
			session.input.jump_pressed,
			allocator = session.allocator,
		)
		append(&session.recorded, input_line)
	}
	if session.has_camera_override {
		camera := session.camera_override
		camera_line := fmt.aprintf(
			`{{"cmd": "camera", "position": [%g, %g, %g], "yaw": %g, "pitch": %g}}`,
			camera.position.x,
			camera.position.y,
			camera.position.z,
			camera.yaw,
			camera.pitch,
			allocator = session.allocator,
		)
		append(&session.recorded, camera_line)
	}
	return ""
}

session_record_stop :: proc(session: ^Session) -> (path: string, error: string) {
	if !session.recording {
		return "", "not recording"
	}

	builder := strings.builder_make(allocator = context.temp_allocator)
	defer strings.builder_destroy(&builder)
	fmt.sbprint(&builder, "{\n  \"version\": 1,\n  \"commands\": [\n")
	for line, index in session.recorded {
		fmt.sbprintf(&builder, "    %s", line)
		if index + 1 < len(session.recorded) {
			fmt.sbprint(&builder, ",")
		}
		fmt.sbprint(&builder, "\n")
	}
	fmt.sbprint(&builder, "  ]\n}\n")

	directory := filepath.dir(session.record_path)
	if directory != "" && directory != "." {
		_ = os.make_directory_all(directory)
	}
	document := strings.to_string(builder)
	if write_error := os.write_entire_file(session.record_path, document); write_error != nil {
		return "", fmt.aprintf(
			"cannot write %s: %v",
			session.record_path,
			write_error,
			allocator = context.allocator,
		)
	}

	absolute, absolute_error := absolute_path(session.record_path, session.allocator)
	if absolute_error != nil {
		absolute = strings.clone(session.record_path, session.allocator)
	}
	for line in session.recorded {
		delete(line, session.allocator)
	}
	clear(&session.recorded)
	delete(session.record_path, session.allocator)
	session.record_path = ""
	session.recording = false
	return absolute, ""
}

session_replay :: proc(session: ^Session, path: string) -> (Replay_Summary, string) {
	if session.recording {
		return {}, format_error("%s", "stop recording before replay")
	}
	scenario, load_error := scenario_load(path, session.allocator)
	if load_error != "" {
		return {}, load_error
	}
	defer scenario_destroy(&scenario, session.allocator)

	if restart_error := session_restart(session); restart_error != "" {
		return {}, restart_error
	}

	summary := Replay_Summary{ok = true}
	for command in scenario.commands {
		#partial switch command.kind {
		case .Replay:
			summary.ok = false
			return summary, format_error("%s", "nested replay is not supported")
		case .Record:
			summary.ok = false
			return summary, format_error("%s", "record is not allowed in a replay")
		case .Quit:
			return summary, ""
		}
		reply := session_execute(session, command, "")
		summary.commands += 1
		if !reply.ok {
			summary.ok = false
			error := strings.clone(reply.error, session.allocator)
			reply_destroy(&reply, session.allocator)
			return summary, error
		}
		reply_destroy(&reply, session.allocator)
	}
	return summary, ""
}
