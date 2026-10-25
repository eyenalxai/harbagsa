#+vet explicit-allocators
package harness

import "core:encoding/json"
import "core:mem"
import "core:strings"

import "src:reference"

// One scene of the reference comparison. `gi` and `direct` name two
// `scene_color` float captures of the same view that differ only in the gather
// toggle, so their difference is the probe indirect term.
Reference_Command :: struct {
	name:      string,
	gi:        string,
	direct:    string,
	settings:  reference.Settings,
	tolerance: reference.Tolerance,
}

DEFAULT_REFERENCE_TOLERANCE :: reference.Tolerance {
	ratio_min         = 0.75,
	ratio_max         = 1.33,
	error_max         = 0.35,
	colour_max        = 0.12,
	zero_fraction_max = 0.01,
}

@(private)
parse_reference :: proc(object: json.Object, allocator: mem.Allocator) -> (Command, string) {
	if key, unknown := json_unknown_key(
		object,
		{"cmd", "name", "gi", "direct", "samples", "bounces", "stride", "sun_samples", "tolerance"},
	); unknown {
		return {}, format_error("unknown key %q", key)
	}
	command := Command{kind = .Reference}
	command.reference.settings = {
		samples     = reference.DEFAULT_SAMPLES,
		bounces     = reference.DEFAULT_BOUNCES,
		stride      = reference.DEFAULT_STRIDE,
		sun_samples = reference.DEFAULT_SUN_SAMPLES,
	}
	command.reference.tolerance = DEFAULT_REFERENCE_TOLERANCE

	name, name_error := reference_name(object, "name", allocator)
	if name_error != "" {
		return {}, name_error
	}
	gi, gi_error := reference_name(object, "gi", allocator)
	if gi_error != "" {
		delete(name, allocator)
		return {}, gi_error
	}
	direct, direct_error := reference_name(object, "direct", allocator)
	if direct_error != "" {
		delete(name, allocator)
		delete(gi, allocator)
		return {}, direct_error
	}
	command.reference.name = name
	command.reference.gi = gi
	command.reference.direct = direct

	settings := &command.reference.settings
	if value, has := json_get(object, "samples"); has {
		samples, ok := json_integer(value)
		if !ok || samples < 1 || samples > 4096 {
			return {}, format_error("%s", "'samples' must be an integer in [1, 4096]")
		}
		settings.samples = samples
	}
	if value, has := json_get(object, "bounces"); has {
		bounces, ok := json_integer(value)
		if !ok || bounces < 2 || bounces > reference.MAX_BOUNCES {
			return {}, format_error("%s", "'bounces' must be in [2, 8]")
		}
		settings.bounces = bounces
	}
	if value, has := json_get(object, "stride"); has {
		stride, ok := json_integer(value)
		if !ok || stride < 1 || stride > 512 {
			return {}, format_error("%s", "'stride' must be an integer in [1, 512]")
		}
		settings.stride = stride
	}
	if value, has := json_get(object, "sun_samples"); has {
		sun_samples, ok := json_integer(value)
		if !ok || sun_samples < 1 || sun_samples > 256 {
			return {}, format_error("%s", "'sun_samples' must be an integer in [1, 256]")
		}
		settings.sun_samples = sun_samples
	}
	if value, has := json_get(object, "tolerance"); has {
		tolerance_object, ok := json_object(value)
		if !ok {
			return {}, format_error("%s", "'tolerance' must be an object")
		}
		if tolerance_error := parse_reference_tolerance(tolerance_object, &command.reference); tolerance_error != "" {
			return {}, tolerance_error
		}
	}
	return command, ""
}

@(private)
reference_name :: proc(object: json.Object, key: string, allocator: mem.Allocator) -> (string, string) {
	value, has := json_get(object, key)
	if !has {
		return "", format_error("'%s' is required", key)
	}
	text, ok := json_string(value)
	if !ok || text == "" {
		return "", format_error("'%s' must be a non-empty string", key)
	}
	return strings.clone(text, allocator), ""
}

@(private)
parse_reference_tolerance :: proc(object: json.Object, command: ^Reference_Command) -> string {
	if key, unknown := json_unknown_key(
		object,
		{"ratio_min", "ratio_max", "error_max", "colour_max", "zero_fraction_max"},
	); unknown {
		return format_error("unknown tolerance key %q", key)
	}
	tolerance := &command.tolerance
	if value, has := json_get(object, "ratio_min"); has {
		number, ok := json_number(value)
		if !ok || number <= 0 {
			return format_error("%s", "'ratio_min' must be a positive number")
		}
		tolerance.ratio_min = f32(number)
	}
	if value, has := json_get(object, "ratio_max"); has {
		number, ok := json_number(value)
		if !ok || number <= 0 {
			return format_error("%s", "'ratio_max' must be a positive number")
		}
		tolerance.ratio_max = f32(number)
	}
	if value, has := json_get(object, "error_max"); has {
		number, ok := json_number(value)
		if !ok || number < 0 {
			return format_error("%s", "'error_max' must be a non-negative number")
		}
		tolerance.error_max = f32(number)
	}
	if value, has := json_get(object, "colour_max"); has {
		number, ok := json_number(value)
		if !ok || number < 0 {
			return format_error("%s", "'colour_max' must be a non-negative number")
		}
		tolerance.colour_max = f32(number)
	}
	if value, has := json_get(object, "zero_fraction_max"); has {
		number, ok := json_number(value)
		if !ok || number < 0 {
			return format_error("%s", "'zero_fraction_max' must be a non-negative number")
		}
		tolerance.zero_fraction_max = f32(number)
	}
	if tolerance.ratio_max < tolerance.ratio_min {
		return format_error("%s", "the tolerance needs ratio_min <= ratio_max")
	}
	return ""
}

@(private)
destroy_reference :: proc(command: ^Command, allocator: mem.Allocator) {
	delete(command.reference.name, allocator)
	delete(command.reference.gi, allocator)
	delete(command.reference.direct, allocator)
	command^ = {}
}
