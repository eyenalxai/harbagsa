#+vet explicit-allocators
package harness

import "core:encoding/json"

Settle_Command :: struct {
	frames: int,
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
