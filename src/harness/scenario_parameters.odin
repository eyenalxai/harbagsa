#+vet explicit-allocators
package harness

import "core:encoding/json"
import "core:fmt"
import "core:mem"
import "core:strconv"
import "core:strings"

@(private)
scenario_apply_parameters :: proc(
	object: ^json.Object,
	overrides: []Parameter_Override,
	check_usage: bool,
	allocator: mem.Allocator,
) -> string {
	parameters_value, has_parameters := object^["parameters"]
	parameters: json.Object
	if has_parameters {
		parsed, parameters_ok := json_object(parameters_value)
		if !parameters_ok {
			return format_error("%s", "scenario 'parameters' must be an object")
		}
		parameters = parsed
	} else if len(overrides) > 0 {
		parameters = make(json.Object, allocator)
		object^["parameters"] = json.Value(parameters)
	} else {
		return ""
	}
	for name, value in parameters {
		#partial switch entry in value {
		case json.String, json.Integer, json.Float, json.Boolean:
		case:
			return fmt.aprintf(
				"parameter %q must be a string, number, or boolean",
				name,
				allocator = allocator,
			)
		}
	}
	for override in overrides {
		if check_usage && !scenario_uses_parameter(object^, override.name) {
			return fmt.aprintf(
				"parameter %q has no placeholder in the scenario",
				override.name,
				allocator = allocator,
			)
		}
		declared, has_declared := parameters[override.name]
		value, value_error := scenario_parameter_parse(
			override.value,
			declared,
			has_declared,
			override.name,
			allocator,
		)
		if value_error != "" {
			return value_error
		}
		if old, has_old := parameters[override.name]; has_old {
			json.destroy_value(old, allocator)
		}
		parameters[override.name] = value
	}
	for key, &entry in object^ {
		if key == "parameters" || key == "extends" {
			continue
		}
		resolved, resolve_error := scenario_substitute(entry, parameters, allocator)
		if resolve_error != "" {
			return resolve_error
		}
		json.destroy_value(entry, allocator)
		entry = resolved
	}
	return ""
}

// The declared default sets the type: a string stays text, a boolean must parse
// as one, and a number accepts either form so 20 and 19.999 share a sweep.
@(private)
scenario_parameter_parse :: proc(
	text: string,
	declared: json.Value,
	has_declared: bool,
	name: string,
	allocator: mem.Allocator,
) -> (json.Value, string) {
	if has_declared {
		#partial switch entry in declared {
		case json.String:
			return json.Value(strings.clone(text, allocator)), ""
		case json.Boolean:
			flag, ok := strconv.parse_bool(text)
			if !ok {
				return {}, fmt.aprintf(
					"parameter %q needs true or false",
					name,
					allocator = allocator,
				)
			}
			return json.Value(flag), ""
		case json.Integer, json.Float:
			return scenario_number_parse(text, name, allocator)
		}
	}
	return scenario_scalar_parse(text, allocator)
}

@(private)
scenario_number_parse :: proc(
	text: string,
	name: string,
	allocator: mem.Allocator,
) -> (json.Value, string) {
	if integer, ok := strconv.parse_i64(text); ok {
		return json.Value(integer), ""
	}
	if number, ok := strconv.parse_f64(text); ok {
		return json.Value(number), ""
	}
	return {}, fmt.aprintf("parameter %q needs a number", name, allocator = allocator)
}

@(private)
scenario_scalar_parse :: proc(text: string, allocator: mem.Allocator) -> (json.Value, string) {
	if text == "true" {
		return json.Value(true), ""
	}
	if text == "false" {
		return json.Value(false), ""
	}
	if integer, ok := strconv.parse_i64(text); ok {
		return json.Value(integer), ""
	}
	if number, ok := strconv.parse_f64(text); ok {
		return json.Value(number), ""
	}
	return json.Value(strings.clone(text, allocator)), ""
}

@(private)
scenario_uses_parameter :: proc(object: json.Object, name: string) -> bool {
	for key, entry in object {
		if key == "parameters" || key == "extends" {
			continue
		}
		if scenario_value_uses_parameter(entry, name) {
			return true
		}
	}
	return false
}

@(private)
scenario_value_uses_parameter :: proc(value: json.Value, name: string) -> bool {
	#partial switch entry in value {
	case json.String:
		if placeholder, ok := scenario_placeholder(entry); ok {
			return placeholder == name
		}
		needle := fmt.aprintf("${%s}", name, allocator = context.temp_allocator)
		return strings.contains(entry, needle)
	case json.Array:
		for item in entry {
			if scenario_value_uses_parameter(item, name) {
				return true
			}
		}
	case json.Object:
		for _, item in entry {
			if scenario_value_uses_parameter(item, name) {
				return true
			}
		}
	}
	return false
}
