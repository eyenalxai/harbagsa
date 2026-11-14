#+vet explicit-allocators
package harness

import "core:encoding/json"
import "core:mem"
import "core:strings"

@(private)
parse_ui_drag :: proc(raw: json.Value) -> (drag: Ui_Drag, error: string) {
	object, ok := json_object(raw)
	if !ok {
		return {}, format_error("%s", "'drag' must be an object")
	}
	if key, unknown := json_unknown_key(
		object,
		{"from", "dx", "dy", "steps", "hold", "cancel"},
	); unknown {
		return {}, format_error("unknown drag key %q", key)
	}
	from, has_from := json_get(object, "from")
	if !has_from {
		return {}, format_error("%s", "drag needs 'from'")
	}
	target, target_error := parse_ui_target(from, "drag.from")
	if target_error != "" {
		return {}, target_error
	}
	drag.target = target
	drag.steps = 1
	if raw_dx, has_dx := json_get(object, "dx"); has_dx {
		number, number_ok := json_number(raw_dx)
		if !number_ok {
			return {}, format_error("%s", "drag 'dx' must be a number")
		}
		drag.dx = f32(number)
	}
	if raw_dy, has_dy := json_get(object, "dy"); has_dy {
		number, number_ok := json_number(raw_dy)
		if !number_ok {
			return {}, format_error("%s", "drag 'dy' must be a number")
		}
		drag.dy = f32(number)
	}
	if raw_steps, has_steps := json_get(object, "steps"); has_steps {
		steps, steps_ok := json_integer(raw_steps)
		if !steps_ok || steps < 1 || steps > 64 {
			return {}, format_error("%s", "drag 'steps' must be in [1, 64]")
		}
		drag.steps = steps
	}
	if field_error := json_bool(object, "hold", &drag.hold); field_error != "" {
		return {}, field_error
	}
	if field_error := json_bool(object, "cancel", &drag.cancel); field_error != "" {
		return {}, field_error
	}
	if drag.hold && drag.cancel {
		return {}, format_error("%s", "drag cannot both hold and cancel")
	}
	return drag, ""
}

@(private)
parse_ui_wheel :: proc(raw: json.Value) -> (wheel: Ui_Wheel, error: string) {
	object, ok := json_object(raw)
	if !ok {
		return {}, format_error("%s", "'wheel' must be an object")
	}
	if key, unknown := json_unknown_key(object, {"at", "dx", "dy"}); unknown {
		return {}, format_error("unknown wheel key %q", key)
	}
	at, has_at := json_get(object, "at")
	if !has_at {
		return {}, format_error("%s", "wheel needs 'at'")
	}
	target, target_error := parse_ui_target(at, "wheel.at")
	if target_error != "" {
		return {}, target_error
	}
	wheel.target = target
	if raw_dx, has_dx := json_get(object, "dx"); has_dx {
		number, number_ok := json_number(raw_dx)
		if !number_ok {
			return {}, format_error("%s", "wheel 'dx' must be a number")
		}
		wheel.dx = f32(number)
	}
	if raw_dy, has_dy := json_get(object, "dy"); has_dy {
		number, number_ok := json_number(raw_dy)
		if !number_ok {
			return {}, format_error("%s", "wheel 'dy' must be a number")
		}
		wheel.dy = f32(number)
	}
	if wheel.dx == 0 && wheel.dy == 0 {
		return {}, format_error("%s", "wheel needs a non-zero 'dx' or 'dy'")
	}
	return wheel, ""
}

@(private)
parse_ui_expect :: proc(raw: json.Value) -> (expect: Ui_Expect, error: string) {
	object, ok := json_object(raw)
	if !ok {
		return {}, format_error("%s", "'expect' must be an object")
	}
	if key, unknown := json_unknown_key(object, {"kind", "id", "value", "scalar"}); unknown {
		return {}, format_error("unknown expect key %q", key)
	}
	kind_name, has_kind := string_field(object, "kind")
	if !has_kind {
		return {}, format_error("%s", "expect needs 'kind'")
	}
	kind, kind_ok := ui_action_kind_from_name(kind_name)
	if !kind_ok {
		return {}, format_error("unknown action kind %q", kind_name)
	}
	expect.kind = kind
	if raw_id, has_id := json_get(object, "id"); has_id {
		number, number_ok := json_integer(raw_id)
		if !number_ok || number < 0 || number > int(max(u32)) {
			return {}, format_error("%s", "expect 'id' must be in the u32 range")
		}
		expect.id = u32(number)
		expect.has_id = true
	}
	if raw_value, has_value := json_get(object, "value"); has_value {
		number, number_ok := json_integer(raw_value)
		if !number_ok || number < int(min(i32)) || number > int(max(i32)) {
			return {}, format_error("%s", "expect 'value' must fit i32")
		}
		expect.value = i32(number)
		expect.has_value = true
	}
	if raw_scalar, has_scalar := json_get(object, "scalar"); has_scalar {
		number, number_ok := json_number(raw_scalar)
		if !number_ok {
			return {}, format_error("%s", "expect 'scalar' must be a number")
		}
		expect.scalar = f32(number)
		expect.has_scalar = true
	}
	return expect, ""
}

@(private)
parse_state_expects :: proc(
	value: json.Value,
	allocator: mem.Allocator,
) -> ([]State_Expect, string) {
	object, ok := json_object(value)
	if !ok {
		return nil, format_error("%s", "'expect_state' must be an object")
	}
	expects := make([dynamic]State_Expect, 0, len(object), allocator)
	for path, expected in object {
		expect: State_Expect
		expect.path = strings.clone(path, allocator)
		#partial switch checked in expected {
		case json.Integer:
			expect.value = {kind = .Number, number = f64(checked)}
		case json.Float:
			expect.value = {kind = .Number, number = checked}
		case json.Boolean:
			expect.value = {kind = .Bool, boolean = checked}
		case json.String:
			expect.value = {kind = .String, text = strings.clone(checked, allocator)}
		case:
			for &entry in expects {
				delete(entry.path, allocator)
				if entry.value.kind == .String {
					delete(entry.value.text, allocator)
				}
			}
			delete(expects)
			delete(expect.path, allocator)
			return nil, format_error("expect_state %q must be a number, boolean, or string", path)
		}
		append(&expects, expect)
	}
	return expects[:], ""
}

state_expects_destroy :: proc(expects: []State_Expect, allocator: mem.Allocator) {
	for &expect in expects {
		delete(expect.path, allocator)
		if expect.value.kind == .String {
			delete(expect.value.text, allocator)
		}
	}
	if expects != nil {
		delete(expects, allocator)
	}
}

