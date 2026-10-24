#+vet explicit-allocators
package harness

import "core:encoding/json"

Debug_Mode_Command :: struct {
	active: bool,
}

@(private)
parse_debug_mode :: proc(object: json.Object) -> (Command, string) {
	if key, unknown := json_unknown_key(object, {"cmd", "active"}); unknown {
		return {}, format_error("unknown key %q", key)
	}
	value, has := json_get(object, "active")
	if !has {
		return {}, "debug_mode needs 'active'"
	}
	active, ok := json_boolean(value)
	if !ok {
		return {}, "'active' must be a boolean"
	}
	return {kind = .Debug_Mode, debug_mode = {active = active}}, ""
}
