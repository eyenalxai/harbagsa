#+vet explicit-allocators
package harness

import "core:encoding/json"
import "core:mem"

Command_Parse :: proc(object: json.Object, allocator: mem.Allocator) -> (Command, string)
Command_Execute :: proc(session: ^Session, command: Command, reply: ^Reply) -> string
Command_Destroy :: proc(command: ^Command, allocator: mem.Allocator)

Command_Backend :: enum {
	None,
	Optional,
	Required,
}

Command_Record :: enum {
	Raw,
	Custom,
	Skip,
}

// One row per command. The parser, dispatcher, recorder, destroy path, backend
// policy, and schema all read this table; a new command is one row.
Command_Row :: struct {
	kind:        Command_Kind,
	name:        string,
	description: string,
	parse:       Command_Parse,
	execute:     Command_Execute,
	record:      Command_Record,
	destroy:     Command_Destroy,
	backend:     Command_Backend,
	value_type:  typeid,
}

COMMANDS := [?]Command_Row {
	{.Reset, "reset", "Return the simulation, settings, menu, and debug state to their defaults.", parse_no_fields, execute_reset, .Raw, nil, .None, No_Fields_Command},
	{.Look, "look", "Apply one pixel look delta through the game sensitivity.", parse_look, execute_look, .Raw, nil, .None, Look_Command},
	{.Face, "face", "Set the player view directly. Angles are degrees.", parse_face, execute_face, .Raw, nil, .None, Face_Command},
	{.Input, "input", "Set persistent movement input until the next input command.", parse_input, execute_input, .Raw, nil, .None, Input_Command},
	{.Step, "step", "Advance the simulation by fixed frames.", parse_step, execute_step, .Raw, nil, .None, Step_Command},
	{.Settle, "settle", "Render every frame of a settle without writing a screenshot.", parse_settle, execute_settle, .Raw, nil, .Optional, Settle_Command},
	{.State, "state", "Report the current state.", parse_no_fields, execute_state, .Raw, nil, .None, No_Fields_Command},
	{.Capture, "capture", "Render one frame and write one capture output.", parse_capture, execute_capture, .Custom, destroy_capture, .Optional, Capture_Command},
	{.Captures, "captures", "Render one frame and write several capture outputs.", parse_captures, execute_captures, .Custom, destroy_captures, .Optional, Captures_Command},
	{.Camera, "camera", "Move the debug camera or set a camera override.", parse_camera, execute_camera, .Raw, nil, .None, Camera_Command},
	{.View, "view", "Toggle the HUD, debug draw, capture hint, and perf overlay.", parse_view, execute_view, .Raw, nil, .None, View_Command},
	{.Debug_Mode, "debug_mode", "Enter or leave the debug mode and drive its palette.", parse_debug_mode, execute_debug_mode, .Raw, nil, .None, Debug_Mode_Command},
	{.Editor, "editor", "Drive the object palette, placement, edits, and history.", parse_editor, execute_editor, .Raw, nil, .None, Editor_Command},
	{.Menu, "menu", "Open, close, select, and change the settings menu.", parse_menu, execute_menu, .Raw, nil, .None, Menu_Command},
	{.Record, "record", "Start or stop recording a live session into a scenario.", parse_record, execute_record, .Skip, destroy_record, .None, Record_Command},
	{.Replay, "replay", "Replay a recorded scenario inside the live session.", parse_replay, execute_replay, .Skip, destroy_replay, .Optional, Replay_Command},
	{.Repro, "repro", "Write the live view as a scene scenario and show the notice.", parse_repro, execute_repro, .Skip, destroy_repro, .None, Repro_Command},
	{.Perf, "perf", "Measure frame time over a fixed or primed run.", parse_perf, execute_perf, .Skip, destroy_perf, .Required, Perf_Command},
	{.Renderer_Debug, "renderer_debug", "Apply gated renderer overrides. A field set to null restores its default.", parse_renderer_debug, execute_renderer_debug, .Raw, nil, .Optional, Renderer_Debug_Command},
	{.Displays, "displays", "Replace the display list.", parse_displays, execute_displays, .Raw, destroy_displays, .None, Displays_Command},
	{.Rows, "rows", "Dump the HUD and menu rows.", parse_no_fields, execute_rows, .Skip, nil, .None, No_Fields_Command},
	{.Scene, "scene", "Apply an exact scene: camera, objects, settings, view, and displays.", parse_scene, execute_scene, .Raw, destroy_scene, .None, Scene_Command},
	{.Place, "place", "Create one named object from a prefab without entering debug mode.", parse_place, execute_place, .Raw, nil, .None, Place_Command},
	{.Remove, "remove", "Delete one object by id or name without entering debug mode.", parse_remove, execute_remove, .Raw, nil, .None, Remove_Command},
	{.Get, "get", "Resolve one state or capture field and return its JSON scalar.", parse_get, execute_get, .Raw, destroy_get, .None, Get_Command},
	{.Quit, "quit", "Close the session.", parse_no_fields, execute_quit, .Skip, nil, .None, No_Fields_Command},
}

command_row_by_name :: proc(name: string) -> (^Command_Row, bool) {
	for &row in COMMANDS {
		if row.name == name {
			return &row, true
		}
	}
	return nil, false
}

command_row_by_kind :: proc(kind: Command_Kind) -> ^Command_Row {
	for &row in COMMANDS {
		if row.kind == kind {
			return &row
		}
	}
	panic("harness: command kind has no registry row")
}

@(private)
parse_no_fields :: proc(object: json.Object, allocator: mem.Allocator) -> (Command, string) {
	if key, unknown := json_unknown_key(object, {"cmd"}); unknown {
		return {}, format_error("unknown key %q", key)
	}
	return {}, ""
}

@(private)
destroy_capture :: proc(command: ^Command, allocator: mem.Allocator) {
	delete(command.capture.name, allocator)
	if command.capture.note != "" {
		delete(command.capture.note, allocator)
	}
	command^ = {}
}

@(private)
destroy_captures :: proc(command: ^Command, allocator: mem.Allocator) {
	for &output in command.captures.outputs {
		delete(output.name, allocator)
		if output.note != "" {
			delete(output.note, allocator)
		}
	}
	delete(command.captures.outputs, allocator)
	command^ = {}
}

@(private)
destroy_record :: proc(command: ^Command, allocator: mem.Allocator) {
	delete(command.record.path, allocator)
	command^ = {}
}

@(private)
destroy_replay :: proc(command: ^Command, allocator: mem.Allocator) {
	delete(command.replay.path, allocator)
	command^ = {}
}

@(private)
destroy_repro :: proc(command: ^Command, allocator: mem.Allocator) {
	delete(command.repro.path, allocator)
	command^ = {}
}

@(private)
destroy_perf :: proc(command: ^Command, allocator: mem.Allocator) {
	if command.perf.has_trace {
		delete(command.perf.trace, allocator)
	}
	if command.perf.has_name {
		delete(command.perf.name, allocator)
	}
	command^ = {}
}

@(private)
destroy_displays :: proc(command: ^Command, allocator: mem.Allocator) {
	displays_command_destroy(&command.displays, allocator)
	command^ = {}
}
