#+vet explicit-allocators
package harness

import "core:encoding/json"
import "core:fmt"
import "core:mem"
import "core:slice"

@(private)
scenario_step :: proc(value: json.Value) -> (Step, string) {
	object, object_ok := json_object(value)
	if !object_ok {
		return {}, format_error("step must be an object")
	}
	if key, unknown := json_unknown_key(object, {"frames", "forward", "right", "jump", "look"}); unknown {
		return {}, fmt.aprintf("unknown key %q", key, allocator = context.allocator)
	}
	frames, frames_error := parse_frames(object)
	if frames_error != "" {
		return {}, frames_error
	}
	input, input_error := parse_input_fields(object)
	if input_error != "" {
		return {}, input_error
	}
	step := Step {
		frames      = frames,
		forward     = input.forward,
		right       = input.right,
		jump        = input.jump,
		has_forward = input.has_forward,
		has_right   = input.has_right,
		has_jump    = input.has_jump,
	}
	if look_value, has := json_get(object, "look"); has {
		look_array, array_ok := json_array(look_value)
		if !array_ok || len(look_array) != 2 {
			return {}, format_error("'look' must be [dx, dy]")
		}
		dx, dx_ok := json_number(look_array[0])
		dy, dy_ok := json_number(look_array[1])
		if !dx_ok || !dy_ok {
			return {}, format_error("'look' must be [dx, dy] numbers")
		}
		step.look_dx = f32(dx)
		step.look_dy = f32(dy)
		step.has_look = true
	}
	return step, ""
}

@(private)
scenario_capture_frames :: proc(
	object: json.Object,
	total: int,
	allocator: mem.Allocator,
) -> (
	frames: []int,
	error: string,
) {
	value, has_capture := json_get(object, "capture")
	if !has_capture {
		result := make([]int, 1, allocator)
		result[0] = total
		return result, ""
	}
	array, array_ok := json_array(value)
	if !array_ok {
		return nil, "scenario 'capture' must be an array of frame numbers"
	}
	collected := make([dynamic]int, 0, len(array) + 1, allocator)
	defer delete(collected)
	for item, index in array {
		frame, frame_ok := json_integer(item)
		if !frame_ok || frame < 0 || frame > total {
			return nil, fmt.aprintf(
				"capture %d: frame must be an integer in [0, %d]",
				index,
				total,
				allocator = context.allocator,
			)
		}
		append(&collected, frame)
	}
	if len(collected) > 0 {
		slice.sort(collected[:])
		unique := 0
		for frame in collected {
			if unique == 0 || collected[unique - 1] != frame {
				collected[unique] = frame
				unique += 1
			}
		}
		resize(&collected, unique)
		if !slice.contains(collected[:], total) {
			append(&collected, total)
		}
	}
	result := make([]int, len(collected), allocator)
	copy(result, collected[:])
	return result, ""
}
