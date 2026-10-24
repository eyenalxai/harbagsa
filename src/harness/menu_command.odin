#+vet explicit-allocators
package harness

import "core:encoding/json"

import "src:game"

Menu_Command :: struct {
	open:          bool,
	has_open:      bool,
	select:        int,
	has_select:    bool,
	activate:      bool,
	has_activate:  bool,
	direction:     int,
	has_direction: bool,
}

parse_menu :: proc(object: json.Object) -> (Command, string) {
	if key, unknown := json_unknown_key(object, {"cmd", "open", "select", "activate", "direction"}); unknown {
		return {}, format_error("unknown key %q", key)
	}

	command := Command{kind = .Menu}
	if value, has := json_get(object, "open"); has {
		open, ok := json_boolean(value)
		if !ok {
			return {}, "'open' must be a boolean"
		}
		command.menu.open = open
		command.menu.has_open = true
	}
	if value, has := json_get(object, "select"); has {
		selected, ok := json_integer(value)
		if !ok || selected < 0 || selected >= game.MENU_ITEM_COUNT {
			return {}, format_error(
				"'select' must be an integer in [0, %d]",
				game.MENU_ITEM_COUNT - 1,
			)
		}
		command.menu.select = selected
		command.menu.has_select = true
	}
	if value, has := json_get(object, "activate"); has {
		activate, ok := json_boolean(value)
		if !ok {
			return {}, "'activate' must be a boolean"
		}
		command.menu.activate = activate
		command.menu.has_activate = true
	}
	if value, has := json_get(object, "direction"); has {
		direction, ok := json_integer(value)
		if !ok || (direction != -1 && direction != 1) {
			return {}, "'direction' must be -1 or 1"
		}
		command.menu.direction = direction
		command.menu.has_direction = true
	}
	if command.menu.has_direction && !command.menu.activate {
		return {}, "'direction' needs 'activate'"
	}
	if !command.menu.has_open && !command.menu.has_select && !command.menu.has_activate {
		return {}, "menu needs 'open', 'select', or 'activate'"
	}
	return command, ""
}
