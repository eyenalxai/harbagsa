#+vet explicit-allocators
package harness

import "core:encoding/json"
import "core:mem"
import "core:strings"

Perf_Command :: struct {
	frames:    int,
	warmup:    int,
	prime:     f64,
	name:      string,
	has_name:  bool,
	trace:     string,
	has_trace: bool,
}

@(private)
parse_perf :: proc(object: json.Object, allocator: mem.Allocator) -> (Command, string) {
	if key, unknown := json_unknown_key(object, {"cmd", "frames", "warmup", "prime", "name", "trace"}); unknown {
		return {}, format_error("unknown key %q", key)
	}
	command := Command {
		kind = .Perf,
		perf = {
			frames = PERF_DEFAULT_FRAMES,
			warmup = PERF_DEFAULT_WARMUP,
			prime  = PERF_DEFAULT_PRIME,
			name   = "perf",
		},
	}
	if value, has := json_get(object, "frames"); has {
		frames, ok := json_integer(value)
		if !ok || frames < 1 || frames > MAX_PERF_FRAMES {
			return {}, format_error("'frames' must be an integer in [1, %d]", MAX_PERF_FRAMES)
		}
		command.perf.frames = frames
	}
	if value, has := json_get(object, "warmup"); has {
		warmup, ok := json_integer(value)
		if !ok || warmup < 0 || warmup > MAX_PERF_FRAMES {
			return {}, format_error("'warmup' must be an integer in [0, %d]", MAX_PERF_FRAMES)
		}
		command.perf.warmup = warmup
	}
	if value, has := json_get(object, "prime"); has {
		prime, ok := json_number(value)
		if !ok || prime < 0 || prime > MAX_PERF_PRIME {
			return {}, format_error("'prime' must be a number in [0, %g]", MAX_PERF_PRIME)
		}
		command.perf.prime = prime
	}
	perf_name: string
	has_perf_name := false
	if value, has := json_get(object, "name"); has {
		name, ok := json_string(value)
		if !ok || len(name) > MAX_PERF_NAME || !valid_capture_name(name) {
			return {}, format_error(
				"'name' must be 1 to %d letters, digits, '-' or '_'",
				MAX_PERF_NAME,
			)
		}
		perf_name = name
		has_perf_name = true
	}
	if value, has := json_get(object, "trace"); has {
		path, ok := json_string(value)
		if !ok || len(path) == 0 || len(path) > MAX_PERF_TRACE_PATH {
			return {}, format_error("'trace' must be a path of 1 to %d characters", MAX_PERF_TRACE_PATH)
		}
		command.perf.trace = strings.clone(path, allocator)
		command.perf.has_trace = true
	}
	if has_perf_name {
		command.perf.name = strings.clone(perf_name, allocator)
		command.perf.has_name = true
	}
	return command, ""
}
