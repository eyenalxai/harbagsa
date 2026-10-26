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

Render_Input :: struct {
	width:        u32,
	height:       u32,
	camera:       Camera,
	boxes:        []geometry.Box,
	lights:       []Light,
	debug_lines:  []geometry.Line,
	hud:          HUD_Frame,
	view_flags:   View_Flags,
	jitter:       [2]f32,
	atlas_weight: f32,
	clip_height:  f32,
}
