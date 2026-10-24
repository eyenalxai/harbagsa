#+vet explicit-allocators
package harness

import "core:encoding/json"
import "core:fmt"
import "core:mem"

@(private)
scenario_view :: proc(value: json.Value) -> (View_Command, string) {
	object, object_ok := json_object(value)
	if !object_ok {
		return {}, format_error("%s", "scenario 'view' must be an object")
	}
	if key, unknown := json_unknown_key(object, {"hud", "debug", "hint", "perf"}); unknown {
		return {}, fmt.aprintf("unknown view key %q", key, allocator = context.allocator)
	}
	return parse_view_fields(object)
}

@(private)
scenario_renderer_debug :: proc(scenario: ^Scenario, value: json.Value) -> string {
	object, object_ok := json_object(value)
	if !object_ok {
		return format_error("%s", "scenario 'renderer_debug' must be an object")
	}
	if key, unknown := json_unknown_key(object, RENDERER_DEBUG_BLOCK_KEYS); unknown {
		return fmt.aprintf("unknown renderer_debug key %q", key, allocator = context.allocator)
	}
	fields, fields_error := renderer_debug_fields(object)
	if fields_error != "" {
		return fields_error
	}
	append(&scenario.commands, Command{kind = .Renderer_Debug, renderer_debug = fields})
	return ""
}

@(private)
scenario_analysis :: proc(value: json.Value) -> (Analysis_Config, string) {
	config := analysis_config_default()
	if enabled, ok := json_boolean(value); ok {
		config.enabled = enabled
		return config, ""
	}
	object, object_ok := json_object(value)
	if !object_ok {
		return {}, format_error("%s", "scenario 'analysis' must be a boolean or an object")
	}
	if key, unknown := json_unknown_key(object, {"enabled", "start", "count", "maps"}); unknown {
		return {}, fmt.aprintf("unknown analysis key %q", key, allocator = context.allocator)
	}
	if enabled_value, has := json_get(object, "enabled"); has {
		flag, ok := json_boolean(enabled_value)
		if !ok {
			return {}, format_error("%s", "'analysis.enabled' must be a boolean")
		}
		config.enabled = flag
	}
	if maps_value, has := json_get(object, "maps"); has {
		flag, ok := json_boolean(maps_value)
		if !ok {
			return {}, format_error("%s", "'analysis.maps' must be a boolean")
		}
		config.maps = flag
	}
	start_value, has_start := json_get(object, "start")
	count_value, has_count := json_get(object, "count")
	if has_start != has_count {
		return {}, format_error("%s", "'analysis' needs both 'start' and 'count'")
	}
	if has_start {
		start, start_ok := json_integer(start_value)
		count, count_ok := json_integer(count_value)
		if !start_ok || start < 0 {
			return {}, format_error("%s", "'analysis.start' must be a non-negative integer")
		}
		if !count_ok || count < 1 {
			return {}, format_error("%s", "'analysis.count' must be a positive integer")
		}
		config.start = int(start)
		config.count = int(count)
		config.has_window = true
	}
	return config, ""
}

@(private)
scenario_commands :: proc(scenario: ^Scenario, value: json.Value, allocator: mem.Allocator) -> string {
	array, array_ok := json_array(value)
	if !array_ok || len(array) == 0 {
		return format_error("%s", "scenario 'commands' must be a non-empty array")
	}
	for item, index in array {
		command, command_error := command_parse(item, allocator)
		if command_error != "" {
			error := fmt.aprintf("command %d: %s", index, command_error, allocator = context.allocator)
			delete(command_error, context.allocator)
			return error
		}
		append(&scenario.commands, command)
	}
	return ""
}

@(private)
scenario_add_checks :: proc(scenario: ^Scenario, value: json.Value, allocator: mem.Allocator) -> string {
	array, array_ok := json_array(value)
	if !array_ok {
		return format_error("%s", "scenario 'checks' must be an array")
	}
	for item, index in array {
		object, object_ok := json_object(item)
		if !object_ok {
			return fmt.aprintf("check %d: check must be an object", index, allocator = context.allocator)
		}
		command, check_error := parse_check(object, allocator)
		if check_error != "" {
			error := fmt.aprintf("check %d: %s", index, check_error, allocator = context.allocator)
			delete(check_error, context.allocator)
			return error
		}
		append(&scenario.commands, command)
	}
	return ""
}
