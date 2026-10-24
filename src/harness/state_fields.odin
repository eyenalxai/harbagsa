#+vet explicit-allocators
package harness

import "core:fmt"
import "core:strconv"

State_Field_Getter :: proc(state: State, path: string) -> (Check_Value, string)

State_Field :: struct {
	name:  string,
	field: State_Field_Getter,
}

// One entry per top-level state object. A new field inside an object is one
// case in its resolver; a new object is one row here.
STATE_FIELDS := [?]State_Field {
	{"player", state_player_field},
	{"camera", state_camera_field},
	{"crates", state_crates_field},
	{"settings", state_settings_field},
	{"debug", state_debug_field},
	{"sun", state_sun_field},
	{"menu", state_menu_field},
	{"rows", state_rows_field},
	{"settle", state_settle_field},
	{"renderer", state_renderer_field},
}

state_field :: proc(state: State, path: string) -> (Check_Value, string) {
	switch path {
	case "frame":
		return {kind = .Number, number = f64(state.frame)}, ""
	case "digest":
		return {kind = .String, text = state.digest}, ""
	case "render_digest":
		return {kind = .String, text = state.render_digest}, ""
	}

	head, tail, has_tail := split_field(path)
	for entry in STATE_FIELDS {
		if entry.name != head {
			continue
		}
		if !has_tail {
			return {}, fmt.aprintf("%s needs a field", head, allocator = context.allocator)
		}
		return entry.field(state, tail)
	}
	return {}, fmt.aprintf("unknown state field %q", path, allocator = context.allocator)
}

@(private)
state_player_field :: proc(state: State, path: string) -> (Check_Value, string) {
	return player_field(state.player, path)
}

@(private)
state_crates_field :: proc(state: State, path: string) -> (Check_Value, string) {
	return crates_field(state.crates, path)
}

@(private)
state_settings_field :: proc(state: State, path: string) -> (Check_Value, string) {
	return settings_field(state.settings, path)
}

@(private)
state_debug_field :: proc(state: State, path: string) -> (Check_Value, string) {
	return debug_field(state.debug, path)
}

@(private)
state_sun_field :: proc(state: State, path: string) -> (Check_Value, string) {
	return sun_field(state.sun, path)
}

@(private)
state_menu_field :: proc(state: State, path: string) -> (Check_Value, string) {
	return menu_field(state.menu, path)
}

@(private)
state_renderer_field :: proc(state: State, path: string) -> (Check_Value, string) {
	return renderer_field(state.renderer, path)
}

@(private)
state_camera_field :: proc(state: State, path: string) -> (Check_Value, string) {
	camera := state.camera
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
	}
	return {}, fmt.aprintf("unknown settings field %q", path, allocator = context.allocator)
}

@(private)
debug_field :: proc(debug: Debug_State, path: string) -> (Check_Value, string) {
	head, tail, has_tail := split_field(path)
	switch head {
	case "active":
		return {kind = .Bool, boolean = debug.active}, ""
	case "selection":
		return {kind = .String, text = debug.selection}, ""
	case "selected_id":
		return {kind = .Number, number = f64(debug.selected_id)}, ""
	case "palette":
		if !has_tail {
			return {}, "debug.palette needs a field"
		}
		return palette_field(debug.palette, tail)
	case "placement":
		if !has_tail {
			return {}, "debug.placement needs a field"
		}
		return placement_field(debug.placement, tail)
	case "sun":
		if !has_tail {
			return {}, "debug.sun needs a field"
		}
		return sun_field(debug.sun, tail)
	}
	return {}, fmt.aprintf("unknown settle field %q", path, allocator = context.allocator)
}

@(private)
palette_field :: proc(palette: Palette_State, path: string) -> (Check_Value, string) {
	switch path {
	case "open":
		return {kind = .Bool, boolean = palette.open}, ""
	case "selected":
		return {kind = .Number, number = f64(palette.selected)}, ""
	case "body":
		return {kind = .String, text = palette.body}, ""
	}
	return {}, fmt.aprintf("unknown debug.palette field %q", path, allocator = context.allocator)
}

@(private)
placement_field :: proc(placement: Placement_State, path: string) -> (Check_Value, string) {
	head, tail, has_tail := split_field(path)
	switch head {
	case "armed":
		return {kind = .Bool, boolean = placement.armed}, ""
	case "prefab":
		return {kind = .String, text = placement.prefab}, ""
	case "height":
		return {kind = .Number, number = f64(placement.height)}, ""
	case "yaw":
		return {kind = .Number, number = f64(placement.yaw)}, ""
	case "snap":
		return {kind = .Bool, boolean = placement.snap}, ""
	case "position":
		if !has_tail {
			return {}, "debug.placement.position needs an axis"
		}
		return vec_field(placement.position, tail)
	}
	return {}, fmt.aprintf("unknown debug.placement field %q", path, allocator = context.allocator)
}

@(private)
sun_field :: proc(sun: Sun_State, path: string) -> (Check_Value, string) {
	head, tail, has_tail := split_field(path)
	switch head {
	case "active":
		return {kind = .Bool, boolean = sun.active}, ""
	case "azimuth":
		return {kind = .Number, number = f64(sun.azimuth)}, ""
	case "elevation":
		return {kind = .Number, number = f64(sun.elevation)}, ""
	case "position":
		if !has_tail {
			return {}, "debug.sun.position needs an axis"
		}
		return vec_field(sun.position, tail)
	}
	return {}, fmt.aprintf("unknown debug.sun field %q", path, allocator = context.allocator)
}

@(private)
menu_field :: proc(menu: Menu_State, path: string) -> (Check_Value, string) {
	switch path {
	case "kind":
		return {kind = .String, text = row.kind}, ""
	case "label":
		return {kind = .String, text = row.label}, ""
	case "value":
		return {kind = .String, text = row.value}, ""
	case "blocked":
		return {kind = .Bool, boolean = row.blocked}, ""
	case "ratio":
		return {kind = .Number, number = f64(row.ratio)}, ""
	case "ticks":
		return {kind = .Number, number = f64(row.ticks)}, ""
	}
	return {}, fmt.aprintf("unknown row field %q", path, allocator = context.allocator)
}
