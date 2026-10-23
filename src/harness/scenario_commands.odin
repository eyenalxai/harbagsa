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
	view: View_Command
	if flag_value, has := json_get(object, "hud"); has {
		flag, ok := json_boolean(flag_value)
		if !ok {
			return {}, "view 'hud' must be a boolean"
		}
		view.hud = flag
		view.has_hud = true
	}
	if flag_value, has := json_get(object, "debug"); has {
		flag, ok := json_boolean(flag_value)
		if !ok {
			return {}, "view 'debug' must be a boolean"
		}
		view.debug = flag
		view.has_debug = true
	}
	if flag_value, has := json_get(object, "hint"); has {
		flag, ok := json_boolean(flag_value)
		if !ok {
			return {}, "view 'hint' must be a boolean"
		}
		view.hint = flag
		view.has_hint = true
	}
	return view, ""
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
