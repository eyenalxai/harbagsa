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
parse_check :: proc(object: json.Object, allocator: mem.Allocator) -> (Command, string) {
	if key, unknown := json_unknown_key(
		object,
		{"cmd", "field", "op", "value", "other", "tolerance", "advisory", "warmup", "window"},
	); unknown {
		return {}, format_error("unknown key %q", key)
	}
	field, field_ok := string_field(object, "field")
	op_name, op_ok := string_field(object, "op")
	if !field_ok || !op_ok {
		return {}, format_error("%s", "check needs string 'field' and 'op'")
	}
	op, parsed_op := check_op_parse(op_name)
	if !parsed_op {
		return {}, format_error("unknown check op %q", op_name)
	}
	warmup := 0
	if warmup_value, has := json_get(object, "warmup"); has {
		parsed, parsed_ok := json_integer(warmup_value)
		if !parsed_ok || parsed < 0 {
			return {}, format_error("%s", "'warmup' must be a non-negative integer")
		}
		warmup = int(parsed)
	}
	window, window_error := parse_check_window(object)
	if window_error != "" {
		return {}, window_error
	}
	if window.has && warmup != 0 {
		return {}, format_error("%s", "a check cannot use both 'warmup' and 'window'")
	}
	value, value_ok := json_get(object, "value")
	other, other_ok := string_field(object, "other")
	if value_ok && other_ok {
		return {}, format_error("%s", "check takes 'value' or 'other', not both")
	}
	if !value_ok && !other_ok {
		return {}, format_error("%s", "check needs 'value' or 'other'")
	}
	check := Check_Command {
		field  = strings.clone(field, allocator),
		op     = op,
		warmup = warmup,
		window = window,
	}
	if field_error := json_bool(object, "advisory", &check.advisory); field_error != "" {
		return {}, field_error
	}
	if tolerance_value, has := json_get(object, "tolerance"); has {
		tolerance, tolerance_ok := json_number(tolerance_value)
		if !tolerance_ok || tolerance < 0 {
			return {}, format_error("%s", "'tolerance' must be a non-negative number")
		}
		check.tolerance = tolerance
	}
	if other_ok {
		if other == "" {
			return {}, format_error("%s", "'other' must name a field")
		}
		check.other = strings.clone(other, allocator)
		check.has_other = true
	} else {
		check_value, value_error := parse_check_value(value, allocator)
		if value_error != "" {
			return {}, value_error
		}
		check.value = check_value
	}
	return {kind = .Check, check = check}, ""
}

@(private)
parse_check_window :: proc(object: json.Object) -> (Capture_Window, string) {
	value, has := json_get(object, "window")
	if !has {
		return {}, ""
	}
	fields, fields_ok := json_object(value)
	if !fields_ok {
		return {}, format_error("%s", "'window' must be an object with 'start' and 'count'")
	}
	if key, unknown := json_unknown_key(fields, {"start", "count"}); unknown {
		return {}, format_error("unknown window key %q", key)
	}
	start_value, has_start := json_get(fields, "start")
	count_value, has_count := json_get(fields, "count")
	if !has_start || !has_count {
		return {}, format_error("%s", "'window' needs 'start' and 'count'")
	}
	start, start_ok := json_integer(start_value)
	count, count_ok := json_integer(count_value)
	if !start_ok || start < 0 {
		return {}, format_error("%s", "window 'start' must be a non-negative integer")
	}
	if !count_ok || count < 1 {
		return {}, format_error("%s", "window 'count' must be a positive integer")
	}
	return {start = int(start), count = int(count), has = true}, ""
}

@(private)
parse_check_value :: proc(value: json.Value, allocator: mem.Allocator) -> (Check_Value, string) {
	if number, ok := json_number(value); ok {
		return {kind = .Number, number = number}, ""
	}
	if boolean, ok := json_boolean(value); ok {
		return {kind = .Bool, boolean = boolean}, ""
	}
	if text, ok := json_string(value); ok {
		return {kind = .String, text = strings.clone(text, allocator)}, ""
	}
	return {}, format_error("%s", "check 'value' must be a number, boolean, or string")
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

