#+vet explicit-allocators
package harness

import "core:encoding/json"

// The pointer and relative-step half of the editor command. Every field maps to
// one game edit intent, so the harness can replay a keyboard session exactly.
Editor_Input :: struct {
	palette_step:       int,
	has_palette_step:   bool,
	palette_number:     int,
	has_palette_number: bool,
	flip_body:          bool,
	snap_toggle:        bool,
	turn:               int,
	has_turn:           bool,
	wheel:              int,
	has_wheel:          bool,
	large:              bool,
	primary:            bool,
	secondary:          bool,
	drag_move:          [2]f32,
	has_drag_move:      bool,
	drag_release:       bool,
}

@(private)
parse_editor_input :: proc(object: json.Object) -> (Editor_Input, string) {
	input: Editor_Input
	if value, has := json_get(object, "palette_step"); has {
		step, ok := json_integer(value)
		if !ok {
			return {}, format_error("%s", "'palette_step' must be an integer")
		}
		input.palette_step = step
		input.has_palette_step = true
	}
	if value, has := json_get(object, "palette_number"); has {
		number, ok := json_integer(value)
		if !ok || number < 1 || number > 9 {
			return {}, format_error("%s", "'palette_number' must be an integer in [1, 9]")
		}
		input.palette_number = number
		input.has_palette_number = true
	}
	if field_error := json_bool(object, "flip_body", &input.flip_body); field_error != "" {
		return {}, field_error
	}
	if field_error := json_bool(object, "snap_toggle", &input.snap_toggle); field_error != "" {
		return {}, field_error
	}
	if value, has := json_get(object, "turn"); has {
		steps, ok := json_integer(value)
		if !ok {
			return {}, format_error("%s", "'turn' must be an integer number of steps")
		}
		input.turn = steps
		input.has_turn = true
	}
	if value, has := json_get(object, "wheel"); has {
		steps, ok := json_integer(value)
		if !ok {
			return {}, format_error("%s", "'wheel' must be an integer number of steps")
		}
		input.wheel = steps
		input.has_wheel = true
	}
	if field_error := json_bool(object, "large", &input.large); field_error != "" {
		return {}, field_error
	}
	if field_error := json_bool(object, "primary", &input.primary); field_error != "" {
		return {}, field_error
	}
	if field_error := json_bool(object, "secondary", &input.secondary); field_error != "" {
		return {}, field_error
	}
	if _, has := json_get(object, "drag_move"); has {
		delta, ok := vec2_field(object, "drag_move")
		if !ok {
			return {}, format_error("%s", "'drag_move' must be two numbers")
		}
		input.drag_move = delta
		input.has_drag_move = true
	}
	if field_error := json_bool(object, "drag_release", &input.drag_release); field_error != "" {
		return {}, field_error
	}
	return input, ""
}
