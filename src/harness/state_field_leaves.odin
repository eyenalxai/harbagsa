#+vet explicit-allocators
package harness

import "core:fmt"
import "core:strconv"
import "core:strings"

@(private)
settings_field :: proc(settings: Settings_State, path: string) -> (Check_Value, string) {
	switch path {
	case "window_mode":
		return {kind = .String, text = settings.window_mode}, ""
	case "display":
		return {kind = .String, text = settings.display}, ""
	case "display_index":
		return {kind = .Number, number = f64(settings.display_index)}, ""
	case "resolution":
		return {kind = .String, text = settings.resolution}, ""
	case "window_resolution":
		return {kind = .String, text = settings.window_resolution}, ""
	case "sprint_mode":
		return {kind = .String, text = settings.sprint_mode}, ""
	case "crouch_mode":
		return {kind = .String, text = settings.crouch_mode}, ""
	case "prone_mode":
		return {kind = .String, text = settings.prone_mode}, ""
	case "type_weight":
		return {kind = .Number, number = f64(settings.type_weight)}, ""
	}
	return {}, fmt.aprintf("unknown settings field %q", path, allocator = context.allocator)
}

@(private)
debug_field :: proc(debug: Debug_State, path: string) -> (Check_Value, string) {
	switch path {
	case "active":
		return {kind = .Bool, boolean = debug.active}, ""
	}
	return {}, fmt.aprintf("unknown debug field %q", path, allocator = context.allocator)
}

@(private)
sun_field :: proc(sun: Sun_State, path: string) -> (Check_Value, string) {
	switch path {
	case "azimuth":
		return {kind = .Number, number = f64(sun.azimuth)}, ""
	case "elevation":
		return {kind = .Number, number = f64(sun.elevation)}, ""
	case "angular_diameter":
		return {kind = .Number, number = f64(sun.angular_diameter)}, ""
	}
	return {}, fmt.aprintf("unknown sun field %q", path, allocator = context.allocator)
}

@(private)
menu_field :: proc(menu: Menu_State, path: string) -> (Check_Value, string) {
	switch path {
	case "open":
		return {kind = .Bool, boolean = menu.open}, ""
	case "selected":
		return {kind = .Number, number = f64(menu.selected)}, ""
	case "item":
		return {kind = .String, text = menu.item}, ""
	case "status":
		return {kind = .String, text = menu.status}, ""
	case "blocked":
		return {kind = .Bool, boolean = menu.blocked}, ""
	}
	return {}, fmt.aprintf("unknown menu field %q", path, allocator = context.allocator)
}

@(private)
player_field :: proc(player: Player_State, path: string) -> (Check_Value, string) {
	head, tail, has_tail := split_field(path)
	switch head {
	case "position":
		if !has_tail {
			return {}, format_error("%s", "position needs an axis")
		}
		return vec_field(player.position, tail)
	case "eye":
		if !has_tail {
			return {}, format_error("%s", "eye needs an axis")
		}
		return vec_field(player.eye, tail)
	case "velocity":
		if !has_tail {
			return {}, format_error("%s", "velocity needs an axis")
		}
		return vec_field(player.velocity, tail)
	case "yaw":
		return {kind = .Number, number = f64(player.yaw)}, ""
	case "pitch":
		return {kind = .Number, number = f64(player.pitch)}, ""
	case "grounded":
		return {kind = .Bool, boolean = player.grounded}, ""
	}
	return {}, fmt.aprintf("unknown player field %q", path, allocator = context.allocator)
}

@(private)
crates_field :: proc(crates: []Crate_State, path: string) -> (Check_Value, string) {
	head, tail, has_tail := split_field(path)
	if head == "count" {
		return {kind = .Number, number = f64(len(crates))}, ""
	}
	index, parse_ok := strconv.parse_int(head)
	if !parse_ok || index < 0 || index >= len(crates) {
		return {}, fmt.aprintf("crate index %q is out of range", head, allocator = context.allocator)
	}
	if !has_tail {
		return {}, format_error("%s", "crate needs 'position' or 'rotation'")
	}
	crate := crates[index]
	property, axis, has_axis := split_field(tail)
	switch property {
	case "position":
		if !has_axis {
			return {}, format_error("%s", "crate position needs an axis")
		}
		return vec_field(crate.position, axis)
	case "rotation":
		if !has_axis {
			return {}, format_error("%s", "crate rotation needs an axis")
		}
		return quat_field(crate.rotation, axis)
	}
	return {}, fmt.aprintf("unknown crate field %q", tail, allocator = context.allocator)
}

@(private)
vec_field :: proc(value: Vec_State, axis: string) -> (Check_Value, string) {
	switch axis {
	case "x":
		return {kind = .Number, number = f64(value.x)}, ""
	case "y":
		return {kind = .Number, number = f64(value.y)}, ""
	case "z":
		return {kind = .Number, number = f64(value.z)}, ""
	}
	return {}, fmt.aprintf("unknown axis %q", axis, allocator = context.allocator)
}

@(private)
quat_field :: proc(value: Quat_State, axis: string) -> (Check_Value, string) {
	switch axis {
	case "x":
		return {kind = .Number, number = f64(value.x)}, ""
	case "y":
		return {kind = .Number, number = f64(value.y)}, ""
	case "z":
		return {kind = .Number, number = f64(value.z)}, ""
	case "w":
		return {kind = .Number, number = f64(value.w)}, ""
	}
	return {}, fmt.aprintf("unknown rotation axis %q", axis, allocator = context.allocator)
}

@(private)
split_field :: proc(path: string) -> (head, tail: string, has_tail: bool) {
	index := strings.index_byte(path, '.')
	if index < 0 {
		return path, "", false
	}
	return path[:index], path[index + 1:], true
}
