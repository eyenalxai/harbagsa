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
			return {}, "'palette_step' must be an integer"
		}
		input.palette_step = step
		input.has_palette_step = true
	}
	if value, has := json_get(object, "palette_number"); has {
		number, ok := json_integer(value)
		if !ok || number < 1 || number > 9 {
			return {}, "'palette_number' must be an integer in [1, 9]"
		}
		input.palette_number = number
		input.has_palette_number = true
	}
	if value, has := json_get(object, "flip_body"); has {
		flag, ok := json_boolean(value)
		if !ok {
			return {}, "'flip_body' must be a boolean"
		}
		input.flip_body = flag
	}
	if value, has := json_get(object, "snap_toggle"); has {
		flag, ok := json_boolean(value)
		if !ok {
			return {}, "'snap_toggle' must be a boolean"
		}
		input.snap_toggle = flag
	}
	if value, has := json_get(object, "turn"); has {
		steps, ok := json_integer(value)
		if !ok {
			return {}, "'turn' must be an integer number of steps"
		}
		input.turn = steps
		input.has_turn = true
	}
	if value, has := json_get(object, "wheel"); has {
		steps, ok := json_integer(value)
		if !ok {
			return {}, "'wheel' must be an integer number of steps"
		}
		input.wheel = steps
		input.has_wheel = true
	}
	if value, has := json_get(object, "large"); has {
		flag, ok := json_boolean(value)
		if !ok {
			return {}, "'large' must be a boolean"
		}
		input.large = flag
	}
	if value, has := json_get(object, "primary"); has {
		flag, ok := json_boolean(value)
		if !ok {
			return {}, "'primary' must be a boolean"
		}
		input.primary = flag
	}
	if value, has := json_get(object, "secondary"); has {
		flag, ok := json_boolean(value)
		if !ok {
			return {}, "'secondary' must be a boolean"
		}
		input.secondary = flag
	}
	if _, has := json_get(object, "drag_move"); has {
		delta, ok := vec2_field(object, "drag_move")
		if !ok {
			return {}, "'drag_move' must be two numbers"
		}
		input.drag_move = delta
		input.has_drag_move = true
	}
	if value, has := json_get(object, "drag_release"); has {
		flag, ok := json_boolean(value)
		if !ok {
			return {}, "'drag_release' must be a boolean"
		}
		input.drag_release = flag
	}
	return input, ""
}
