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

// One row per command. The parser, dispatcher, recorder, destroy path, and
// backend policy all read this table; a new command is one row plus its test.
Command_Row :: struct {
	kind:       Command_Kind,
	name:       string,
	parse:      Command_Parse,
	execute:    Command_Execute,
	record:     Command_Record,
	destroy:    Command_Destroy,
	backend:    Command_Backend,
	value_type: typeid,
}

COMMANDS := [?]Command_Row {
	{.Reset, "reset", parse_no_fields, execute_reset, .Raw, nil, .None, No_Fields_Command},
	{.Look, "look", parse_look_row, execute_look, .Raw, nil, .None, Look_Command},
	{.Face, "face", parse_face_row, execute_face, .Raw, nil, .None, Face_Command},
	{.Input, "input", parse_input_row, execute_input, .Raw, nil, .None, Input_Command},
	{.Step, "step", parse_step_row, execute_step, .Raw, nil, .None, Step_Command},
	{.Settle, "settle", parse_settle_row, execute_settle, .Raw, nil, .Optional, Settle_Command},
	{.State, "state", parse_no_fields, execute_state, .Raw, nil, .None, No_Fields_Command},
	{.Capture, "capture", parse_capture, execute_capture, .Custom, destroy_capture, .Optional, Capture_Command},
	{.Captures, "captures", parse_captures, execute_captures, .Skip, destroy_captures, .Optional, Captures_Command},
	{.Camera, "camera", parse_camera_row, execute_camera, .Raw, nil, .None, Camera_Command},
	{.View, "view", parse_view_row, execute_view, .Raw, nil, .None, View_Command},
	{.Sun, "sun", parse_sun_row, execute_sun, .Raw, nil, .None, Sun_Command},
	{.Debug_Mode, "debug_mode", parse_debug_mode_row, execute_debug_mode, .Raw, nil, .None, Debug_Mode_Command},
	{.Editor, "editor", parse_editor_row, execute_editor, .Raw, nil, .None, Editor_Command},
	{.Menu, "menu", parse_menu_row, execute_menu, .Raw, nil, .None, Menu_Command},
	{.Check, "check", parse_check, execute_check, .Raw, destroy_check, .None, Check_Command},
	{.Record, "record", parse_record, execute_record, .Skip, destroy_record, .None, Record_Command},
	{.Replay, "replay", parse_replay, execute_replay, .Skip, destroy_replay, .Optional, Replay_Command},
	{.Repro, "repro", parse_repro, execute_repro, .Skip, destroy_repro, .None, Repro_Command},
	{.Perf, "perf", parse_perf, execute_perf, .Skip, destroy_perf, .Required, Perf_Command},
	{.Renderer_Debug, "renderer_debug", parse_renderer_debug_row, execute_renderer_debug, .Raw, nil, .Optional, Renderer_Debug_Command},
	{.Displays, "displays", parse_displays, execute_displays, .Raw, destroy_displays, .None, Displays_Command},
	{.Rows, "rows", parse_no_fields, execute_rows, .Skip, nil, .None, No_Fields_Command},
	{.Scene, "scene", parse_scene, execute_scene, .Raw, destroy_scene, .None, Scene_Command},
	{.Quit, "quit", parse_no_fields, execute_quit, .Skip, nil, .None, No_Fields_Command},
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
parse_look_row :: proc(object: json.Object, allocator: mem.Allocator) -> (Command, string) {
	return parse_look(object)
}

@(private)
parse_face_row :: proc(object: json.Object, allocator: mem.Allocator) -> (Command, string) {
	return parse_face(object)
}

@(private)
parse_input_row :: proc(object: json.Object, allocator: mem.Allocator) -> (Command, string) {
	return parse_input(object)
}

@(private)
parse_step_row :: proc(object: json.Object, allocator: mem.Allocator) -> (Command, string) {
	return parse_step(object)
}

@(private)
parse_settle_row :: proc(object: json.Object, allocator: mem.Allocator) -> (Command, string) {
	return parse_settle(object)
}

@(private)
parse_camera_row :: proc(object: json.Object, allocator: mem.Allocator) -> (Command, string) {
	return parse_camera(object)
}

@(private)
parse_view_row :: proc(object: json.Object, allocator: mem.Allocator) -> (Command, string) {
	return parse_view(object)
}

@(private)
parse_sun_row :: proc(object: json.Object, allocator: mem.Allocator) -> (Command, string) {
	return parse_sun(object)
}

@(private)
parse_debug_mode_row :: proc(object: json.Object, allocator: mem.Allocator) -> (Command, string) {
	return parse_debug_mode(object)
}

@(private)
parse_editor_row :: proc(object: json.Object, allocator: mem.Allocator) -> (Command, string) {
	return parse_editor(object)
}

@(private)
parse_menu_row :: proc(object: json.Object, allocator: mem.Allocator) -> (Command, string) {
	return parse_menu(object)
}

@(private)
parse_renderer_debug_row :: proc(object: json.Object, allocator: mem.Allocator) -> (Command, string) {
	return parse_renderer_debug(object)
}

@(private)
destroy_capture :: proc(command: ^Command, allocator: mem.Allocator) {
	delete(command.capture.name, allocator)
	command^ = {}
}

@(private)
destroy_captures :: proc(command: ^Command, allocator: mem.Allocator) {
	for &output in command.captures.outputs {
		delete(output.name, allocator)
	}
	delete(command.captures.outputs, allocator)
	command^ = {}
}

@(private)
destroy_check :: proc(command: ^Command, allocator: mem.Allocator) {
	delete(command.check.field, allocator)
	if command.check.has_other {
		delete(command.check.other, allocator)
	}
	check_value_destroy(&command.check.value, allocator)
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
