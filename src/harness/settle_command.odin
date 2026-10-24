#+vet explicit-allocators
package harness

import "core:encoding/json"

Settle_Command :: struct {
	frames:     int,
	has_frames: bool,
	converged:  bool,
}

@(private)
parse_settle :: proc(object: json.Object) -> (Command, string) {
	if key, unknown := json_unknown_key(object, {"cmd", "frames", "until"}); unknown {
		return {}, format_error("unknown key %q", key)
	}
	_, has_frames := json_get(object, "frames")
	if until_value, has_until := json_get(object, "until"); has_until {
		if has_frames {
			return {}, format_error("%s", "settle takes 'frames' or 'until', not both")
		}
		until, ok := json_string(until_value)
		if !ok || until != "converged" {
			return {}, format_error("%s", "settle 'until' must be \"converged\"")
		}
		return {kind = .Settle, settle = {converged = true}}, ""
	}
	frames, frames_error := parse_frames(object)
	if frames_error != "" {
		return {}, frames_error
	}
	return {kind = .Settle, settle = {frames = frames, has_frames = true}}, ""
}

parse_frames :: proc(object: json.Object) -> (frames: int, error: string) {
	value, ok := integer_field(object, "frames")
	if !ok || value < 1 || value > MAX_STEP_FRAMES {
		return 0, format_error("'frames' must be an integer in [1, %d]", MAX_STEP_FRAMES)
	}
	return value, ""
}
