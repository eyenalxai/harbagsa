#+vet explicit-allocators
package harness

import "core:encoding/json"
import "core:mem"
import "core:fmt"
import "core:strings"

import "src:game"
import "src:ui"

Menu_Command :: struct {
	open:              bool,
	has_open:          bool,
	item:              game.Menu_Item,
	has_item:          bool,
	activate:          bool,
	has_activate:      bool,
	direction:         int,
	has_direction:     bool,
	opacity:           f64,
	has_opacity:       bool,
	reduce_motion:     bool,
	has_reduce_motion: bool,
	allow_blocked:     bool,
	has_allow_blocked: bool,
}

parse_menu :: proc(object: json.Object, _allocator: mem.Allocator) -> (Command, string) {
	if key, unknown := json_unknown_key(object, {"cmd", "open", "item", "activate", "direction", "opacity", "reduce_motion", "allow_blocked"}); unknown {
		return {}, format_error("unknown key %q", key)
	}

	command := Command{kind = .Menu}
	if field_error := json_optional_bool(object, "open", &command.menu.open, &command.menu.has_open); field_error != "" {
		return {}, field_error
	}
	if value, has := json_get(object, "item"); has {
		name, ok := json_string(value)
		if !ok {
			return {}, format_error("%s", "'item' must be a string")
		}
		item, found := game.menu_item_from_name(name)
		if !found {
			return {}, format_error("unknown menu item %q; use %s", name, menu_item_names())
		}
		command.menu.item = item
		command.menu.has_item = true
	}
	if field_error := json_optional_bool(object, "activate", &command.menu.activate, &command.menu.has_activate); field_error != "" {
		return {}, field_error
	}
	if value, has := json_get(object, "direction"); has {
		direction, ok := json_integer(value)
		if !ok || (direction != -1 && direction != 1) {
			return {}, format_error("%s", "'direction' must be -1 or 1")
		}
		command.menu.direction = direction
		command.menu.has_direction = true
	}
	if command.menu.has_direction && !command.menu.activate {
		return {}, format_error("%s", "'direction' needs 'activate'")
	}
	if value, has := json_get(object, "opacity"); has {
		opacity, ok := json_number(value)
		if !ok || opacity < f64(ui.HUD_OPACITY_MIN * 100) || opacity > f64(ui.HUD_OPACITY_MAX * 100) {
			return {}, format_error(
				"'opacity' must be a number in [%d, %d]",
				int(ui.HUD_OPACITY_MIN * 100),
				int(ui.HUD_OPACITY_MAX * 100),
			)
		}
		command.menu.opacity = opacity
		command.menu.has_opacity = true
	}
	if field_error := json_optional_bool(object, "reduce_motion", &command.menu.reduce_motion, &command.menu.has_reduce_motion); field_error != "" {
		return {}, field_error
	}
	if field_error := json_optional_bool(object, "allow_blocked", &command.menu.allow_blocked, &command.menu.has_allow_blocked); field_error != "" {
		return {}, field_error
	}
	if !command.menu.has_open &&
	   !command.menu.has_item &&
	   !command.menu.has_activate &&
	   !command.menu.has_opacity &&
	   !command.menu.has_reduce_motion {
		return {}, format_error("%s", "menu needs 'open', 'item', 'activate', 'opacity', or 'reduce_motion'")
	}
	return command, ""
}

@(private)
menu_item_names :: proc() -> string {
	builder := strings.builder_make(allocator = context.temp_allocator)
	for name, index in game.MENU_ITEM_NAMES {
		if index > 0 {
			fmt.sbprint(&builder, ", ")
		}
		fmt.sbprint(&builder, name)
	}
	return strings.to_string(builder)
}
