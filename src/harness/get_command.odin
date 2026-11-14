#+vet explicit-allocators
package harness

import "core:encoding/json"
import "core:mem"
import "core:strings"

Get_Command :: struct {
	field: string,
}

Get_Result :: struct {
	field: string,
	value: Field_Value,
}

@(private)
parse_get :: proc(object: json.Object, allocator: mem.Allocator) -> (Command, string) {
	if key, unknown := json_unknown_key(object, {"cmd", "field"}); unknown {
		return {}, format_error("unknown key %q", key)
	}
	field, ok := string_field(object, "field")
	if !ok || field == "" {
		return {}, format_error("%s", "get needs a string 'field'")
	}
	return {kind = .Get, get = {field = strings.clone(field, allocator)}}, ""
}

@(private)
destroy_get :: proc(command: ^Command, allocator: mem.Allocator) {
	delete(command.get.field, allocator)
	command^ = {}
}

session_get :: proc(session: ^Session, command: Get_Command, reply: ^Reply) -> string {
	state, state_error := session_observe(session, state_section_for_field(command.field))
	if state_error != "" {
		return state_error
	}
	defer state_destroy(&state, session.allocator)
	value, field_error := field_value(state, session.capture.captures[:], command.field)
	if field_error != "" {
		return field_error
	}
	if value.kind == .String {
		value.text = strings.clone(value.text, session.allocator)
	}
	reply.get = new(Get_Result, session.allocator)
	reply.get^ = {
		field = strings.clone(command.field, session.allocator),
		value = value,
	}
	return ""
}
