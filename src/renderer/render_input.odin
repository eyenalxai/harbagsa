#+vet explicit-allocators
package renderer

import "src:bake"
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
	box_slots:    []bake.Box_Slot,
	lights:       []Light,
	debug_lines:  []geometry.Line,
	hud:          HUD_Frame,
	view_flags:   View_Flags,
	jitter:       [2]f32,
	atlas_weight: f32,
	clip_height:  f32,
	light_shadows: bool,
	lightmap:     bool,
	probe:        bool,
	bake_static:  bake.Static,
	bake_key:     u64,
	bake_status:  Bake_Status,
	// A pick frame draws the unjittered camera, forces the TLAS build, and
	// records one compute dispatch into the result buffer. It carries no
	// capture and replaces no render digest.
	pick_at: Maybe([2]i32),
}
