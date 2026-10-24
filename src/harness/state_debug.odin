#+vet explicit-allocators
package harness

import "src:game"

Debug_State :: struct {
	active:      bool            `json:"active"`,
	selection:   string          `json:"selection"`,
	selected_id: u32             `json:"selected_id"`,
	palette:     Palette_State   `json:"palette"`,
	placement:   Placement_State `json:"placement"`,
	sun:         Sun_State       `json:"sun"`,
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
	height:   f32       `json:"height"`,
	yaw:      f32       `json:"yaw"`,
	snap:     bool      `json:"snap"`,
}

Sun_State :: struct {
	active:    bool      `json:"active"`,
	position:  Vec_State `json:"position"`,
	azimuth:   f32       `json:"azimuth"`,
	elevation: f32       `json:"elevation"`,
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
