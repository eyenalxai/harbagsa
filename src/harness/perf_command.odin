#+vet explicit-allocators
package harness

import "core:encoding/json"
import "core:mem"
import "core:slice"
import "core:strings"

import "src:renderer"

Perf_Variant :: struct {
	name:    string,
	patch:   renderer.Renderer_Debug_Patch,
	reset:   Renderer_Debug_Resets,
}

Perf_Command :: struct {
	frames:     int,
	warmup:     int,
	prime:      f64,
	prime_once: bool `json:"-"`,
	name:       string,
	has_name:   bool,
	trace:      string,
	has_trace:  bool,
	variants:   []Perf_Variant,
	baseline:   string,
	rounds:     int,
	discard:    int,
}

@(private)
parse_perf :: proc(object: json.Object, allocator: mem.Allocator) -> (Command, string) {
	if key, unknown := json_unknown_key(
		object,
		{"cmd", "frames", "warmup", "prime", "name", "trace", "variants", "rounds", "baseline", "discard"},
	); unknown {
		return {}, format_error("unknown key %q", key)
	}
	command := Command {
		kind = .Perf,
		perf = {
			frames   = PERF_DEFAULT_FRAMES,
			warmup   = PERF_DEFAULT_WARMUP,
			prime    = PERF_DEFAULT_PRIME,
			name     = "perf",
			rounds   = 1,
			discard  = 1,
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
		if text, is_text := json_string(value); is_text {
			if text != "once" {
				return {}, format_error("%s", "'prime' must be a number or \"once\"")
			}
			command.perf.prime_once = true
		} else {
			prime, ok := json_number(value)
			if !ok || prime < 0 || prime > MAX_PERF_PRIME {
				return {}, format_error("'prime' must be a number in [0, %g] or \"once\"", MAX_PERF_PRIME)
			}
			command.perf.prime = prime
		}
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
	perf_trace: string
	has_perf_trace := false
	if value, has := json_get(object, "trace"); has {
		path, ok := json_string(value)
		if !ok || len(path) == 0 || len(path) > MAX_PERF_TRACE_PATH {
			return {}, format_error("'trace' must be a path of 1 to %d characters", MAX_PERF_TRACE_PATH)
		}
		perf_trace = path
		has_perf_trace = true
	}
	if value, has := json_get(object, "rounds"); has {
		rounds, ok := json_integer(value)
		if !ok || rounds < 1 || rounds > MAX_PERF_ROUNDS {
			return {}, format_error("'rounds' must be an integer in [1, %d]", MAX_PERF_ROUNDS)
		}
		command.perf.rounds = rounds
	}
	if value, has := json_get(object, "discard"); has {
		discard, ok := json_integer(value)
		if !ok || discard < 0 || discard > MAX_PERF_ROUNDS {
			return {}, format_error("'discard' must be an integer in [0, %d]", MAX_PERF_ROUNDS)
		}
		command.perf.discard = discard
	}
	if value, has := json_get(object, "variants"); has {
		variants, baseline, variant_error := parse_perf_variants(value, allocator)
		if variant_error != "" {
			perf_variants_destroy(variants, allocator)
			return {}, variant_error
		}
		command.perf.variants = variants
		command.perf.baseline = strings.clone(variants[baseline].name, allocator)
	}
	if value, has := json_get(object, "baseline"); has {
		name, ok := json_string(value)
		if !ok || name == "" {
			perf_command_variants_clear(&command, allocator)
			return {}, format_error("%s", "'baseline' must be a variant name")
		}
		if len(command.perf.variants) == 0 {
			return {}, format_error("%s", "'baseline' needs 'variants'")
		}
		if _, found := perf_variant_index(command.perf.variants, name); !found {
			perf_command_variants_clear(&command, allocator)
			return {}, format_error("'baseline' names unknown variant %q", name)
		}
		if command.perf.baseline != "" {
			delete(command.perf.baseline, allocator)
		}
		command.perf.baseline = strings.clone(name, allocator)
	}
	if has_perf_name {
		command.perf.name = strings.clone(perf_name, allocator)
		command.perf.has_name = true
	}
	if has_perf_trace {
		command.perf.trace = strings.clone(perf_trace, allocator)
		command.perf.has_trace = true
	}
	return command, ""
}

// A JSON object has no key order, so variants are taken in name order and the
// first name is the default baseline.
@(private)
parse_perf_variants :: proc(
	value: json.Value,
	allocator: mem.Allocator,
) -> ([]Perf_Variant, int, string) {
	object, object_ok := json_object(value)
	if !object_ok || len(object) == 0 {
		return nil, -1, format_error("%s", "'variants' must be an object with at least one variant")
	}
	if len(object) > MAX_PERF_VARIANTS {
		return nil, -1, format_error("'variants' holds at most %d variants", MAX_PERF_VARIANTS)
	}
	names := make([dynamic]string, 0, len(object), context.temp_allocator)
	defer delete(names)
	for name in object {
		append(&names, name)
	}
	slice.sort(names[:])

	variants := make([]Perf_Variant, len(names), allocator)
	for name, index in names {
		if len(name) == 0 || len(name) > MAX_PERF_NAME || !valid_capture_name(name) {
			return variants, -1, format_error(
				"variant names must be 1 to %d letters, digits, '-' or '_'",
				MAX_PERF_NAME,
			)
		}
		variant, variant_error := parse_perf_variant(name, object[name])
		if variant_error != "" {
			return variants, -1, variant_error
		}
		variant.name = strings.clone(name, allocator)
		variants[index] = variant
	}
	return variants, 0, ""
}

@(private)
parse_perf_variant :: proc(name: string, value: json.Value) -> (Perf_Variant, string) {
	object, object_ok := json_object(value)
	if !object_ok {
		return {}, format_error("variant %q must be an object", name)
	}
	allowed := make([dynamic]string, 0, len(RENDERER_DEBUG_FIELD_ROWS), context.temp_allocator)
	defer delete(allowed)
	for row in RENDERER_DEBUG_FIELD_ROWS {
		append(&allowed, row.name)
	}
	if key, unknown := json_unknown_key(object, allowed[:]); unknown {
		return {}, format_error("variant %q has unknown key %q", name, key)
	}
	fields, fields_error := renderer_debug_fields(object)
	if fields_error != "" {
		return {}, fields_error
	}
	return {name = name, patch = fields.patch, reset = fields.reset}, ""
}

perf_baseline_index :: proc(command: Perf_Command) -> int {
	if index, found := perf_variant_index(command.variants, command.baseline); found {
		return index
	}
	return 0
}

perf_variant_index :: proc(variants: []Perf_Variant, name: string) -> (int, bool) {
	for variant, index in variants {
		if variant.name == name {
			return index, true
		}
	}
	return -1, false
}

perf_command_variants_clear :: proc(command: ^Command, allocator: mem.Allocator) {
	if command.perf.baseline != "" {
		delete(command.perf.baseline, allocator)
		command.perf.baseline = ""
	}
	perf_variants_destroy(command.perf.variants, allocator)
	command.perf.variants = nil
}

perf_variants_destroy :: proc(variants: []Perf_Variant, allocator: mem.Allocator) {
	for variant in variants {
		if variant.name != "" {
			delete(variant.name, allocator)
		}
	}
	delete(variants, allocator)
}
