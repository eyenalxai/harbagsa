#+vet explicit-allocators
package harness

import "core:encoding/json"
import "core:mem"
import "core:strings"

import "src:renderer"

@(private)
parse_capture :: proc(object: json.Object, allocator: mem.Allocator) -> (Command, string) {
	if key, unknown := json_unknown_key(object, {"cmd", "name", "frame", "alpha", "target", "format"}); unknown {
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
	if value, has := json_get(object, "target"); has {
		name, ok := json_string(value)
		target, target_ok := renderer.capture_target_parse(name)
		if !ok || !target_ok {
			return {}, "'target' must be color, velocity, history, depth, or scene_color"
		}
		command.capture.target = target
	}
	if value, has := json_get(object, "format"); has {
		name, ok := json_string(value)
		format, format_ok := capture_format_parse(name)
		if !ok || !format_ok {
			return {}, "'format' must be png, float, raw, or stats"
		}
		command.capture.format = format
	} else {
		command.capture.format = command.capture.target == .Color ? .Png : .Stats
	}
	if command.capture.format == .Png && command.capture.target != .Color {
		return {}, "a png capture needs the color target"
	}
	if (command.capture.format == .Float || command.capture.format == .Raw) &&
	   command.capture.target == .Color {
		return {}, "a float or raw capture needs an intermediate target"
	}
	return command, ""
}
