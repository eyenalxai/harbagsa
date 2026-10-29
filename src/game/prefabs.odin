#+vet explicit-allocators
#+vet !unused-procedures // the agent harness calls this API; the game binary does not
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
	Lamp,
	Light_Panel,
	Beacon,
}

INITIAL_CRATE_COUNT :: 3
INITIAL_LAMP_COUNT :: 3
INITIAL_OBJECT_COUNT :: INITIAL_CRATE_COUNT + INITIAL_LAMP_COUNT
OBJECT_DENSITY :: 20.0
RAMP_BASE_PITCH :: 20.0 * b3.DEG_TO_RAD

LIGHT_LAMP_INTENSITY :: 1.5
LIGHT_PANEL_INTENSITY :: 1.2
LIGHT_BEACON_INTENSITY :: 2.0
LIGHT_LAMP_RANGE :: 8.0
LIGHT_PANEL_RANGE :: 10.0
LIGHT_BEACON_RANGE :: 5.0

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

Initial_Lamp :: struct {
	name:     string,
	prefab:   Prefab_Id,
	position: [3]f32,
}

INITIAL_LAMPS :: [INITIAL_LAMP_COUNT]Initial_Lamp {
	{"initial-lamp", .Lamp, {-6.0, 1.2, 6.0}},
	{"initial-panel", .Light_Panel, {6.0, 1.5, 6.0}},
	{"initial-beacon", .Beacon, {0.0, 1.0, 2.0}},
}

Prefab :: struct {
	name:         string,
	short_name:   string,
	half_extents: [3]f32,
	color:        [4]f32,
	body_mode:    Body_Mode,
	base_pitch:   f32,
	density:      f32,
	light:        Light_Settings,
}

PREFABS := [Prefab_Id]Prefab {
	.Crate = {
		name = "Crate",
		short_name = "Crate",
		half_extents = {0.5, 0.5, 0.5},
		color = CRATE_GREEN_COLOR,
		body_mode = .Dynamic,
		density = OBJECT_DENSITY,
	},
	.Small_Crate = {
		name = "Small crate",
		short_name = "Small",
		half_extents = {0.25, 0.25, 0.25},
		color = CRATE_AMBER_COLOR,
		body_mode = .Dynamic,
		density = OBJECT_DENSITY,
	},
	.Wide_Crate = {
		name = "Wide crate",
		short_name = "Wide",
		half_extents = {1.0, 0.5, 0.5},
		color = CRATE_BLUE_COLOR,
		body_mode = .Dynamic,
		density = OBJECT_DENSITY,
	},
	.Block = {
		name = "Block",
		short_name = "Block",
		half_extents = {1.0, 0.5, 1.0},
		color = FLOOR_COLOR,
		body_mode = .Static,
		density = OBJECT_DENSITY,
	},
	.Platform = {
		name = "Platform",
		short_name = "Platform",
		half_extents = {2.0, 0.25, 2.0},
		color = WALKABLE_COLOR,
		body_mode = .Static,
		density = OBJECT_DENSITY,
	},
	.Ramp = {
		name = "Ramp",
		short_name = "Ramp",
		half_extents = {1.0, 0.25, 1.5},
		color = WALKABLE_COLOR,
		body_mode = .Static,
		base_pitch = RAMP_BASE_PITCH,
		density = OBJECT_DENSITY,
	},
	.Pillar = {
		name = "Pillar",
		short_name = "Pillar",
		half_extents = {0.25, 1.5, 0.25},
		color = FLOOR_COLOR,
		body_mode = .Static,
		density = OBJECT_DENSITY,
	},
	.Wall = {
		name = "Wall",
		short_name = "Wall",
		half_extents = {2.0, 1.5, 0.25},
		color = WALL_COLOR,
		body_mode = .Static,
		density = OBJECT_DENSITY,
	},
	.Lamp = {
		name = "Lamp",
		short_name = "Lamp",
		half_extents = {0.25, 0.25, 0.25},
		body_mode = .Dynamic,
		density = OBJECT_DENSITY,
		light = {
			active = true,
			color = .Warm,
			intensity = LIGHT_LAMP_INTENSITY,
			range = LIGHT_LAMP_RANGE,
		},
	},
	.Light_Panel = {
		name = "Light panel",
		short_name = "Panel",
		half_extents = {1.0, 0.05, 0.25},
		body_mode = .Dynamic,
		density = OBJECT_DENSITY,
		light = {
			active = true,
			color = .Cool,
			intensity = LIGHT_PANEL_INTENSITY,
			range = LIGHT_PANEL_RANGE,
		},
	},
	.Beacon = {
		name = "Beacon",
		short_name = "Beacon",
		half_extents = {0.15, 0.15, 0.15},
		body_mode = .Dynamic,
		density = OBJECT_DENSITY,
		light = {
			active = true,
			color = .Red,
			intensity = LIGHT_BEACON_INTENSITY,
			range = LIGHT_BEACON_RANGE,
		},
	},
}

PREFAB_COUNT :: len(PREFABS)

prefab :: proc(id: Prefab_Id) -> Prefab {
	return PREFABS[id]
}

prefab_color :: proc(id: Prefab_Id) -> [4]f32 {
	info := prefab(id)
	if info.light.active {
		return light_color4(info.light.color)
	}
	return info.color
}

// The catalog stores the raw light values; the emissive strength follows the
// intensity so a tuned lamp glows as brightly as it lights.
prefab_light :: proc(id: Prefab_Id) -> Light_Settings {
	settings := prefab(id).light
	if settings.active {
		settings.emissive = light_emissive(settings.intensity)
	}
	return settings
}

prefab_has_light :: proc(id: Prefab_Id) -> bool {
	return prefab(id).light.active
}

// A light follows its body. A static body is a static fixture; a dynamic body
// is a dynamic lamp.
prefab_name :: proc(id: Prefab_Id) -> string {
	return PREFABS[id].name
}

prefab_parse :: proc(name: string) -> (Prefab_Id, bool) {
	for id in Prefab_Id {
		if PREFABS[id].name == name {
			return id, true
		}
	}
	return .Crate, false
}

body_mode_name :: proc(mode: Body_Mode) -> string {
	return mode == .Static ? "static" : "dynamic"
}

body_mode_parse :: proc(name: string) -> (Body_Mode, bool) {
	switch name {
	case "static":
		return .Static, true
	case "dynamic":
		return .Dynamic, true
	}
	return .Static, false
}
