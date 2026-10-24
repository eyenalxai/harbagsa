#+vet explicit-allocators
package harness

import "core:fmt"

@(private)
settings_field :: proc(settings: Settings_State, path: string) -> (Check_Value, string) {
	switch path {
	case "sprint_mode":
		return {kind = .String, text = settings.sprint_mode}, ""
	case "crouch_mode":
		return {kind = .String, text = settings.crouch_mode}, ""
	case "prone_mode":
		return {kind = .String, text = settings.prone_mode}, ""
	}
	return {}, fmt.aprintf("unknown settings field %q", path, allocator = context.allocator)
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
