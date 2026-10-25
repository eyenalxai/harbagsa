#+vet explicit-allocators
package harness

import "core:encoding/json"
import "core:fmt"
import "core:mem"
import "core:slice"
import "core:strings"

import "src:digest"

Scenario_Parameter :: struct {
	name:  string `json:"name"`,
	value: string `json:"value"`,
}

Scenario_Source :: struct {
	path:       string               `json:"path"`,
	hash:       string               `json:"hash"`,
	parameters: []Scenario_Parameter `json:"parameters,omitempty"`,
}

// A scenario declares the gated capabilities its commands need, and the runner
// enables them for that run.
Scenario_Requirements :: struct {
	renderer_debug: bool `json:"renderer_debug"`,
}

Scenario :: struct {
	commands: [dynamic]Command,
	analysis: Analysis_Config,
	requires: Scenario_Requirements,
	source:   Scenario_Source,
	has_size: bool,
	size:     [2]u32,
}

// One run's value for a scenario parameter. The CLI sweep owns the strings.
Parameter_Override :: struct {
	name:  string,
	value: string,
}

scenario_parse :: proc(
	data: string,
	allocator: mem.Allocator,
	overrides: []Parameter_Override = nil,
) -> (Scenario, string) {
	return scenario_parse_with_base(data, "", overrides, allocator)
}

@(private)
scenario_parse_with_base :: proc(
	data: string,
	base_dir: string,
	overrides: []Parameter_Override,
	allocator: mem.Allocator,
) -> (Scenario, string) {
	value, parse_error := json.parse_string(data, .JSON, true, allocator)
	if parse_error != .None {
		return {}, fmt.aprintf("invalid JSON: %v", parse_error, allocator = allocator)
	}
	defer json.destroy_value(value, allocator)

	resolved, resolve_error := scenario_resolve(value, base_dir, 0, overrides, allocator)
	if resolve_error != "" {
		return {}, resolve_error
	}
	defer json.destroy_value(resolved, allocator)

	parameters := scenario_parameter_values(resolved, allocator)
	scenario, build_error := scenario_build(resolved, allocator)
	if build_error != "" {
		scenario_parameters_destroy(parameters, allocator)
		return {}, build_error
	}
	scenario.source.parameters = parameters
	scenario.source.hash = scenario_hash(data, parameters, allocator)
	return scenario, ""
}

@(private)
scenario_parameter_values :: proc(
	value: json.Value,
	allocator: mem.Allocator,
) -> []Scenario_Parameter {
	object, object_ok := json_object(value)
	if !object_ok {
		return nil
	}
	parameters_value, has_parameters := json_get(object, "parameters")
	if !has_parameters {
		return nil
	}
	parameters, parameters_ok := json_object(parameters_value)
	if !parameters_ok || len(parameters) == 0 {
		return nil
	}
	values := make([]Scenario_Parameter, len(parameters), allocator)
	index := 0
	for name, parameter in parameters {
		values[index] = {
			name  = strings.clone(name, allocator),
			value = strings.clone(scenario_parameter_text(parameter, context.temp_allocator), allocator),
		}
		index += 1
	}
	slice.sort_by(values, proc(a, b: Scenario_Parameter) -> bool {
		return a.name < b.name
	})
	return values
}

@(private)
scenario_parameters_destroy :: proc(values: []Scenario_Parameter, allocator: mem.Allocator) {
	for value in values {
		delete(value.name, allocator)
		delete(value.value, allocator)
	}
	delete(values, allocator)
}

@(private)
scenario_build :: proc(value: json.Value, allocator: mem.Allocator) -> (Scenario, string) {
	object, object_ok := json_object(value)
	if !object_ok {
		return {}, format_error("%s", "scenario must be a JSON object")
	}
	if key, unknown := json_unknown_key(
		object,
		{"version", "view", "checks", "commands", "renderer_debug", "requires", "analysis", "size", "extends", "parameters"},
	); unknown {
		return {}, fmt.aprintf("unknown scenario key %q", key, allocator = allocator)
	}

	scenario: Scenario
	scenario.analysis = analysis_config_default()
	scenario.commands = make([dynamic]Command, 0, 16, allocator)
	ok := false
	defer if !ok {
		scenario_destroy(&scenario, allocator)
	}

	if version_value, has_version := json_get(object, "version"); has_version {
		version, version_ok := json_integer(version_value)
		if !version_ok || version != 1 {
			return {}, format_error("%s", "scenario 'version' must be 1")
		}
	}

	if size_value, has_size := json_get(object, "size"); has_size {
		name, name_ok := json_string(size_value)
		if !name_ok {
			return {}, format_error("%s", "scenario 'size' must be a string like 1280x720")
		}
		width, height, size_ok := parse_size(name)
		if !size_ok {
			return {}, format_error("%s", "scenario 'size' must be WIDTHxHEIGHT")
		}
		scenario.size = {width, height}
		scenario.has_size = true
	}

	if view_value, has_view := json_get(object, "view"); has_view {
		view, view_error := scenario_view(view_value)
		if view_error != "" {
			return {}, view_error
		}
		append(&scenario.commands, Command{kind = .View, view = view})
	}

	if debug_value, has_debug := json_get(object, "renderer_debug"); has_debug {
		if debug_error := scenario_renderer_debug(&scenario, debug_value); debug_error != "" {
			return {}, debug_error
		}
	}

	if requires_value, has_requires := json_get(object, "requires"); has_requires {
		if requires_error := scenario_requires(&scenario, requires_value); requires_error != "" {
			return {}, requires_error
		}
	}

	if analysis_value, has_analysis := json_get(object, "analysis"); has_analysis {
		config, analysis_error := scenario_analysis(analysis_value)
		if analysis_error != "" {
			return {}, analysis_error
		}
		scenario.analysis = config
	}

	commands_value, has_commands := json_get(object, "commands")
	if !has_commands {
		return {}, format_error("%s", "scenario needs 'commands'")
	}
	if commands_error := scenario_commands(&scenario, commands_value, allocator); commands_error != "" {
		return {}, commands_error
	}

	if checks_value, has := json_get(object, "checks"); has {
		if checks_error := scenario_add_checks(&scenario, checks_value, allocator); checks_error != "" {
			return {}, checks_error
		}
	}

	ok = true
	return scenario, ""
}

scenario_destroy :: proc(scenario: ^Scenario, allocator: mem.Allocator) {
	for &command in scenario.commands {
		command_destroy(&command, allocator)
	}
	delete(scenario.commands)
	if scenario.source.path != "" {
		delete(scenario.source.path, allocator)
	}
	if scenario.source.hash != "" {
		delete(scenario.source.hash, allocator)
	}
	scenario_parameters_destroy(scenario.source.parameters, allocator)
	scenario^ = {}
}

// The effective parameter values join the hash, so two sweep runs of one file
// are distinct scenarios.
scenario_hash :: proc(
	data: string,
	parameters: []Scenario_Parameter,
	allocator: mem.Allocator,
) -> string {
	hash := digest.fnv()
	digest.write_bytes(&hash, transmute([]u8)data)
	for parameter in parameters {
		digest.write_bytes(&hash, transmute([]u8)parameter.name)
		digest.write_bytes(&hash, transmute([]u8)parameter.value)
	}
	return digest.hex(hash, allocator)
}

capture_name :: proc(frame: int, allocator: mem.Allocator) -> string {
	return fmt.aprintf("frame_%04d", frame, allocator = allocator)
}

@(private)
scenario_base_dir :: proc(path: string) -> string {
	if path == "-" {
		return ""
	}
	index := strings.last_index_byte(path, '/')
	if index < 0 {
		return ""
	}
	return path[:index]
}
