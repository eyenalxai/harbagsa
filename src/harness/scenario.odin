#+vet explicit-allocators
package harness

import "core:encoding/json"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:strings"

import "src:digest"

Scenario_Source :: struct {
	path: string `json:"path"`,
	hash: string `json:"hash"`,
}

Scenario :: struct {
	commands: [dynamic]Command,
	analysis: Analysis_Config,
	source:   Scenario_Source,
	has_size: bool,
	size:     [2]u32,
}

scenario_load :: proc(path: string, allocator: mem.Allocator) -> (Scenario, string) {
	data: []u8
	if path == "-" {
		stdin_data, stdin_error := read_stdin(allocator)
		if stdin_error != "" {
			return {}, stdin_error
		}
		data = stdin_data
	} else {
		file_data, read_error := os.read_entire_file(path, allocator)
		if read_error != nil {
			return {}, fmt.aprintf("cannot read %s: %v", path, read_error, allocator = allocator)
		}
		data = file_data
	}
	defer delete(data, allocator)
	scenario, parse_error := scenario_parse_with_base(string(data), scenario_base_dir(path), allocator)
	if parse_error != "" {
		return {}, parse_error
	}
	scenario.source.path = strings.clone(path, allocator)
	return scenario, ""
}

@(private)
read_stdin :: proc(allocator: mem.Allocator) -> ([]u8, string) {
	buffer := make([dynamic]u8, 0, 4096, allocator)
	chunk: [4096]u8
	for {
		count, read_error := os.read(os.stdin, chunk[:])
		if count > 0 {
			append(&buffer, ..chunk[:count])
		}
		if read_error != nil || count == 0 {
			break
		}
	}
	if len(buffer) == 0 {
		delete(buffer)
		return nil, format_error("%s", "scenario stdin is empty")
	}
	return buffer[:], ""
}

scenario_parse :: proc(data: string, allocator: mem.Allocator) -> (Scenario, string) {
	return scenario_parse_with_base(data, "", allocator)
}

@(private)
scenario_parse_with_base :: proc(
	data: string,
	base_dir: string,
	allocator: mem.Allocator,
) -> (Scenario, string) {
	value, parse_error := json.parse_string(data, .JSON, true, allocator)
	if parse_error != .None {
		return {}, fmt.aprintf("invalid JSON: %v", parse_error, allocator = allocator)
	}
	defer json.destroy_value(value, allocator)

	resolved, resolve_error := scenario_resolve(value, base_dir, 0, allocator)
	if resolve_error != "" {
		return {}, resolve_error
	}
	defer json.destroy_value(resolved, allocator)

	scenario, build_error := scenario_build(resolved, allocator)
	if build_error != "" {
		return {}, build_error
	}
	scenario.source.hash = scenario_hash(data, allocator)
	return scenario, ""
}

@(private)
scenario_build :: proc(value: json.Value, allocator: mem.Allocator) -> (Scenario, string) {
	object, object_ok := json_object(value)
	if !object_ok {
		return {}, format_error("%s", "scenario must be a JSON object")
	}
	if key, unknown := json_unknown_key(
		object,
		{"version", "view", "checks", "commands", "renderer_debug", "analysis", "size", "extends", "parameters"},
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
	scenario^ = {}
}

scenario_hash :: proc(data: string, allocator: mem.Allocator) -> string {
	hash := digest.fnv()
	digest.write_bytes(&hash, transmute([]u8)data)
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
