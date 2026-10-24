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
	input, input_error := parse_input_fields(object)
	if input_error != "" {
		return {}, input_error
	}
	return {kind = .Input, input = input}, ""
}

parse_input_fields :: proc(object: json.Object) -> (input: Input_Command, error: string) {
	if value, has := json_get(object, "forward"); has {
		forward, ok := json_number(value)
		if !ok || forward < -1 || forward > 1 {
			return {}, "'forward' must be a number in [-1, 1]"
		}
		input.forward = f32(forward)
		input.has_forward = true
	}
	if value, has := json_get(object, "right"); has {
		right, ok := json_number(value)
		if !ok || right < -1 || right > 1 {
			return {}, "'right' must be a number in [-1, 1]"
		}
		input.right = f32(right)
		input.has_right = true
	}
	if value, has := json_get(object, "jump"); has {
		jump, ok := json_boolean(value)
		if !ok {
			return {}, "'jump' must be a boolean"
		}
		input.jump = jump
		input.has_jump = true
	}
	return input, ""
}

@(private)
parse_step :: proc(object: json.Object) -> (Command, string) {
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
parse_settle :: proc(object: json.Object) -> (Command, string) {
	if key, unknown := json_unknown_key(object, {"cmd", "frames"}); unknown {
		return {}, format_error("unknown key %q", key)
	}
	frames, frames_error := parse_frames(object)
	if frames_error != "" {
		return {}, frames_error
	}
	return {kind = .Settle, settle = {frames = frames}}, ""
}

parse_frames :: proc(object: json.Object) -> (frames: int, error: string) {
	value, ok := integer_field(object, "frames")
	if !ok || value < 1 || value > MAX_STEP_FRAMES {
		return 0, format_error("'frames' must be an integer in [1, %d]", MAX_STEP_FRAMES)
	}
	return value, ""
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
	view, view_error := parse_view_fields(object)
	if view_error != "" {
		return {}, view_error
	}
	return {kind = .View, view = view}, ""
}

parse_view_fields :: proc(object: json.Object) -> (view: View_Command, error: string) {
	if value, has := json_get(object, "hud"); has {
		flag, ok := json_boolean(value)
		if !ok {
			return {}, "'hud' must be a boolean"
		}
		view.hud = flag
		view.has_hud = true
	}
	if value, has := json_get(object, "debug"); has {
		flag, ok := json_boolean(value)
		if !ok {
			return {}, "'debug' must be a boolean"
		}
		view.debug = flag
		view.has_debug = true
	}
	if value, has := json_get(object, "hint"); has {
		flag, ok := json_boolean(value)
		if !ok {
			return {}, "'hint' must be a boolean"
		}
		view.hint = flag
		view.has_hint = true
	}
	return view, ""
}

@(private)
parse_check :: proc(object: json.Object, allocator: mem.Allocator) -> (Command, string) {
	if key, unknown := json_unknown_key(object, {"cmd", "field", "op", "value", "warmup"}); unknown {
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
	warmup := 0
	if warmup_value, has := json_get(object, "warmup"); has {
		parsed, parsed_ok := json_integer(warmup_value)
		if !parsed_ok || parsed < 0 {
			return {}, "'warmup' must be a non-negative integer"
		}
		warmup = int(parsed)
	}
	return {
		kind = .Check,
		check = {
			field = strings.clone(field, allocator),
			op = op,
			value = check_value,
			warmup = warmup,
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

