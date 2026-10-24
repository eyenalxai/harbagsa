#+vet explicit-allocators
package harness

import "core:encoding/json"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:path/filepath"
import "core:strings"

// A scenario may extend another scenario and may name `parameters`. Resolution
// happens on the JSON tree before the typed parser sees it, so both features
// work for every command and every top-level key.
SCENARIO_EXTENDS_MAX :: 8

scenario_resolve :: proc(
	value: json.Value,
	base_dir: string,
	depth: int,
	allocator: mem.Allocator,
) -> (json.Value, string) {
	if depth > SCENARIO_EXTENDS_MAX {
		return {}, format_error("%s", "scenario 'extends' nests too deeply")
	}
	object, object_ok := json_object(value)
	if !object_ok {
		return json.clone_value(value, allocator), ""
	}

	merged := make(json.Object, allocator)
	if extends_value, has_extends := object["extends"]; has_extends {
		base_value, base_error := scenario_load_base(extends_value, base_dir, depth, allocator)
		if base_error != "" {
			json.destroy_value(json.Value(merged), allocator)
			return {}, base_error
		}
		base_object, base_ok := json_object(base_value)
		if !base_ok {
			json.destroy_value(base_value, allocator)
			json.destroy_value(json.Value(merged), allocator)
			return {}, format_error("%s", "the base scenario must be a JSON object")
		}
		for key, entry in base_object {
			merged[strings.clone(key, allocator)] = json.clone_value(entry, allocator)
		}
		json.destroy_value(base_value, allocator)
	}

	for key, entry in object {
		if key == "extends" {
			continue
		}
		if old, has := merged[key]; has {
			json.destroy_value(old, allocator)
		}
		merged[strings.clone(key, allocator)] = json.clone_value(entry, allocator)
	}

	if parameters_error := scenario_apply_parameters(merged, allocator); parameters_error != "" {
		json.destroy_value(json.Value(merged), allocator)
		return {}, parameters_error
	}
	return json.Value(merged), ""
}

@(private)
scenario_load_base :: proc(
	extends_value: json.Value,
	base_dir: string,
	depth: int,
	allocator: mem.Allocator,
) -> (json.Value, string) {
	name, name_ok := json_string(extends_value)
	if !name_ok || name == "" {
		return {}, format_error("%s", "scenario 'extends' must be a non-empty path")
	}
	path := name
	if !filepath.is_abs(path) && base_dir != "" {
		joined, join_error := filepath.join({base_dir, path}, allocator)
		if join_error != nil {
			return {}, format_error("cannot resolve the base scenario %q", path)
		}
		path = joined
	}
	defer if path != name {
		delete(path, allocator)
	}

	data, read_error := os.read_entire_file(path, allocator)
	if read_error != nil {
		return {}, fmt.aprintf("cannot read the base scenario %s: %v", path, read_error, allocator = allocator)
	}
	defer delete(data, allocator)

	value, parse_error := json.parse_string(string(data), .JSON, true, allocator)
	if parse_error != .None {
		return {}, fmt.aprintf("invalid JSON in %s: %v", path, parse_error, allocator = allocator)
	}
	defer json.destroy_value(value, allocator)

	resolved, resolve_error := scenario_resolve(value, scenario_base_dir(path), depth + 1, allocator)
	if resolve_error != "" {
		return {}, resolve_error
	}
	return resolved, ""
}

@(private)
scenario_apply_parameters :: proc(object: json.Object, allocator: mem.Allocator) -> string {
	parameters_value, has_parameters := object["parameters"]
	if !has_parameters {
		return ""
	}
	parameters, parameters_ok := json_object(parameters_value)
	if !parameters_ok {
		return format_error("%s", "scenario 'parameters' must be an object")
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
	for key, &entry in object {
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

@(private)
scenario_substitute :: proc(
	value: json.Value,
	parameters: json.Object,
	allocator: mem.Allocator,
) -> (json.Value, string) {
	#partial switch entry in value {
	case json.String:
		if name, is_placeholder := scenario_placeholder(entry); is_placeholder {
			parameter, has := parameters[name]
			if !has {
				return {}, fmt.aprintf("unknown parameter %q", name, allocator = allocator)
			}
			return scenario_parameter_copy(parameter, allocator)
		}
		text, changed := scenario_interpolate(entry, parameters, allocator)
		if !changed {
			return json.clone_value(value, allocator), ""
		}
		return json.Value(text), ""
	case json.Array:
		items := make([dynamic]json.Value, 0, len(entry), allocator)
		for item in entry {
			resolved, item_error := scenario_substitute(item, parameters, allocator)
			if item_error != "" {
				for resolved_item in items {
					json.destroy_value(resolved_item, allocator)
				}
				delete(items)
				return {}, item_error
			}
			append(&items, resolved)
		}
		return json.Value(json.Array(items)), ""
	case json.Object:
		object := make(json.Object, allocator)
		for key, item in entry {
			resolved, item_error := scenario_substitute(item, parameters, allocator)
			if item_error != "" {
				json.destroy_value(json.Value(object), allocator)
				return {}, item_error
			}
			object[strings.clone(key, allocator)] = resolved
		}
		return json.Value(object), ""
	}
	return json.clone_value(value, allocator), ""
}

@(private)
scenario_parameter_copy :: proc(value: json.Value, allocator: mem.Allocator) -> (json.Value, string) {
	#partial switch entry in value {
	case json.String:
		return json.Value(strings.clone(entry, allocator)), ""
	case json.Integer:
		return json.Value(entry), ""
	case json.Float:
		return json.Value(entry), ""
	case json.Boolean:
		return json.Value(entry), ""
	}
	return {}, format_error("%s", "a parameter value must be a string, number, or boolean")
}

@(private)
scenario_placeholder :: proc(text: string) -> (name: string, ok: bool) {
	if len(text) < 4 || text[0] != '$' || text[1] != '{' || text[len(text) - 1] != '}' {
		return "", false
	}
	name = text[2:len(text) - 1]
	if name == "" || strings.index_byte(name, '}') >= 0 || strings.index_byte(name, '$') >= 0 {
		return "", false
	}
	return name, true
}

// Returns the original string and false when it holds no placeholder, so the
// caller can clone instead of allocating a copy.
@(private)
scenario_interpolate :: proc(
	text: string,
	parameters: json.Object,
	allocator: mem.Allocator,
) -> (result: string, changed: bool) {
	keyword := "${"
	if strings.index(text, keyword) < 0 {
		return text, false
	}
	builder := strings.builder_make(allocator)
	cursor := 0
	for cursor < len(text) {
		start := strings.index(text[cursor:], keyword)
		if start < 0 {
			strings.write_string(&builder, text[cursor:])
			break
		}
		start += cursor
		end := strings.index_byte(text[start + len(keyword):], '}')
		if end < 0 {
			strings.write_string(&builder, text[cursor:])
			break
		}
		end += start + len(keyword)
		name := text[start + len(keyword):end]
		parameter, has := parameters[name]
		if !has {
			strings.write_string(&builder, text[cursor:end + 1])
			cursor = end + 1
			continue
		}
		strings.write_string(&builder, text[cursor:start])
		strings.write_string(&builder, scenario_parameter_text(parameter, context.temp_allocator))
		cursor = end + 1
	}
	return strings.to_string(builder), true
}

@(private)
scenario_parameter_text :: proc(value: json.Value, allocator: mem.Allocator) -> string {
	#partial switch entry in value {
	case json.String:
		return entry
	case json.Integer:
		return fmt.aprintf("%d", entry, allocator = allocator)
	case json.Float:
		return fmt.aprintf("%g", entry, allocator = allocator)
	case json.Boolean:
		return entry ? "true" : "false"
	}
	return ""
}
