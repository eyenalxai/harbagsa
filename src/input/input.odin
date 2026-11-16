#+vet explicit-allocators
#+vet !unused-procedures // the window loop calls this API; the game binary does not
package input

import "src:game"
import "src:platform"

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
	snapshot:     game.Input_Snapshot,
	look_delta:   [2]f32,
	motion:       game.Debug_Motion,
	actions:      [game.MAX_EDIT_ACTIONS]game.Edit_Action,
	action_count: int,
	view:         View_Intents,
	overflow:     bool,
}

// Owner is the one surface that owns this frame. The route table turns it into
// a sink for each event; no event is derived from two owners.
Owner :: enum {
	World,
	Menu,
	Inspector,
	Palette,
	Placement,
}

Sink :: enum {
	None,
	Game,
	UI,
}

// Routed_Frame is the one output of the routing pass: the game intent, the UI
// batch, the owner, the pointer state, and any dropped event.
Routed_Frame :: struct {
	owner:          Owner,
	game:           Frame_Input,
	ui_events:      [platform.MAX_INPUT_EVENTS]platform.Input_Event,
	ui_event_count: int,
	pointer_free:   bool,
	overflow:       bool,
}

// Resolver holds the edge latches that must survive a frame with no fixed step,
// and the sink each held key was pressed into, so a release follows its press.
Resolver :: struct {
	jump:     bool,
	sprint:   bool,
	key_sink: [len(platform.Key)]Sink,
	stick_x:  i8,
	stick_y:  i8,
}

clear_latches :: proc(r: ^Resolver) {
	r.jump = false
	r.sprint = false
}
