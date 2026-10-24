#+vet explicit-allocators
#+vet !unused-procedures // the agent harness and tests call this API; the game binary does not
package game

import b3 "libs:box3d"

Body_Mode :: enum {
	Static,
	Dynamic,
}

Prefab_Id :: enum {
	Crate,
	Small_Crate,
	Wide_Crate,
	Block,
	Platform,
	Ramp,
	Pillar,
	Wall,
}

INITIAL_CRATE_COUNT :: 3
MAX_PLACED_OBJECTS :: 128
OBJECT_DENSITY :: 20.0
RAMP_BASE_PITCH :: 20.0 * b3.DEG_TO_RAD

INITIAL_CRATE_POSITIONS :: [INITIAL_CRATE_COUNT][3]f32 {
	{0, 0.5, 8},
	{-3, 0.5, 6},
	{3, 0.5, 6},
}

CRATE_GREEN_COLOR :: [4]f32{0.30, 0.68, 0.38, 1.0}
CRATE_AMBER_COLOR :: [4]f32{0.86, 0.56, 0.20, 1.0}
CRATE_BLUE_COLOR :: [4]f32{0.26, 0.48, 0.84, 1.0}

INITIAL_CRATE_COLORS :: [INITIAL_CRATE_COUNT][4]f32 {
	CRATE_GREEN_COLOR,
	CRATE_AMBER_COLOR,
	CRATE_BLUE_COLOR,
}

Prefab :: struct {
	name:         string,
	half_extents: [3]f32,
	color:        [4]f32,
	body_mode:    Body_Mode,
	base_pitch:   f32,
	density:      f32,
}

PREFABS := [Prefab_Id]Prefab {
	.Crate = {
		name = "Crate",
		half_extents = {0.5, 0.5, 0.5},
		color = CRATE_GREEN_COLOR,
		body_mode = .Dynamic,
		density = OBJECT_DENSITY,
	},
	.Small_Crate = {
		name = "Small crate",
		half_extents = {0.25, 0.25, 0.25},
		color = CRATE_AMBER_COLOR,
		body_mode = .Dynamic,
		density = OBJECT_DENSITY,
	},
	.Wide_Crate = {
		name = "Wide crate",
		half_extents = {1.0, 0.5, 0.5},
		color = CRATE_BLUE_COLOR,
		body_mode = .Dynamic,
		density = OBJECT_DENSITY,
	},
	.Block = {
		name = "Block",
		half_extents = {1.0, 0.5, 1.0},
		color = FLOOR_COLOR,
		body_mode = .Static,
		density = OBJECT_DENSITY,
	},
	.Platform = {
		name = "Platform",
		half_extents = {2.0, 0.25, 2.0},
		color = WALKABLE_COLOR,
		body_mode = .Static,
		density = OBJECT_DENSITY,
	},
	.Ramp = {
		name = "Ramp",
		half_extents = {1.0, 0.25, 1.5},
		color = WALKABLE_COLOR,
		body_mode = .Static,
		base_pitch = RAMP_BASE_PITCH,
		density = OBJECT_DENSITY,
	},
	.Pillar = {
		name = "Pillar",
		half_extents = {0.25, 1.5, 0.25},
		color = FLOOR_COLOR,
		body_mode = .Static,
		density = OBJECT_DENSITY,
	},
	.Wall = {
		name = "Wall",
		half_extents = {2.0, 1.5, 0.25},
		color = WALL_COLOR,
		body_mode = .Static,
		density = OBJECT_DENSITY,
	},
}

prefab :: proc(id: Prefab_Id) -> Prefab {
	return PREFABS[id]
}

prefab_name :: proc(id: Prefab_Id) -> string {
	return PREFABS[id].name
}

body_mode_name :: proc(mode: Body_Mode) -> string {
	return mode == .Static ? "static" : "dynamic"
}
