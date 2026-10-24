#+vet explicit-allocators
package harness

import "core:math"

import "src:game"

Debug_State :: struct {
	active:      bool             `json:"active"`,
	selection:   string           `json:"selection"`,
	selected_id: u32              `json:"selected_id"`,
	palette:     Palette_State    `json:"palette"`,
	placement:   Placement_State  `json:"placement"`,
	sun:         Sun_State        `json:"sun"`,
	inspector:   Inspector_State  `json:"inspector"`,
	history:     History_State    `json:"history"`,
	lights:      Light_Budget_State `json:"lights"`,
}

Palette_State :: struct {
	open:     bool   `json:"open"`,
	selected: int    `json:"selected"`,
	body:     string `json:"body"`,
}

Placement_State :: struct {
	armed:    bool      `json:"armed"`,
	prefab:   string    `json:"prefab"`,
	position: Vec_State `json:"position"`,
	height:   f32         `json:"height"`,
	yaw:      f32         `json:"yaw"`,
	snap:     bool        `json:"snap"`,
	light:    Light_State `json:"light"`,
}

Sun_State :: struct {
	active:    bool      `json:"active"`,
	position:  Vec_State `json:"position"`,
	azimuth:          f32 `json:"azimuth"`,
	elevation:        f32 `json:"elevation"`,
	angular_diameter: f32 `json:"angular_diameter"`,
}

// The selected-object half of the debug inspector. Every number is in metres
// or degrees, and snap is the placement grid flag the inspector shows.
Inspector_State :: struct {
	prefab:   string    `json:"prefab"`,
	body:     string    `json:"body"`,
	size:     Vec_State `json:"size"`,
	position: Vec_State   `json:"position"`,
	yaw:      f32         `json:"yaw"`,
	snap:     bool        `json:"snap"`,
	light:    Light_State `json:"light"`,
}

History_State :: struct {
	depth: int `json:"depth"`,
	redo:  int `json:"redo"`,
}

debug_state_build :: proc(debug: ^game.Debug_Mode, sim: ^game.Simulation) -> Debug_State {
	azimuth, elevation := game.debug_mode_sun_angles(debug)
	state := Debug_State {
		active = debug.active,
		selection = game.debug_selection_name(debug.selection),
		selected_id = selected_object_id(debug, sim),
		palette = {
			open = debug.palette.open,
			selected = debug.palette.selected,
			body = game.body_mode_name(debug.palette.body_mode),
		},
		placement = {
			armed = debug.placement.armed,
			prefab = game.prefab_name(debug.placement.prefab),
			position = debug_placement_position(debug),
			height = debug.placement.height,
			yaw = debug.placement.yaw_degrees,
			snap = debug.placement.snap,
			light = placement_light_state(debug),
		},
		sun = {
			active = debug.sun.active,
			position = vec_state(debug.sun.position),
			azimuth = azimuth * 180.0 / math.PI,
			elevation = elevation * 180.0 / math.PI,
			angular_diameter = debug.sun_angular_diameter * 180.0 / math.PI,
		},
		history = {
			depth = game.debug_history_depth(debug),
			redo = game.debug_history_redo_depth(debug),
		},
		lights = light_budget_state(sim),
	}
	state.inspector = inspector_state(debug, sim)
	return state
}

// The next placement light belongs to the prefab the placement tool will use:
// the armed prefab, or the palette selection while the tool is idle.
@(private)
placement_light_state :: proc(debug: ^game.Debug_Mode) -> Light_State {
	prefab := debug.placement.prefab
	if !debug.placement.armed {
		prefab = game.palette_selected(debug.palette)
	}
	if !game.prefab_has_light(prefab) {
		return {}
	}
	settings := debug.palette.light
	if !settings.active {
		settings = game.prefab_light(prefab)
	}
	return light_state(settings)
}

@(private)
inspector_state :: proc(debug: ^game.Debug_Mode, sim: ^game.Simulation) -> Inspector_State {
	state := Inspector_State {
		snap = debug.placement.snap,
	}
	id, ok := game.debug_selected_object_id(debug, sim)
	if !ok {
		return state
	}
	object, found := game.simulation_object_find(sim, id)
	if !found {
		return state
	}
	box := game.simulation_object_box(sim, id)
	state.prefab = game.prefab_name(object.prefab)
	state.body = game.body_mode_name(object.body_mode)
	state.size = vec_state(box.half_extents * 2.0)
	state.position = vec_state(box.center)
	state.yaw = game.simulation_object_yaw(sim, id) * 180.0 / math.PI
	state.light = light_state(object.light)
	return state
}

@(private)
selected_object_id :: proc(debug: ^game.Debug_Mode, sim: ^game.Simulation) -> u32 {
	id, ok := game.debug_selected_object_id(debug, sim)
	if !ok {
		return 0
	}
	return u32(id)
}

@(private)
debug_placement_position :: proc(debug: ^game.Debug_Mode) -> Vec_State {
	ghost, ok := game.debug_ghost_geometry(debug)
	if !ok {
		return {}
	}
	return vec_state(ghost.center)
}
