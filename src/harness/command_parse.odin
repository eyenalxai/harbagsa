#+vet explicit-allocators
package harness

import "core:encoding/json"

command_parse_string :: proc(line: string, allocator := context.allocator) -> (Command, string) {
	value, parse_error := json.parse_string(line, .JSON, true, allocator)
	if parse_error != .None {
		return {}, format_error("invalid JSON: %v", parse_error)
	}
	defer json.destroy_value(value, allocator)
	return command_parse(value, allocator)
}

// Parse errors are always allocated; the caller frees them.
command_parse :: proc(value: json.Value, allocator := context.allocator) -> (Command, string) {
	object, object_ok := json_object(value)
	if !object_ok {
		return {}, format_error("%s", "command must be an object")
	}
	cmd_value, has_cmd := json_get(object, "cmd")
	if !has_cmd {
		return {}, format_error("%s", "command is missing 'cmd'")
	}
	name, name_ok := json_string(cmd_value)
	if !name_ok {
		return {}, format_error("%s", "'cmd' must be a string")
	}

	switch name {
	case "reset":
		if key, unknown := json_unknown_key(object, {"cmd"}); unknown {
			return {}, format_error("unknown key %q", key)
		}
		return {kind = .Reset}, ""
	case "look":
		return parse_look(object)
	case "face":
		return parse_face(object)
	case "input":
		return parse_input(object)
	case "step":
		return parse_step(object)
	case "settle":
		return parse_settle(object)
	case "state":
		if key, unknown := json_unknown_key(object, {"cmd"}); unknown {
			return {}, format_error("unknown key %q", key)
		}
		return {kind = .State}, ""
	case "capture":
		return parse_capture(object, allocator)
	case "camera":
		return parse_camera(object)
	case "view":
		return parse_view(object)
	case "sun":
		return parse_sun(object)
	case "crates":
		return parse_crates(object)
	case "debug_mode":
		return parse_debug_mode(object)
	case "menu":
		return parse_menu(object)
	case "check":
		return parse_check(object, allocator)
	case "record":
		return parse_record(object, allocator)
	case "replay":
		return parse_replay(object, allocator)
	case "perf":
		return parse_perf(object, allocator)
	case "renderer_debug":
		return parse_renderer_debug(object)
	case "displays":
		return parse_displays(object, allocator)
	case "rows":
		if key, unknown := json_unknown_key(object, {"cmd"}); unknown {
			return {}, format_error("unknown key %q", key)
		}
		return {kind = .Rows}, ""
	case "quit":
		if key, unknown := json_unknown_key(object, {"cmd"}); unknown {
			return {}, format_error("unknown key %q", key)
		}
		return {kind = .Quit}, ""
	}
	return {}, format_error("unknown command %q", name)
}

