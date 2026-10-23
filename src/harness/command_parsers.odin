#+vet explicit-allocators
package harness

import "core:encoding/json"
import "core:mem"
import "core:strings"

@(private)
parse_look :: proc(object: json.Object) -> (Command, string) {
	if key, unknown := json_unknown_key(object, {"cmd", "dx", "dy"}); unknown {
		return {}, format_error("unknown key %q", key)
	}
	dx, dx_ok := number_field(object, "dx")
	dy, dy_ok := number_field(object, "dy")
	if !dx_ok || !dy_ok {
		return {}, "look needs numeric 'dx' and 'dy'"
	}
	return {kind = .Look, look = {dx = f32(dx), dy = f32(dy)}}, ""
}

@(private)
parse_face :: proc(object: json.Object) -> (Command, string) {
	if key, unknown := json_unknown_key(object, {"cmd", "yaw", "pitch"}); unknown {
		return {}, format_error("unknown key %q", key)
	}
	yaw, yaw_ok := number_field(object, "yaw")
	pitch, pitch_ok := number_field(object, "pitch")
	if !yaw_ok || !pitch_ok {
		return {}, "face needs numeric 'yaw' and 'pitch'"
	}
	return {kind = .Face, face = {yaw = f32(yaw), pitch = f32(pitch)}}, ""
}

@(private)
parse_input :: proc(object: json.Object) -> (Command, string) {
	if key, unknown := json_unknown_key(object, {"cmd", "forward", "right", "jump"}); unknown {
		return {}, format_error("unknown key %q", key)
	}
	command := Command{kind = .Input}
	if value, has := json_get(object, "forward"); has {
		forward, ok := json_number(value)
		if !ok || forward < -1 || forward > 1 {
			return {}, "'forward' must be a number in [-1, 1]"
		}
		command.input.forward = f32(forward)
		command.input.has_forward = true
	}
	if value, has := json_get(object, "right"); has {
		right, ok := json_number(value)
		if !ok || right < -1 || right > 1 {
			return {}, "'right' must be a number in [-1, 1]"
		}
		command.input.right = f32(right)
		command.input.has_right = true
	}
	if value, has := json_get(object, "jump"); has {
		jump, ok := json_boolean(value)
		if !ok {
			return {}, "'jump' must be a boolean"
		}
		command.input.jump = jump
		command.input.has_jump = true
	}
	return command, ""
}

@(private)
parse_step :: proc(object: json.Object) -> (Command, string) {
	if key, unknown := json_unknown_key(object, {"cmd", "frames"}); unknown {
		return {}, format_error("unknown key %q", key)
	}
	frames, ok := integer_field(object, "frames")
	if !ok || frames < 1 || frames > MAX_STEP_FRAMES {
		return {}, format_error("'frames' must be an integer in [1, %d]", MAX_STEP_FRAMES)
	}
	return {kind = .Step, step = {frames = frames}}, ""
}

@(private)
parse_capture :: proc(object: json.Object, allocator: mem.Allocator) -> (Command, string) {
	if key, unknown := json_unknown_key(object, {"cmd", "name", "frame", "alpha"}); unknown {
		return {}, format_error("unknown key %q", key)
	}
	command := Command{kind = .Capture}
	if value, has := json_get(object, "name"); has {
		name, ok := json_string(value)
		if !ok || !valid_capture_name(name) {
			return {}, "'name' must use only letters, digits, '-' and '_'"
		}
		command.capture.name = strings.clone(name, allocator)
	}
	if value, has := json_get(object, "frame"); has {
		frame, ok := json_integer(value)
		if !ok || frame < 0 {
			return {}, "'frame' must be a non-negative integer"
		}
		command.capture.frame = frame
		command.capture.has_frame = true
	}
	if value, has := json_get(object, "alpha"); has {
		alpha, ok := json_number(value)
		if !ok || alpha < 0 || alpha > 1 {
			return {}, "'alpha' must be a number in [0, 1]"
		}
		command.capture.alpha = f32(alpha)
		command.capture.has_alpha = true
	}
	return command, ""
}

@(private)
parse_camera :: proc(object: json.Object) -> (Command, string) {
	if key, unknown := json_unknown_key(object, {"cmd", "position", "yaw", "pitch", "clear"}); unknown {
		return {}, format_error("unknown key %q", key)
	}
	command := Command{kind = .Camera}
	if value, has := json_get(object, "clear"); has {
		clear, ok := json_boolean(value)
		if !ok {
			return {}, "'clear' must be a boolean"
		}
		command.camera.clear = clear
	}
	if command.camera.clear {
		return command, ""
	}
	position, position_ok := vec3_field(object, "position")
	yaw, yaw_ok := number_field(object, "yaw")
	pitch, pitch_ok := number_field(object, "pitch")
	if !position_ok || !yaw_ok || !pitch_ok {
		return {}, "camera needs 'position', 'yaw' and 'pitch', or 'clear'"
	}
	command.camera.position = position
	command.camera.yaw = f32(yaw)
	command.camera.pitch = f32(pitch)
	return command, ""
}

@(private)
parse_view :: proc(object: json.Object) -> (Command, string) {
	if key, unknown := json_unknown_key(object, {"cmd", "hud", "debug", "hint"}); unknown {
		return {}, format_error("unknown key %q", key)
	}
	command := Command{kind = .View}
	if value, has := json_get(object, "hud"); has {
		hud, ok := json_boolean(value)
		if !ok {
			return {}, "'hud' must be a boolean"
		}
		command.view.hud = hud
		command.view.has_hud = true
	}
	if value, has := json_get(object, "debug"); has {
		debug, ok := json_boolean(value)
		if !ok {
			return {}, "'debug' must be a boolean"
		}
		command.view.debug = debug
		command.view.has_debug = true
	}
	if value, has := json_get(object, "hint"); has {
		hint, ok := json_boolean(value)
		if !ok {
			return {}, "'hint' must be a boolean"
		}
		command.view.hint = hint
		command.view.has_hint = true
	}
	return command, ""
}

@(private)
parse_check :: proc(object: json.Object, allocator: mem.Allocator) -> (Command, string) {
	if key, unknown := json_unknown_key(object, {"cmd", "field", "op", "value"}); unknown {
		return {}, format_error("unknown key %q", key)
	}
	field, field_ok := string_field(object, "field")
	op_name, op_ok := string_field(object, "op")
	if !field_ok || !op_ok {
		return {}, "check needs string 'field' and 'op'"
	}
	op, parsed_op := check_op_parse(op_name)
	if !parsed_op {
		return {}, format_error("unknown check op %q", op_name)
	}
	value, value_ok := json_get(object, "value")
	if !value_ok {
		return {}, "check needs 'value'"
	}
	check_value, value_error := parse_check_value(value, allocator)
	if value_error != "" {
		return {}, value_error
	}
	return {
		kind = .Check,
		check = {
			field = strings.clone(field, allocator),
			op = op,
			value = check_value,
		},
	}, ""
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
	return {}, "check 'value' must be a number, boolean, or string"
}

@(private)
parse_record :: proc(object: json.Object, allocator: mem.Allocator) -> (Command, string) {
	if key, unknown := json_unknown_key(object, {"cmd", "path"}); unknown {
		return {}, format_error("unknown key %q", key)
	}
	command := Command{kind = .Record}
	if value, has := json_get(object, "path"); has {
		path, ok := json_string(value)
		if !ok || path == "" {
			return {}, "'path' must be a non-empty string"
		}
		command.record.path = strings.clone(path, allocator)
		command.record.has_path = true
	}
	return command, ""
}

@(private)
parse_replay :: proc(object: json.Object, allocator: mem.Allocator) -> (Command, string) {
	if key, unknown := json_unknown_key(object, {"cmd", "path"}); unknown {
		return {}, format_error("unknown key %q", key)
	}
	path, ok := string_field(object, "path")
	if !ok || path == "" {
		return {}, "replay needs a non-empty 'path'"
	}
	return {kind = .Replay, replay = {path = strings.clone(path, allocator)}}, ""
}

@(private)
number_field :: proc(object: json.Object, key: string) -> (value: f64, ok: bool) {
	value_json, has := json_get(object, key)
	if !has {
		return 0, false
	}
	return json_number(value_json)
}

@(private)
integer_field :: proc(object: json.Object, key: string) -> (value: int, ok: bool) {
	value_json, has := json_get(object, key)
	if !has {
		return 0, false
	}
	return json_integer(value_json)
}

@(private)
string_field :: proc(object: json.Object, key: string) -> (value: string, ok: bool) {
	value_json, has := json_get(object, key)
	if !has {
		return "", false
	}
	return json_string(value_json)
}

@(private)
vec3_field :: proc(object: json.Object, key: string) -> (value: [3]f32, ok: bool) {
	value_json, has := json_get(object, key)
	if !has {
		return {}, false
	}
	array, array_ok := json_array(value_json)
	if !array_ok || len(array) != 3 {
		return {}, false
	}
	for index in 0 ..< 3 {
		number, number_ok := json_number(array[index])
		if !number_ok {
			return {}, false
		}
		value[index] = f32(number)
	}
	return value, true
}
