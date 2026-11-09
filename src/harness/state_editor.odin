#+vet explicit-allocators
package harness

import "src:game"

Editor_State :: struct {
	active:    bool               `json:"active"`,
	tool:      string             `json:"tool"`,
	palette:   Palette_State      `json:"palette"`,
	placement: Placement_State    `json:"placement"`,
	selection: Selection_State    `json:"selection"`,
	history:   History_State      `json:"history"`,
	lights:    Light_Budget_State `json:"lights"`,
}

Palette_State :: struct {
	open:     bool   `json:"open"`,
	selected: int    `json:"selected"`,
	body:     string `json:"body"`,
}

Placement_State :: struct {
	armed:    bool        `json:"armed"`,
	prefab:   string      `json:"prefab"`,
	position: Vec_State   `json:"position"`,
	height:   f32         `json:"height"`,
	yaw_deg:  f32         `json:"yaw_deg"`,
	snap:     bool        `json:"snap"`,
	body:     string      `json:"body"`,
	light:    Light_State `json:"light"`,
}

Selection_State :: struct {
	present:  bool        `json:"present"`,
	id:       u32         `json:"id"`,
	prefab:   string      `json:"prefab"`,
	body:     string      `json:"body"`,
	size:     Vec_State   `json:"size"`,
	position: Vec_State   `json:"position"`,
	yaw_deg:  f32         `json:"yaw_deg"`,
	light:    Light_State `json:"light"`,
}

History_State :: struct {
	depth: int `json:"depth"`,
	redo:  int `json:"redo"`,
}

editor_state_build :: proc(view: game.Editor_View) -> Editor_State {
	state := Editor_State {
		active = view.active,
		tool = game.tool_kind_name(view.tool),
		palette = {
			open = view.palette.open,
			selected = int(view.palette.prefab),
			body = game.body_mode_name(view.palette.body_mode),
		},
		placement = {
			armed = view.placement.armed,
			prefab = game.prefab_name(view.placement.prefab),
			position = vec_state(view.placement.center),
			height = view.placement.height,
			yaw_deg = view.placement.yaw_degrees,
			snap = view.placement.snap,
			body = game.body_mode_name(view.placement.body_mode),
			light = light_state(view.placement.light),
		},
		history = {
			depth = view.history.depth,
			redo = view.history.redo,
		},
		lights = {
			active = view.lights.active,
			lamps = view.lights.lamps,
		},
	}
	if selection, has_selection := view.selection.?; has_selection {
		state.selection = {
			present = true,
			id = u32(selection.id),
			prefab = game.prefab_name(selection.prefab),
			body = game.body_mode_name(selection.body_mode),
			size = vec_state(selection.box.half_extents * 2.0),
			position = vec_state(selection.box.center),
			yaw_deg = selection.yaw_degrees,
			light = light_state(selection.light),
		}
	}
	return state
}
