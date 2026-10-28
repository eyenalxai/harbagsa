#+vet explicit-allocators
package harness

import "core:encoding/json"
import "core:mem"
import "core:strings"


@(private)
parse_step :: proc(object: json.Object, _allocator: mem.Allocator) -> (Command, string) {
	if key, unknown := json_unknown_key(object, {"cmd", "frames"}); unknown {
		return {}, format_error("unknown key %q", key)
	}
	frames, frames_error := parse_frames(object)
	if frames_error != "" {
		return {}, frames_error
	}
	return {kind = .Step, step = {frames = frames}}, ""
}


@(private)
parse_view :: proc(object: json.Object, _allocator: mem.Allocator) -> (Command, string) {
	if key, unknown := json_unknown_key(object, {"cmd", "hud", "debug", "hint", "perf"}); unknown {
		return {}, format_error("unknown key %q", key)
	}
	view, view_error := parse_view_fields(object)
	if view_error != "" {
		return {}, view_error
	}
	return {kind = .View, view = view}, ""
}

parse_view_fields :: proc(object: json.Object) -> (view: View_Command, error: string) {
	if field_error := json_optional_bool(object, "hud", &view.hud, &view.has_hud); field_error != "" {
		return {}, field_error
	}
	if field_error := json_optional_bool(object, "debug", &view.debug, &view.has_debug); field_error != "" {
		return {}, field_error
	}
	if field_error := json_optional_bool(object, "hint", &view.hint, &view.has_hint); field_error != "" {
		return {}, field_error
	}
	if field_error := json_optional_bool(object, "perf", &view.perf, &view.has_perf); field_error != "" {
		return {}, field_error
	}
	return view, ""
}

@(private)
parse_record :: proc(object: json.Object, allocator: mem.Allocator) -> (Command, string) {
	if key, unknown := json_unknown_key(object, {"cmd", "path", "actions"}); unknown {
		return {}, format_error("unknown key %q", key)
	}
	command := Command{kind = .Record}
	if value, has := json_get(object, "path"); has {
		path, ok := json_string(value)
		if !ok || path == "" {
			return {}, format_error("%s", "'path' must be a non-empty string")
		}
		command.record.path = strings.clone(path, allocator)
		command.record.has_path = true
	}
	if field_error := json_bool(object, "actions", &command.record.actions); field_error != "" {
		return {}, field_error
	}
	return command, ""
}

@(private)
parse_replay :: proc(object: json.Object, allocator: mem.Allocator) -> (Command, string) {
	path, path_error := parse_path_field(object, allocator, "replay")
	if path_error != "" {
		return {}, path_error
	}
	return {kind = .Replay, replay = {path = path}}, ""
}

@(private)
parse_repro :: proc(object: json.Object, allocator: mem.Allocator) -> (Command, string) {
	path, path_error := parse_path_field(object, allocator, "repro")
	if path_error != "" {
		return {}, path_error
	}
	return {kind = .Repro, repro = {path = path}}, ""
}

@(private)
parse_path_field :: proc(
	object: json.Object,
	allocator: mem.Allocator,
	name: string,
) -> (path: string, error: string) {
	if key, unknown := json_unknown_key(object, {"cmd", "path"}); unknown {
		return "", format_error("unknown key %q", key)
	}
	value, ok := string_field(object, "path")
	if !ok || value == "" {
		return "", format_error("%s needs a non-empty 'path'", name)
	}
	return strings.clone(value, allocator), ""
}

