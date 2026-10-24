#+vet explicit-allocators
package harness

import "core:fmt"

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
	}
	return {}, fmt.aprintf("unknown menu field %q", path, allocator = context.allocator)
}
