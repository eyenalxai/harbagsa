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
	case "position.x":
		return {kind = .Number, number = f64(camera.position.x)}, ""
	case "position.y":
		return {kind = .Number, number = f64(camera.position.y)}, ""
	case "position.z":
		return {kind = .Number, number = f64(camera.position.z)}, ""
	case "yaw":
		return {kind = .Number, number = f64(camera.yaw)}, ""
	case "pitch":
		return {kind = .Number, number = f64(camera.pitch)}, ""
	case "fov":
		return {kind = .Number, number = f64(camera.fov)}, ""
	case "overridden":
		return {kind = .Bool, boolean = camera.overridden}, ""
	}
	return {}, fmt.aprintf("unknown camera field %q", path, allocator = context.allocator)
}

@(private)
state_settle_field :: proc(state: State, path: string) -> (Check_Value, string) {
	switch path {
	case "frames":
		return {kind = .Number, number = f64(state.settle.frames)}, ""
	case "converged":
		return {kind = .Bool, boolean = state.settle.converged}, ""
	}
	return {}, fmt.aprintf("unknown settle field %q", path, allocator = context.allocator)
}

@(private)
state_rows_field :: proc(state: State, path: string) -> (Check_Value, string) {
	head, tail, has_tail := split_field(path)
	rows: []Row_State
	switch head {
	case "hud":
		rows = state.rows.hud
	case "menu":
		rows = state.rows.menu
	case:
		return {}, fmt.aprintf("unknown rows group %q", head, allocator = context.allocator)
	}
	if !has_tail {
		return {}, fmt.aprintf("rows %s needs an index", head, allocator = context.allocator)
	}
	index_text, field, has_field := split_field(tail)
	index, parse_ok := strconv.parse_int(index_text)
	if !parse_ok || index < 0 || index >= len(rows) {
		return {}, fmt.aprintf("row index %q is out of range", index_text, allocator = context.allocator)
	}
	if !has_field {
		return {}, fmt.aprintf("row %d needs a field", index, allocator = context.allocator)
	}
	return row_field(rows[index], field)
}

@(private)
row_field :: proc(row: Row_State, path: string) -> (Check_Value, string) {
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
