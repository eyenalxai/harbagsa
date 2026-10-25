#+vet explicit-allocators
package renderer

import "src:geometry"

View_Flag :: enum {
	HUD,
	Menu,
	Palette,
	Debug_Draw,
	Capture_Hint,
	Perf,
}

View_Flags :: bit_set[View_Flag]

// One value carries every effective render input. The frame builder fills the
// scene half; the recorder fills the extent, TAA phase, atlas weight, and the
// debug flags in one place. The uniform and the digest both read this value.
Render_Input :: struct {
	width:                u32,
	height:               u32,
	camera:               Camera,
	light_direction:      [3]f32,
	sun_angular_diameter: f32,
	boxes:                []geometry.Box,
	lights:               []Light,
	debug_lines:          []geometry.Line,
	hud:                  HUD_Frame,
	view_flags:           View_Flags,
	jitter:               [2]f32,
	shadow_phase:         u32,
	atlas_weight:         f32,
	sky:                  bool,
	ao:                   bool,
	ao_radius:            f32,
	ao_strength:          f32,
	clip_height:          f32,
}
