#+vet explicit-allocators
package harness

import "core:encoding/json"
import "core:fmt"
import "core:mem"
import "core:strings"

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
