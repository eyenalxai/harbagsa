#+vet explicit-allocators
package harness

import "core:encoding/json"
import "core:fmt"
import "core:mem"

@(private)
scenario_view :: proc(value: json.Value) -> (View_Command, string) {
	object, object_ok := json_object(value)
	if !object_ok {
		return {}, "scenario 'view' must be an object"
	}
	if key, unknown := json_unknown_key(object, {"hud", "debug", "hint"}); unknown {
		return {}, fmt.aprintf("unknown view key %q", key, allocator = context.allocator)
	}
	return parse_view_fields(object)
}

@(private)
scenario_renderer_debug :: proc(scenario: ^Scenario, value: json.Value) -> string {
	object, object_ok := json_object(value)
	if !object_ok {
		return "scenario 'renderer_debug' must be an object"
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
scenario_commands :: proc(scenario: ^Scenario, value: json.Value, allocator: mem.Allocator) -> string {
	array, array_ok := json_array(value)
	if !array_ok || len(array) == 0 {
		return "scenario 'commands' must be a non-empty array"
	}
	for item, index in array {
		command, command_error := command_parse(item, allocator)
		if command_error != "" {
			return fmt.aprintf("command %d: %s", index, command_error, allocator = context.allocator)
		}
		append(&scenario.commands, command)
	}
	return ""
}

@(private)
scenario_add_checks :: proc(scenario: ^Scenario, value: json.Value, allocator: mem.Allocator) -> string {
	array, array_ok := json_array(value)
	if !array_ok {
		return "scenario 'checks' must be an array"
	}
	for item, index in array {
		object, object_ok := json_object(item)
		if !object_ok {
			return fmt.aprintf("check %d: check must be an object", index, allocator = context.allocator)
		}
		command, check_error := parse_check(object, allocator)
		if check_error != "" {
			return fmt.aprintf("check %d: %s", index, check_error, allocator = context.allocator)
		}
		append(&scenario.commands, command)
	}
	return ""
}
