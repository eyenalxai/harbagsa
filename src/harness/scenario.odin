#+vet explicit-allocators
package harness

import "core:encoding/json"
import "core:fmt"
import "core:mem"
import "core:os"

Scenario :: struct {
	commands: [dynamic]Command,
	analysis: Analysis_Config,
}

scenario_load :: proc(path: string, allocator: mem.Allocator) -> (Scenario, string) {
	data, read_error := os.read_entire_file(path, allocator)
	if read_error != nil {
		return {}, fmt.aprintf("cannot read %s: %v", path, read_error, allocator = allocator)
	}
	defer delete(data, allocator)
	return scenario_parse(string(data), allocator)
}

scenario_parse :: proc(data: string, allocator: mem.Allocator) -> (Scenario, string) {
	value, parse_error := json.parse_string(data, .JSON, true, allocator)
	if parse_error != .None {
		return {}, fmt.aprintf("invalid JSON: %v", parse_error, allocator = allocator)
	}
	defer json.destroy_value(value, allocator)

	object, object_ok := json_object(value)
	if !object_ok {
		return {}, format_error("%s", "scenario must be a JSON object")
	}
	if key, unknown := json_unknown_key(
		object,
		{"version", "view", "checks", "commands", "renderer_debug", "analysis"},
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
	scenario.commands = nil
}

capture_name :: proc(frame: int, allocator: mem.Allocator) -> string {
	return fmt.aprintf("frame_%04d", frame, allocator = allocator)
}
