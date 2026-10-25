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
	value: Check_Value,
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
	sections := state_section_for_field(command.field)
	if .Menu in sections || .Notice in sections || .Rows in sections {
		session_refresh_hud(session)
	}
	state := state_build_sections(
		&session.sim,
		session.frame,
		&session.hud,
		&session.debug,
		session_camera(session),
		session.renderer_report,
		session.render_digest_text,
		{frames = session.settle_frames, converged = session.settle_converged},
		sections,
		session.allocator,
	)
	defer state_destroy(&state, session.allocator)
	analysis := session.has_analysis ? &session.analysis : nil
	value, field_error := check_field(state, session.captures[:], analysis, command.field)
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
