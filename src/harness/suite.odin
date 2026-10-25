#+vet explicit-allocators
package harness

import "core:encoding/json"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:path/filepath"
import "core:strings"

Suite_Entry :: struct {
	scenario:        string,
	label:           string,
	size:            string,
	has_size:        bool,
	no_render:       bool,
	parameters:      [MAX_SUITE_PARAMETERS]Parameter_Override,
	parameter_count: int,
}

Suite_File :: struct {
	path:        string,
	name:        string,
	description: string,
	entries:     []Suite_Entry,
}

suite_file_read :: proc(selector: string, allocator: mem.Allocator) -> (Suite_File, string) {
	path := suite_resolve_path(selector, allocator)
	data, read_error := os.read_entire_file(path, allocator)
	if read_error != nil {
		error := fmt.aprintf("cannot read %s: %v", path, read_error, allocator = allocator)
		delete(path, allocator)
		return {}, error
	}
	defer delete(data, allocator)
	file, parse_error := suite_parse(path, string(data), allocator)
	delete(path, allocator)
	if parse_error != "" {
		return {}, parse_error
	}
	return file, ""
}

suite_file_destroy :: proc(file: ^Suite_File, allocator: mem.Allocator) {
	for &entry in file.entries {
		delete(entry.scenario, allocator)
		if entry.label != "" {
			delete(entry.label, allocator)
		}
		if entry.size != "" {
			delete(entry.size, allocator)
		}
		for parameter in entry.parameters[:entry.parameter_count] {
			delete(parameter.name, allocator)
			delete(parameter.value, allocator)
		}
	}
	delete(file.entries, allocator)
	if file.path != "" {
		delete(file.path, allocator)
	}
	if file.name != "" {
		delete(file.name, allocator)
	}
	if file.description != "" {
		delete(file.description, allocator)
	}
	file^ = {}
}

suite_parse :: proc(path, data: string, allocator: mem.Allocator) -> (Suite_File, string) {
	value, parse_error := json.parse_string(data, .JSON, true, allocator)
	if parse_error != .None {
		return {}, fmt.aprintf("invalid JSON in %s: %v", path, parse_error, allocator = allocator)
	}
	defer json.destroy_value(value, allocator)
	object, object_ok := json_object(value)
	if !object_ok {
		return {}, format_error("%s", "a suite must be a JSON object")
	}
	if key, unknown := json_unknown_key(object, {"version", "name", "description", "entries"}); unknown {
		return {}, fmt.aprintf("unknown suite key %q", key, allocator = allocator)
	}

	file := Suite_File {
		path = strings.clone(path, allocator),
		name = strings.clone(filepath.stem(filepath.base(path)), allocator),
	}
	ok := false
	defer if !ok {
		suite_file_destroy(&file, allocator)
	}

	if version_value, has := json_get(object, "version"); has {
		version, version_ok := json_integer(version_value)
		if !version_ok || version != 1 {
			return {}, format_error("%s", "suite 'version' must be 1")
		}
	}
	if name_value, has := json_get(object, "name"); has {
		name, name_ok := json_string(name_value)
		if !name_ok || name == "" {
			return {}, format_error("%s", "suite 'name' must be a non-empty string")
		}
		delete(file.name, allocator)
		file.name = strings.clone(name, allocator)
	}
	if description_value, has := json_get(object, "description"); has {
		description, description_ok := json_string(description_value)
		if !description_ok {
			return {}, format_error("%s", "suite 'description' must be a string")
		}
		file.description = strings.clone(description, allocator)
	}

	entries_value, has_entries := json_get(object, "entries")
	array, array_ok := json_array(entries_value)
	if !has_entries || !array_ok || len(array) == 0 {
		return {}, format_error("%s", "suite 'entries' must be a non-empty array")
	}
	if len(array) > MAX_SUITE_ENTRIES {
		return {}, fmt.aprintf(
			"a suite holds at most %d entries",
			MAX_SUITE_ENTRIES,
			allocator = allocator,
		)
	}
	entries := make([]Suite_Entry, len(array), allocator)
	for item, index in array {
		entry, entry_error := suite_parse_entry(item, index, allocator)
		if entry_error != "" {
			for parsed in entries[:index] {
				suite_entry_destroy(parsed, allocator)
			}
			delete(entries, allocator)
			return {}, entry_error
		}
		entries[index] = entry
	}
	file.entries = entries
	for entry, index in file.entries {
		label := suite_entry_label(entry, context.temp_allocator)
		for previous in file.entries[:index] {
			if suite_entry_label(previous, context.temp_allocator) == label {
				return {}, fmt.aprintf(
					"suite entry %d repeats the label %q",
					index,
					label,
					allocator = allocator,
				)
			}
		}
	}
	ok = true
	return file, ""
}

@(private)
suite_parse_entry :: proc(value: json.Value, index: int, allocator: mem.Allocator) -> (Suite_Entry, string) {
	if scenario, ok := json_string(value); ok {
		if scenario == "" {
			return {}, fmt.aprintf("suite entry %d needs a scenario", index, allocator = allocator)
		}
		return {scenario = strings.clone(scenario, allocator)}, ""
	}
	object, object_ok := json_object(value)
	if !object_ok {
		return {}, fmt.aprintf(
			"suite entry %d must be a scenario name or an object",
			index,
			allocator = allocator,
		)
	}
	if key, unknown := json_unknown_key(
		object,
		{"scenario", "label", "size", "params", "no_render"},
	); unknown {
		return {}, fmt.aprintf(
			"unknown suite entry key %q in entry %d",
			key,
			index,
			allocator = allocator,
		)
	}
	scenario, scenario_ok := string_field(object, "scenario")
	if !scenario_ok || scenario == "" {
		return {}, fmt.aprintf(
			"suite entry %d needs a non-empty 'scenario'",
			index,
			allocator = allocator,
		)
	}
	entry := Suite_Entry{scenario = strings.clone(scenario, allocator)}
	if label_value, has := json_get(object, "label"); has {
		label, label_ok := json_string(label_value)
		if !label_ok || !valid_capture_name(label) {
			suite_entry_destroy(entry, allocator)
			return {}, fmt.aprintf(
				"suite entry %d 'label' must use only letters, digits, '-' and '_'",
				index,
				allocator = allocator,
			)
		}
		entry.label = strings.clone(label, allocator)
	}
	if size_value, has := json_get(object, "size"); has {
		size, size_ok := json_string(size_value)
		if !size_ok {
			suite_entry_destroy(entry, allocator)
			return {}, fmt.aprintf("suite entry %d 'size' must be a string", index, allocator = allocator)
		}
		if _, _, parsed := parse_size(size); !parsed {
			suite_entry_destroy(entry, allocator)
			return {}, fmt.aprintf("suite entry %d 'size' must be WIDTHxHEIGHT", index, allocator = allocator)
		}
		entry.size = strings.clone(size, allocator)
		entry.has_size = true
	}
	if no_render_value, has := json_get(object, "no_render"); has {
		flag, flag_ok := json_boolean(no_render_value)
		if !flag_ok {
			suite_entry_destroy(entry, allocator)
			return {}, fmt.aprintf("suite entry %d 'no_render' must be a boolean", index, allocator = allocator)
		}
		entry.no_render = flag
	}
	if params_value, has := json_get(object, "params"); has {
		params, params_ok := json_object(params_value)
		if !params_ok {
			suite_entry_destroy(entry, allocator)
			return {}, fmt.aprintf("suite entry %d 'params' must be an object", index, allocator = allocator)
		}
		if len(params) > MAX_SUITE_PARAMETERS {
			suite_entry_destroy(entry, allocator)
			return {}, fmt.aprintf(
				"suite entry %d holds at most %d parameters",
				index,
				MAX_SUITE_PARAMETERS,
				allocator = allocator,
			)
		}
		for name, parameter in params {
			#partial switch entry_value in parameter {
			case json.String, json.Integer, json.Float, json.Boolean:
			case:
				suite_entry_destroy(entry, allocator)
				return {}, fmt.aprintf(
					"suite entry %d parameter %q must be a string, number, or boolean",
					index,
					name,
					allocator = allocator,
				)
			}
			text := scenario_parameter_text(parameter, context.temp_allocator)
			entry.parameters[entry.parameter_count] = {
				name  = strings.clone(name, allocator),
				value = strings.clone(text, allocator),
			}
			entry.parameter_count += 1
		}
	}
	return entry, ""
}

suite_entry_destroy :: proc(entry: Suite_Entry, allocator: mem.Allocator) {
	delete(entry.scenario, allocator)
	if entry.label != "" {
		delete(entry.label, allocator)
	}
	if entry.size != "" {
		delete(entry.size, allocator)
	}
	parameters := entry.parameters
	for parameter in parameters[:entry.parameter_count] {
		delete(parameter.name, allocator)
		delete(parameter.value, allocator)
	}
}

suite_entry_label :: proc(entry: Suite_Entry, allocator: mem.Allocator) -> string {
	if entry.label != "" {
		return entry.label
	}
	return filepath.stem(filepath.base(entry.scenario))
}
