#+vet explicit-allocators
package harness

import "core:log"
import "core:path/filepath"
import "core:strings"

@(private)
execute_commands :: proc(session: ^Session, scenario: Scenario, render_enabled: bool) -> string {
	for command in scenario.commands {
		log.infof("harness: %s at frame %d", command_name(command.kind), session.frame)
		backend_ready := session.backend != nil && session.backend.ready
		if command.kind == .Capture && (!render_enabled || !backend_ready) {
			log.warn("harness: capture skipped because rendering is disabled")
			continue
		}
		reply := session_execute(session, command, "")
		ok := reply.ok
		error := ""
		if !ok && command.kind != .Check {
			error = strings.clone(reply.error, context.allocator)
		}
		reply_destroy(&reply, context.allocator)
		if command.kind == .Check {
			continue
		}
		if !ok || session.quit {
			return error
		}
	}
	return ""
}

scenario_has_capture :: proc(scenario: Scenario) -> bool {
	for command in scenario.commands {
		if command.kind == .Capture {
			return true
		}
	}
	return false
}

@(private)
scenario_has_perf :: proc(scenario: Scenario) -> bool {
	for command in scenario.commands {
		if command.kind == .Perf {
			return true
		}
	}
	return false
}

@(private)
rewrite_capture_paths :: proc(session: ^Session, out_dir: string) {
	for &capture in session.captures {
		if capture.path == "" {
			continue
		}
		filename := filepath.base(capture.path)
		final_path := join_path({out_dir, "frames", filename}, context.allocator)
		if final_path == "" {
			continue
		}
		if capture.path != "" {
			delete(capture.path, context.allocator)
		}
		capture.path = final_path
	}
}
