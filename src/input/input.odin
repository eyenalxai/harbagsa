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

// Held_Key is the press a source owns, so its repeat and release follow the
// sink that saw the press even after the owner changes.
Held_Key :: struct {
	key:  platform.Key,
	sink: Sink,
}

// Routed_Frame is the one output of the routing pass: the game intent, the UI
// batch, the owner, and any dropped event.
Routed_Frame :: struct {
	owner:          Owner,
	game:           Frame_Input,
	ui_events:      [platform.MAX_INPUT_EVENTS]platform.Input_Event,
	ui_event_count: int,
	// The raw events and one sink per event, in arrival order, so a frame can
	// report who acted on each one.
	events:      [platform.MAX_INPUT_EVENTS]platform.Input_Event,
	event_sinks: [platform.MAX_INPUT_EVENTS]Sink,
	event_count: int,
	gamepad:     platform.Gamepad_State,
	overflow:    bool,
}

// Resolver holds the edge latches that must survive a frame with no fixed step,
// and the held press of every input source. The keyboard is keyed by key; each
// gamepad button and stick axis is one source of its own.
Resolver :: struct {
	jump:        bool,
	sprint:      bool,
	keyboard:    [len(platform.Key)]Sink,
	buttons:     [platform.Gamepad_Button]Held_Key,
	stick_x:     Held_Key,
	stick_y:     Held_Key,
	stick_x_dir: i8,
	stick_y_dir: i8,
	pad_primary: bool,
	counts:      [len(Sink)][len(platform.Key)]u16,
}

clear_latches :: proc(r: ^Resolver) {
	r.jump = false
	r.sprint = false
}

clear_held :: proc(r: ^Resolver) {
	r.keyboard = {}
	r.buttons = {}
	r.stick_x = {}
	r.stick_y = {}
	r.stick_x_dir = 0
	r.stick_y_dir = 0
	r.pad_primary = false
	r.counts = {}
}

@(private)
press_key :: proc(r: ^Resolver, sink: Sink, key: platform.Key) -> bool {
	if sink == .None {
		return false
	}
	count := &r.counts[int(sink)][int(key)]
	if count^ > 0 {
		count^ += 1
		return false
	}
	count^ = 1
	return true
}

@(private)
release_key :: proc(r: ^Resolver, sink: Sink, key: platform.Key) -> bool {
	if sink == .None {
		return false
	}
	count := &r.counts[int(sink)][int(key)]
	if count^ == 0 {
		return false
	}
	count^ -= 1
	return count^ == 0
}
