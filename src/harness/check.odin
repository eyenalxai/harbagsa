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
	actual:   string `json:"actual,omitempty"`,
	ok:       bool   `json:"ok"`,
	error:    string `json:"error,omitempty"`,
}

Field_Value :: struct {
	kind:    Value_Kind,
	number:  f64,
	boolean: bool,
	text:    string,
}

check_evaluate :: proc(
	command: Check_Command,
	state: State,
	allocator: mem.Allocator,
) -> Check_Result {
	result := Check_Result {
		field = command.field,
		op = check_op_name(command.op),
		expected = check_value_display(command.value, allocator),
	}
	actual, field_error := state_field(state, command.field)
	if field_error != "" {
		result.error = field_error
		return result
	}
	result.actual = field_value_display(actual, allocator)
	ok, compare_error := check_compare(actual, command.op, command.value)
	if compare_error != "" {
		result.error = compare_error
		return result
	}
	result.ok = ok
	return result
}

check_result_destroy :: proc(result: ^Check_Result, allocator: mem.Allocator) {
	if result.expected != "" {
		delete(result.expected, allocator)
	}
	if result.actual != "" {
		delete(result.actual, allocator)
	}
	result^ = {}
}

check_compare :: proc(actual: Field_Value, op: Check_Op, expected: Check_Value) -> (bool, string) {
	if actual.kind != expected.kind {
		return false, "check value type does not match the field type"
	}
	switch actual.kind {
	case .Number:
		return compare_number(actual.number, op, expected.number)
	case .Bool:
		if op != .Eq && op != .Ne {
			return false, "boolean checks support only 'eq' and 'ne'"
		}
		equal := actual.boolean == expected.boolean
		return equal if op == .Eq else !equal, ""
	case .String:
		if op != .Eq && op != .Ne {
			return false, "string checks support only 'eq' and 'ne'"
		}
		equal := actual.text == expected.text
		return equal if op == .Eq else !equal, ""
	}
	return false, "unsupported check value"
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
	return false, "unknown check op"
}

state_field :: proc(state: State, path: string) -> (Field_Value, string) {
	if path == "frame" {
		return {kind = .Number, number = f64(state.frame)}, ""
	}
	if path == "digest" {
		return {kind = .String, text = state.digest}, ""
	}

	head, tail, has_tail := split_field(path)
	switch head {
	case "player":
		if !has_tail {
			return {}, "player needs a field"
		}
		return player_field(state.player, tail)
	case "crates":
		if !has_tail {
			return {}, "crates needs an index or 'count'"
		}
		return crates_field(state.crates, tail)
	}
	return {}, fmt.aprintf("unknown state field %q", path, allocator = context.allocator)
}

@(private)
player_field :: proc(player: Player_State, path: string) -> (Field_Value, string) {
	head, tail, has_tail := split_field(path)
	switch head {
	case "position":
		if !has_tail {
			return {}, "position needs an axis"
		}
		return vec_field(player.position, tail)
	case "eye":
		if !has_tail {
			return {}, "eye needs an axis"
		}
		return vec_field(player.eye, tail)
	case "velocity":
		if !has_tail {
			return {}, "velocity needs an axis"
		}
		return vec_field(player.velocity, tail)
	case "yaw":
		return {kind = .Number, number = f64(player.yaw)}, ""
	case "pitch":
		return {kind = .Number, number = f64(player.pitch)}, ""
	case "grounded":
		return {kind = .Bool, boolean = player.grounded}, ""
	}
	return {}, fmt.aprintf("unknown player field %q", path, allocator = context.allocator)
}

@(private)
crates_field :: proc(crates: []Crate_State, path: string) -> (Field_Value, string) {
	head, tail, has_tail := split_field(path)
	if head == "count" {
		return {kind = .Number, number = f64(len(crates))}, ""
	}
	index, parse_ok := strconv.parse_int(head)
	if !parse_ok || index < 0 || index >= len(crates) {
		return {}, fmt.aprintf("crate index %q is out of range", head, allocator = context.allocator)
	}
	if !has_tail {
		return {}, "crate needs 'position' or 'rotation'"
	}
	crate := crates[index]
	property, axis, has_axis := split_field(tail)
	switch property {
	case "position":
		if !has_axis {
			return {}, "crate position needs an axis"
		}
		return vec_field(crate.position, axis)
	case "rotation":
		if !has_axis {
			return {}, "crate rotation needs an axis"
		}
		return quat_field(crate.rotation, axis)
	}
	return {}, fmt.aprintf("unknown crate field %q", tail, allocator = context.allocator)
}

@(private)
vec_field :: proc(value: Vec_State, axis: string) -> (Field_Value, string) {
	switch axis {
	case "x":
		return {kind = .Number, number = f64(value.x)}, ""
	case "y":
		return {kind = .Number, number = f64(value.y)}, ""
	case "z":
		return {kind = .Number, number = f64(value.z)}, ""
	}
	return {}, fmt.aprintf("unknown axis %q", axis, allocator = context.allocator)
}

@(private)
quat_field :: proc(value: Quat_State, axis: string) -> (Field_Value, string) {
	switch axis {
	case "x":
		return {kind = .Number, number = f64(value.x)}, ""
	case "y":
		return {kind = .Number, number = f64(value.y)}, ""
	case "z":
		return {kind = .Number, number = f64(value.z)}, ""
	case "w":
		return {kind = .Number, number = f64(value.w)}, ""
	}
	return {}, fmt.aprintf("unknown rotation axis %q", axis, allocator = context.allocator)
}

@(private)
split_field :: proc(path: string) -> (head, tail: string, has_tail: bool) {
	index := strings.index_byte(path, '.')
	if index < 0 {
		return path, "", false
	}
	return path[:index], path[index + 1:], true
}

check_value_display :: proc(value: Check_Value, allocator: mem.Allocator) -> string {
	switch value.kind {
	case .Number:
		return fmt.aprintf("%g", value.number, allocator = allocator)
	case .Bool:
		return "true" if value.boolean else "false"
	case .String:
		return value.text
	}
	return ""
}

@(private)
field_value_display :: proc(value: Field_Value, allocator: mem.Allocator) -> string {
	switch value.kind {
	case .Number:
		return fmt.aprintf("%g", value.number, allocator = allocator)
	case .Bool:
		return "true" if value.boolean else "false"
	case .String:
		return value.text
	}
	return ""
}
