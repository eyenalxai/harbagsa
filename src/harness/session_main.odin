#+vet explicit-allocators
package harness

import "core:encoding/json"
import "core:fmt"
import "core:log"
import "core:os"
import "core:strings"

Session_Runtime :: struct {
	session:    Session,
	options:    Session_Options,
	frames_dir: string,
	trace_dir:  string,
	backend:    Backend,
	has_backend: bool,
	exit_code:  int,
	had_error:  bool,
}

session_main :: proc(options: Session_Options) -> int {
	frames_dir := options.out_dir
	if frames_dir == "" {
		frames_dir = "runs/session"
	}
	absolute_frames, abs_error := absolute_path(frames_dir, context.allocator)
	if abs_error != nil {
		print_summary_failure("cannot resolve the capture directory", EXIT_SCENARIO)
		return EXIT_SCENARIO
	}
	defer delete(absolute_frames, context.allocator)
	frames_path := join_path({absolute_frames, "frames"}, context.allocator)
	defer delete(frames_path, context.allocator)
	_ = os.make_directory_all(frames_path)

	session, session_error := session_create(context.allocator)
	if session_error != "" {
		print_summary_failure(session_error, EXIT_RENDER)
		return EXIT_RENDER
	}
	runtime := Session_Runtime {
		session    = session,
		options    = options,
		frames_dir = strings.clone(frames_path, context.allocator),
		trace_dir  = strings.clone(absolute_frames, context.allocator),
	}
	runtime.session.debug_renderer = options.debug_renderer
	if options.no_analysis {
		runtime.session.analysis_config.enabled = false
	}
	defer {
		if runtime.has_backend {
			backend_destroy(&runtime.backend)
		}
		delete(runtime.frames_dir, context.allocator)
		delete(runtime.trace_dir, context.allocator)
		session_destroy(&runtime.session)
	}

	if options.present && !options.no_render {
		if backend_error := runtime_ensure_backend(&runtime, true); backend_error != "" {
			print_summary_failure(backend_error, EXIT_RENDER)
			return EXIT_RENDER
		}
	}

	code: int
	if options.socket != "" {
		code = serve_socket(&runtime, options.socket)
	} else {
		code = serve_stdin(&runtime)
	}
	if runtime.exit_code > code {
		code = runtime.exit_code
	}
	if len(runtime.session.failures) > 0 && code == EXIT_OK {
		code = EXIT_CHECK
	}
	return code
}

runtime_ensure_backend :: proc(runtime: ^Session_Runtime, present: bool) -> string {
	if runtime.has_backend {
		return ""
	}
	if runtime.options.no_render {
		return "capture requires rendering"
	}
	backend, backend_error := backend_create(
		runtime.options.width,
		runtime.options.height,
		present,
		runtime.frames_dir,
		context.allocator,
	)
	if backend_error != "" {
		runtime.exit_code = EXIT_RENDER
		log.errorf("harness: %s", backend_error)
		return backend_error
	}
	runtime.backend = backend
	runtime.has_backend = true
	session_set_backend(&runtime.session, &runtime.backend, present)
	return ""
}

runtime_handle_line :: proc(runtime: ^Session_Runtime, line: string) -> []byte {
	trimmed := strings.trim_space(line)
	if trimmed == "" {
		return nil
	}
	value, parse_error := json.parse_string(trimmed, .JSON, true, context.allocator)
	if parse_error != .None {
		reply := Reply{ok = false, cmd = "parse", frame = runtime.session.frame}
		reply.error = fmt.aprintf("invalid JSON: %v", parse_error, allocator = context.allocator)
		data := encode_reply(reply)
		reply_destroy(&reply, context.allocator)
		return data
	}
	defer json.destroy_value(value, context.allocator)

	command, command_error := command_parse(value, context.allocator)
	if command_error != "" {
		reply := Reply{ok = false, cmd = "parse", frame = runtime.session.frame}
		reply.error = strings.clone(command_error, context.allocator)
		data := encode_reply(reply)
		reply_destroy(&reply, context.allocator)
		return data
	}
	defer command_destroy(&command, context.allocator)

	backend_error := ""
	if command.kind == .Capture ||
	   (command.kind == .Perf && !runtime.options.no_render) ||
	   (command.kind == .Settle && !runtime.options.no_render) {
		backend_error = runtime_ensure_backend(runtime, false)
	}
	if command.kind == .Replay {
		scenario, load_error := scenario_load(command.replay.path, context.allocator)
		if load_error == "" {
			defer scenario_destroy(&scenario, context.allocator)
			if scenario_has_capture(scenario) ||
			   (scenario_has_perf(scenario) && !runtime.options.no_render) {
				backend_error = runtime_ensure_backend(runtime, false)
			}
		}
	}
	if backend_error != "" {
		reply := Reply{ok = false, cmd = command_name(command.kind), frame = runtime.session.frame}
		reply.error = strings.clone(backend_error, context.allocator)
		data := encode_reply(reply)
		reply_destroy(&reply, context.allocator)
		runtime.had_error = true
		return data
	}

	reply := session_execute(&runtime.session, command, trimmed)
	if reply.ok && reply.perf != nil && runtime.session.has_trace {
		if trace_error := write_session_trace(&runtime.session, runtime.trace_dir); trace_error != "" {
			reply.ok = false
			reply.error = trace_error
			runtime.had_error = true
		} else {
			reply.trace = runtime.session.trace_path
		}
	}
	if !reply.ok {
		runtime.had_error = true
		if runtime.session.render_failed {
			runtime.exit_code = EXIT_RENDER
		} else if runtime.exit_code == EXIT_OK {
			runtime.exit_code = EXIT_CHECK
		}
	}
	data := encode_reply(reply)
	reply_destroy(&reply, context.allocator)
	return data
}

serve_stdin :: proc(runtime: ^Session_Runtime) -> int {
	if serve_stream(runtime, os.stdin, os.stdout) != "" {
		return runtime.exit_code
	}
	if runtime.had_error || len(runtime.session.failures) > 0 {
		return EXIT_CHECK
	}
	return EXIT_OK
}

Line_Sink :: struct {
	ctx:   rawptr,
	write: proc(ctx: rawptr, data: []u8) -> bool,
}

consume_lines :: proc(runtime: ^Session_Runtime, pending: ^[dynamic]u8, sink: Line_Sink) -> bool {
	for {
		newline := -1
		for character, index in pending[:] {
			if character == '\n' {
				newline = index
				break
			}
		}
		if newline < 0 {
			if len(pending) > MAX_SESSION_LINE {
				clear(pending)
				return false
			}
			return true
		}
		line := string(pending[:newline])
		data := runtime_handle_line(runtime, line)
		if data != nil && !sink.write(sink.ctx, data) {
			return false
		}
		copy(pending[:], pending[newline + 1:])
		resize(pending, len(pending^) - (newline + 1))
		if runtime.session.quit {
			return true
		}
	}
}

consume_tail :: proc(runtime: ^Session_Runtime, pending: ^[dynamic]u8, sink: Line_Sink) -> bool {
	if len(pending) == 0 {
		return true
	}
	data := runtime_handle_line(runtime, string(pending[:]))
	return data == nil || sink.write(sink.ctx, data)
}

serve_stream :: proc(runtime: ^Session_Runtime, input, output: ^os.File) -> string {
	pending := make([dynamic]u8, 0, 4096, context.allocator)
	defer delete(pending)
	sink := Line_Sink{ctx = output, write = stdout_sink_write}
	chunk: [8192]u8
	for {
		count, read_error := os.read(input, chunk[:])
		if count > 0 {
			append(&pending, ..chunk[:count])
			if !consume_lines(runtime, &pending, sink) {
				return "line processing failed"
			}
		}
		if runtime.session.quit {
			break
		}
		if read_error != nil {
			break
		}
	}
	_ = consume_tail(runtime, &pending, sink)
	return ""
}

@(private)
stdout_sink_write :: proc(ctx: rawptr, data: []u8) -> bool {
	output := cast(^os.File)ctx
	defer delete(data, context.allocator)
	if _, write_error := os.write(output, data); write_error != nil {
		return false
	}
	if _, write_error := os.write(output, []byte{'\n'}); write_error != nil {
		return false
	}
	return true
}
