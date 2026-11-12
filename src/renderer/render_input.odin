#+vet explicit-allocators
package renderer

import "src:bake"
import "src:geometry"

Arena_Box_Identity :: struct {
	index: int,
}

Object_Identity :: struct {
	id: u32,
}

Spider_Box_Identity :: struct {
	index: int,
}

// A pick resolves the box back to its source through this identity, so a new
// box group cannot change which object the pick names.
Frame_Box_Identity :: union #no_nil {
	Arena_Box_Identity,
	Object_Identity,
	Spider_Box_Identity,
}

Frame_Box :: struct {
	box:      geometry.Box,
	slot:     bake.Box_Slot,
	identity: Frame_Box_Identity,
	is_lamp:  bool,
}

Render_Input :: struct {
	width:        u32,
	height:       u32,
	camera:       Camera,
	boxes:        []Frame_Box,
	lights:       []Light,
	debug_lines:  []geometry.Line,
	hud:          HUD_Frame,
	jitter:       [2]f32,
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
