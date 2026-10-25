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

	row, found := command_row_by_name(name)
	if !found {
		return {}, format_error("unknown command %q", name)
	}
	command, parse_error := row.parse(object, allocator)
	if parse_error != "" {
		return {}, parse_error
	}
	command.kind = row.kind
	return command, ""
}
