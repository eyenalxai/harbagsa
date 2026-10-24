#+vet explicit-allocators
package harness

import "core:encoding/json"
import "core:fmt"

import "src:game"

Crates_Action :: enum {
	Reset,
	Clear,
	Add,
	Remove,
}

Crates_Add :: struct {
	origin:  [3]f32,
	count:   int,
	columns: int,
	spacing: [3]f32,
}

Crates_Command :: struct {
	action:       Crates_Action,
	add:          Crates_Add,
	remove_index: int,
}

@(private)
parse_crates :: proc(object: json.Object) -> (Command, string) {
	if key, unknown := json_unknown_key(object, {"cmd", "reset", "clear", "add", "remove"}); unknown {
		return {}, format_error("unknown key %q", key)
	}
	command := Command{kind = .Crates}
	actions := 0
	if value, has := json_get(object, "reset"); has {
		flag, ok := json_boolean(value)
		if !ok || !flag {
			return {}, format_error("%s", "'reset' must be true")
		}
		command.crates.action = .Reset
		actions += 1
	}
	if value, has := json_get(object, "clear"); has {
		flag, ok := json_boolean(value)
		if !ok || !flag {
			return {}, format_error("%s", "'clear' must be true")
		}
		command.crates.action = .Clear
		actions += 1
	}
	if value, has := json_get(object, "add"); has {
		add, add_error := parse_crates_add(value)
		if add_error != "" {
			return {}, add_error
		}
		command.crates.action = .Add
		command.crates.add = add
		actions += 1
	}
	if value, has := json_get(object, "remove"); has {
		index, index_error := parse_crates_remove(value)
		if index_error != "" {
			return {}, index_error
		}
		command.crates.action = .Remove
		command.crates.remove_index = index
		actions += 1
	}
	if actions != 1 {
		return {}, format_error("%s", "crates needs exactly one of 'reset', 'clear', 'add', or 'remove'")
	}
	return command, ""
}

@(private)
parse_crates_add :: proc(value: json.Value) -> (Crates_Add, string) {
	object, object_ok := json_object(value)
	if !object_ok {
		return {}, format_error("%s", "'add' must be an object")
	}
	if key, unknown := json_unknown_key(
		object,
		{"position", "origin", "count", "columns", "spacing"},
	); unknown {
		return {}, format_error("unknown add key %q", key)
	}
	position, has_position := vec3_field(object, "position")
	origin, has_origin := vec3_field(object, "origin")
	if has_position == has_origin {
		return {}, format_error("%s", "'add' needs 'position' or 'origin', not both")
	}
	if has_position {
		if _, has_count := json_get(object, "count"); has_count {
			return {}, format_error("%s", "a single add takes only 'position'")
		}
		if _, has_columns := json_get(object, "columns"); has_columns {
			return {}, format_error("%s", "a single add takes only 'position'")
		}
		if _, has_spacing := json_get(object, "spacing"); has_spacing {
			return {}, format_error("%s", "a single add takes only 'position'")
		}
		return {origin = position, count = 1, columns = 1}, ""
	}
	count, count_ok := integer_field(object, "count")
	if !count_ok || count < 1 || count > game.MAX_CRATES {
		return {}, format_error("'count' must be an integer in [1, %d]", game.MAX_CRATES)
	}
	columns, columns_ok := integer_field(object, "columns")
	if !columns_ok || columns < 1 || columns > count {
		return {}, format_error("%s", "'columns' must be an integer in [1, count]")
	}
	spacing, spacing_ok := vec3_field(object, "spacing")
	if !spacing_ok {
		return {}, format_error("%s", "'spacing' must be [x, y, z]")
	}
	return {origin = origin, count = count, columns = columns, spacing = spacing}, ""
}

@(private)
parse_crates_remove :: proc(value: json.Value) -> (int, string) {
	object, object_ok := json_object(value)
	if !object_ok {
		return 0, format_error("%s", "'remove' must be an object")
	}
	if key, unknown := json_unknown_key(object, {"index"}); unknown {
		return 0, fmt.aprintf("unknown remove key %q", key, allocator = context.allocator)
	}
	index, index_ok := integer_field(object, "index")
	if !index_ok || index < 0 || index >= game.MAX_CRATES {
		return 0, fmt.aprintf(
			"'index' must be an integer in [0, %d]",
			game.MAX_CRATES - 1,
			allocator = context.allocator,
		)
	}
	return index, ""
}
