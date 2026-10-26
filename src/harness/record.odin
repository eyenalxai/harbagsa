#+vet explicit-allocators
package harness

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"

import "src:frame"
import "src:renderer"

session_record_start :: proc(session: ^Session, path: string, include_scene := true) -> string {
	if session.recorder.recording {
		return format_error("%s", "already recording; send 'record' without a path to stop")
	}
	if path == "" {
		return format_error("%s", "record needs a path to start")
	}
	session.recorder.recording = true
	session.recorder.path = strings.clone(path, session.allocator)
	session.recorder.start_frame = session.frame
	session.recorder.recorded_renderer_debug = false
	clear(&session.recorder.recorded)

	append(&session.recorder.recorded, strings.clone(`{"cmd": "reset"}`, session.allocator))
	if include_scene {
		options := frame.Options {
			hud        = session.view.hud,
			debug_view = session.view.debug,
			captured   = !session.view.hint,
			perf       = session.view.perf,
		}
		camera: ^renderer.Camera
		if session.has_camera_override {
			camera = &session.camera_override
		}
		debug: ^renderer.Renderer_Debug
		if session.render.debug.active {
			debug = &session.render.debug
		}
		scene := frame.scene_capture(
			&session.sim,
			&session.debug,
			options,
			camera,
			debug,
			session.scene_probe_volumes,
			session.allocator,
		)
		_, has_scene_debug := scene.renderer_debug.?
		session.recorder.recorded_renderer_debug = has_scene_debug
		scene_line := frame.scene_json(scene, session.allocator, false)
		frame.scene_destroy(&scene, session.allocator)
		append(&session.recorder.recorded, scene_line)
	}
	if session.input.move_forward != 0 || session.input.move_right != 0 || session.input.jump_pressed {
		input := Input_Command {
			forward     = session.input.move_forward,
			right       = session.input.move_right,
			jump        = session.input.jump_pressed,
			has_forward = true,
			has_right   = true,
			has_jump    = true,
		}
		append(&session.recorder.recorded, input_command_json(input, session.allocator))
	}
	return ""
}

session_record_stop :: proc(session: ^Session) -> (path: string, error: string) {
	if !session.recorder.recording {
		return "", format_error("%s", "not recording")
	}

	builder := strings.builder_make(allocator = context.temp_allocator)
	defer strings.builder_destroy(&builder)
	fmt.sbprint(&builder, "{\n  \"version\": 1,\n")
	// A recorded renderer debug command needs the gate when it replays.
	if session.recorder.recorded_renderer_debug {
		fmt.sbprint(&builder, "  \"requires\": {\"renderer_debug\": true},\n")
	}
	fmt.sbprint(&builder, "  \"commands\": [\n")
	for line, index in session.recorder.recorded {
		fmt.sbprintf(&builder, "    %s", line)
		if index + 1 < len(session.recorder.recorded) {
			fmt.sbprint(&builder, ",")
		}
		fmt.sbprint(&builder, "\n")
	}
	fmt.sbprint(&builder, "  ]\n}\n")

	directory := filepath.dir(session.recorder.path)
	if directory != "" && directory != "." {
		_ = os.make_directory_all(directory)
	}
	document := strings.to_string(builder)
	if write_error := os.write_entire_file(session.recorder.path, document); write_error != nil {
		return "", fmt.aprintf(
			"cannot write %s: %v",
			session.recorder.path,
			write_error,
			allocator = context.allocator,
		)
	}

	absolute, absolute_error := absolute_path(session.recorder.path, session.allocator)
	if absolute_error != nil {
		absolute = strings.clone(session.recorder.path, session.allocator)
	}
	recorder_clear(&session.recorder, session.allocator)
	return absolute, ""
}

session_replay :: proc(session: ^Session, path: string) -> (Replay_Summary, string) {
	if session.recorder.recording {
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
	if scenario.requires.renderer_debug {
		session.debug_renderer = true
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
