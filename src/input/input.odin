#+vet explicit-allocators
#+vet !unused-procedures // the window loop calls this API; the game binary does not
package input

import "src:game"

// Focus is the whole frame's ownership: the game half from game.focus and the
// platform's captured fact.
Focus :: struct {
	game:     game.Focus,
	captured: bool,
}

View_Intents :: struct {
	debug_view:   bool,
	debug_mode:   bool,
	taa:          bool,
	repro:        bool,
	reset_player: bool,
	reset_scene:  bool,
	menu_toggle:  bool,
}

// Frame_Input is the resolved intent of one frame. It holds no pointer into
// session state, so it is safe to copy.
Frame_Input :: struct {
	snapshot:         game.Input_Snapshot,
	look_delta:       [2]f32,
	motion:           game.Debug_Motion,
	actions:          [game.MAX_EDIT_ACTIONS]game.Edit_Action,
	action_count:     int,
	view:             View_Intents,
	pause:            bool,
}

// Resolver holds the edge latches that must survive a frame with no fixed step.
Resolver :: struct {
	jump:   bool,
	sprint: bool,
}

clear_latches :: proc(r: ^Resolver) {
	r^ = {}
}
