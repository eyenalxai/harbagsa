#+vet explicit-allocators
package harness

import "core:encoding/json"
import "core:mem"
import "core:strings"

import "src:display"

@(private)
parse_displays :: proc(object: json.Object, allocator: mem.Allocator) -> (Command, string) {
	if key, unknown := json_unknown_key(object, {"cmd", "set", "clear"}); unknown {
		return {}, format_error("unknown key %q", key)
	}
	command := Command{kind = .Displays}
	if field_error := json_bool(object, "clear", &command.displays.clear); field_error != "" {
		return {}, field_error
	}
	set_value, has_set := json_get(object, "set")
	if command.displays.clear && has_set {
		return {}, format_error("%s", "displays cannot combine 'clear' and 'set'")
	}
	if !command.displays.clear && !has_set {
		return {}, format_error("%s", "displays needs 'set' or 'clear'")
	}
	if !has_set {
		return command, ""
	}
	array, array_ok := json_array(set_value)
	if !array_ok || len(array) == 0 || len(array) > display.MAX_DISPLAYS {
		return {}, format_error("'set' must be an array of 1 to %d displays", display.MAX_DISPLAYS)
	}
	entries := make([]Display_Def, len(array), allocator)
	ok := false
	defer if !ok {
		displays_def_destroy(entries, allocator)
	}
	for item, index in array {
		fields, fields_ok := json_object(item)
		if !fields_ok {
			return {}, format_error("display %d must be an object", index)
		}
		if key, unknown := json_unknown_key(fields, {"name", "desktop", "modes"}); unknown {
			return {}, format_error("unknown display key %q", key)
		}
		name, name_ok := string_field(fields, "name")
		if !name_ok || name == "" || len(name) > display.NAME_MAX {
			return {}, format_error(
				"display %d needs a 'name' of 1 to %d bytes",
				index,
				display.NAME_MAX,
			)
		}
		entries[index].name = strings.clone(name, allocator)
		if value, has := json_get(fields, "desktop"); has {
			mode, mode_ok := parse_display_mode(value)
			if !mode_ok {
				return {}, format_error("display %d 'desktop' must be WIDTHxHEIGHT", index)
			}
			entries[index].desktop = mode
			entries[index].has_desktop = true
		}
		if value, has := json_get(fields, "modes"); has {
			mode_array, mode_ok := json_array(value)
			if !mode_ok || len(mode_array) > display.MAX_MODES {
				return {}, format_error(
					"display %d 'modes' must be an array of at most %d sizes",
					index,
					display.MAX_MODES,
				)
			}
			modes := make([]Display_Mode_Def, len(mode_array), allocator)
			for entry, mode_index in mode_array {
				mode, parse_ok := parse_display_mode(entry)
				if !parse_ok {
					delete(modes, allocator)
					return {}, format_error(
						"display %d mode %d must be WIDTHxHEIGHT",
						index,
						mode_index,
					)
				}
				modes[mode_index] = mode
			}
			entries[index].modes = modes
		}
	}
	command.displays.set = entries
	ok = true
	return command, ""
}

@(private)
parse_display_mode :: proc(value: json.Value) -> (Display_Mode_Def, bool) {
	text, text_ok := json_string(value)
	if !text_ok {
		return {}, false
	}
	width, height, size_ok := parse_size(text)
	if !size_ok {
		return {}, false
	}
	return {width = i32(width), height = i32(height)}, true
}

displays_command_destroy :: proc(command: ^Displays_Command, allocator: mem.Allocator) {
	displays_def_destroy(command.set, allocator)
	command^ = {}
}

@(private)
displays_def_destroy :: proc(entries: []Display_Def, allocator: mem.Allocator) {
	for &entry in entries {
		if entry.name != "" {
			delete(entry.name, allocator)
		}
		if entry.modes != nil {
			delete(entry.modes, allocator)
		}
	}
	if entries != nil {
		delete(entries, allocator)
	}
}
