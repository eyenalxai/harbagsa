#+vet explicit-allocators
package harness

import "core:fmt"
import "core:mem"
import "core:strings"

import "src:digest"

// One `--param` flag. The name is a scenario parameter and the values run in the
// order they were given.
Parameter_Sweep :: struct {
	name:   string,
	values: []string,
}

Sweep_Run :: struct {
	parameters: []Scenario_Parameter `json:"parameters"`,
	run_dir:    string               `json:"run_dir,omitempty"`,
	report:     string               `json:"report,omitempty"`,
	state:      string               `json:"state,omitempty"`,
	digest:     string               `json:"digest,omitempty"`,
	exit_code:  int                  `json:"exit_code"`,
	ok:         bool                 `json:"ok"`,
	error:      string               `json:"error,omitempty"`,
}

Sweep_Report :: struct {
	ok:        bool        `json:"ok"`,
	exit_code: int         `json:"exit_code"`,
	scenario:  string      `json:"scenario"`,
	runs:      []Sweep_Run `json:"runs"`,
}

parse_parameter_sweep :: proc(
	text: string,
	allocator: mem.Allocator,
) -> (
	Parameter_Sweep,
	string,
) {
	separator := strings.index_byte(text, '=')
	if separator <= 0 || separator + 1 >= len(text) {
		return {}, format_error("%s", "--param needs NAME=VALUE[,VALUE...]")
	}
	name := text[:separator]
	if !valid_capture_name(name) {
		return {}, format_error(
			"%s",
			"--param NAME must use only letters, digits, '-' and '_'",
		)
	}
	values := strings.split(text[separator + 1:], ",", allocator)
	if len(values) > MAX_SWEEP_VALUES {
		delete(values, allocator)
		return {}, fmt.aprintf(
			"--param %s accepts at most %d values",
			name,
			MAX_SWEEP_VALUES,
			allocator = allocator,
		)
	}
	for value, index in values {
		if value == "" {
			delete(values, allocator)
			return {}, fmt.aprintf("--param %s has an empty value", name, allocator = allocator)
		}
		for earlier in values[:index] {
			if earlier == value {
				delete(values, allocator)
				return {}, fmt.aprintf(
					"--param %s repeats the value %q",
					name,
					value,
					allocator = allocator,
				)
			}
		}
	}
	return {name = name, values = values}, ""
}

sweep_combination_count :: proc(parameters: []Parameter_Sweep) -> int {
	count := 1
	for parameter in parameters {
		values := len(parameter.values)
		if values == 0 {
			return 0
		}
		if count > MAX_SWEEP_RUNS / values {
			return MAX_SWEEP_RUNS + 1
		}
		count *= values
	}
	return count
}

sweep_combination :: proc(
	parameters: []Parameter_Sweep,
	index: int,
	buffer: []Parameter_Override,
) -> []Parameter_Override {
	remaining := index
	for position := len(parameters) - 1; position >= 0; position -= 1 {
		radix := len(parameters[position].values)
		value_index := remaining % radix
		remaining /= radix
		buffer[position] = {
			name  = parameters[position].name,
			value = parameters[position].values[value_index],
		}
	}
	return buffer[:len(parameters)]
}

// The label names the values so a run directory reads like the command line.
// A value that needs a replacement character appends a hash, which keeps two
// different values from sharing one directory.
sweep_label :: proc(overrides: []Parameter_Override, allocator: mem.Allocator) -> string {
	builder := strings.builder_make(allocator)
	replaced := false
	for override, index in overrides {
		if index > 0 {
			strings.write_byte(&builder, ',')
		}
		strings.write_string(&builder, override.name)
		strings.write_byte(&builder, '=')
		for character in override.value {
			if sweep_label_character(character) {
				strings.write_byte(&builder, u8(character))
			} else {
				strings.write_byte(&builder, '_')
				replaced = true
			}
		}
	}
	label := strings.to_string(builder)
	if !replaced && len(label) <= 120 {
		return label
	}

	hash := digest.fnv()
	for override in overrides {
		digest.write_bytes(&hash, transmute([]u8)override.name)
		digest.write_bytes(&hash, []u8{0})
		digest.write_bytes(&hash, transmute([]u8)override.value)
	}
	suffix := digest.hex(hash, context.temp_allocator)
	trimmed := label[:min(len(label), 100)]
	tagged := fmt.aprintf("%s-%s", trimmed, suffix[:4], allocator = allocator)
	delete(label, allocator)
	return tagged
}

@(private)
sweep_label_character :: proc(character: rune) -> bool {
	switch character {
	case 'a' ..= 'z', 'A' ..= 'Z', '0' ..= '9', '.', '-', '_', '+':
		return true
	}
	return false
}
