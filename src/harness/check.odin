#+vet explicit-allocators
package harness

import "core:fmt"
import "core:mem"
import "core:strconv"
import "core:strings"

CHECK_EPSILON :: 1e-6

Check_Result :: struct {
	field:    string `json:"field"`,
	op:       string `json:"op"`,
	expected: string `json:"value"`,
	other:    string `json:"other,omitempty"`,
	actual:   string `json:"actual,omitempty"`,
	ok:       bool   `json:"ok"`,
	error:    string `json:"error,omitempty"`,
}

check_evaluate :: proc(
	command: Check_Command,
	state: State,
	captures: []Capture_Result,
	analysis: ^Analysis_Summary,
	allocator: mem.Allocator,
) -> Check_Result {
	result := Check_Result {
		field = command.field,
		op = check_op_name(command.op),
	}
	actual, field_error := check_field(state, captures, analysis, command.field)
	if field_error != "" {
		result.error = field_error
		return result
	}
	result.actual = check_value_display(actual, allocator)
	if command.has_other {
		result.other = command.other
		other, other_error := check_field(state, captures, analysis, command.other)
		if other_error != "" {
			result.error = other_error
			return result
		}
		result.expected = check_value_display(other, allocator)
		ok, compare_error := check_compare(actual, command.op, other)
		if compare_error != "" {
			result.error = compare_error
			return result
		}
		result.ok = ok
		return result
	}
	result.expected = check_value_display(command.value, allocator)
	ok, compare_error := check_compare(actual, command.op, command.value)
	if compare_error != "" {
		result.error = compare_error
		return result
	}
	result.ok = ok
	return result
}

@(private)
check_field :: proc(
	state: State,
	captures: []Capture_Result,
	analysis: ^Analysis_Summary,
	path: string,
) -> (
	Check_Value,
	string,
) {
	if strings.has_prefix(path, "analysis.") {
		if analysis == nil {
			return {}, format_error("%s", "analysis is not available; enable it and capture a color frame")
		}
		return analysis_field(analysis^, path[len("analysis."):])
	}
	if strings.has_prefix(path, "capture.") {
		if len(captures) == 0 {
			return {}, format_error("%s", "no capture has run")
		}
		return capture_path_field(captures, path[len("capture."):])
	}
	return state_field(state, path)
}

check_result_destroy :: proc(result: ^Check_Result, allocator: mem.Allocator) {
	if result.expected != "" {
		delete(result.expected, allocator)
	}
	if result.actual != "" {
		delete(result.actual, allocator)
	}
	if result.error != "" {
		delete(result.error, allocator)
	}
	result^ = {}
}

check_compare :: proc(actual: Check_Value, op: Check_Op, expected: Check_Value) -> (bool, string) {
	if actual.kind != expected.kind {
		return false, format_error("%s", "check value type does not match the field type")
	}
	switch actual.kind {
	case .Number:
		return compare_number(actual.number, op, expected.number)
	case .Bool:
		if op != .Eq && op != .Ne {
			return false, format_error("%s", "boolean checks support only 'eq' and 'ne'")
		}
		equal := actual.boolean == expected.boolean
		return equal if op == .Eq else !equal, ""
	case .String:
		if op != .Eq && op != .Ne {
			return false, format_error("%s", "string checks support only 'eq' and 'ne'")
		}
		equal := actual.text == expected.text
		return equal if op == .Eq else !equal, ""
	}
	return false, format_error("%s", "unsupported check value")
}

@(private)
compare_number :: proc(actual: f64, op: Check_Op, expected: f64) -> (bool, string) {
	switch op {
	case .Eq:
		return abs(actual - expected) <= CHECK_EPSILON, ""
	case .Ne:
		return abs(actual - expected) > CHECK_EPSILON, ""
	case .Lt:
		return actual < expected, ""
	case .Le:
		return actual <= expected, ""
	case .Gt:
		return actual > expected, ""
	case .Ge:
		return actual >= expected, ""
	}
	return false, format_error("%s", "unknown check op")
}

// `capture.N.*` names one capture in the check window, so two captures of the
// same run can be compared without an absolute constant.
@(private)
capture_path_field :: proc(captures: []Capture_Result, path: string) -> (Check_Value, string) {
	head, tail, has_tail := split_field(path)
	if has_tail {
		switch head {
		case "first":
			return capture_one_field(captures[0], tail)
		case "last":
			return capture_one_field(captures[len(captures) - 1], tail)
		case "named":
			name, rest, has_rest := split_field(tail)
			if !has_rest {
				return {}, format_error("%s", "capture.named needs <name>.<field>")
			}
			for capture in captures {
				if capture.name == name {
					return capture_one_field(capture, rest)
				}
			}
			return {}, fmt.aprintf("no capture named %q", name, allocator = context.allocator)
		}
		if index, parse_ok := strconv.parse_int(head); parse_ok {
			if index < 0 || index >= len(captures) {
				return {}, fmt.aprintf(
					"capture index %d is out of range",
					index,
					allocator = context.allocator,
				)
			}
			return capture_one_field(captures[index], tail)
		}
	}
	return capture_field(capture_summary(captures), path)
}

@(private)
capture_one_field :: proc(capture: Capture_Result, path: string) -> (Check_Value, string) {
	switch path {
	case "delta_mean":
		return {kind = .Number, number = f64(capture.delta_mean)}, ""
	case "delta_max":
		return {kind = .Number, number = f64(capture.delta_max)}, ""
	case "delta_over_16":
		return {kind = .Number, number = f64(capture.delta_over_16)}, ""
	case "frame":
		return {kind = .Number, number = f64(capture.frame)}, ""
	case "written_width":
		return {kind = .Number, number = f64(capture.written_width)}, ""
	case "written_height":
		return {kind = .Number, number = f64(capture.written_height)}, ""
	case "render_digest":
		return {kind = .String, text = capture.render_digest}, ""
	}
	return capture_field(capture_summary([]Capture_Result{capture}), path)
}

check_value_display :: proc(value: Check_Value, allocator: mem.Allocator) -> string {
	switch value.kind {
	case .Number:
		return fmt.aprintf("%g", value.number, allocator = allocator)
	case .Bool:
		return strings.clone(value.boolean ? "true" : "false", allocator)
	case .String:
		return strings.clone(value.text, allocator)
	}
	return ""
}
