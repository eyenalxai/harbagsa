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
	overrides: []Parameter_Override,
	used: []bool,
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
		base_value, base_error := scenario_load_base(extends_value, base_dir, depth, overrides, used, allocator)
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

	if parameters_error := scenario_apply_parameters(&merged, overrides, used, depth == 0, allocator); parameters_error != "" {
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
	overrides: []Parameter_Override,
	used: []bool,
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

	resolved, resolve_error := scenario_resolve(
		value,
		scenario_base_dir(path),
		depth + 1,
		overrides,
		used,
		allocator,
	)
	if resolve_error != "" {
		return {}, resolve_error
	}
	return resolved, ""
}
