#+vet explicit-allocators
package harness

import "core:encoding/json"
import "core:mem"

Command_Kind :: enum {
	Reset,
	Look,
	Face,
	Input,
	Step,
	State,
	Capture,
	Camera,
	View,
	Menu,
	Check,
	Record,
	Replay,
	Quit,
}

Check_Op :: enum {
	Eq,
	Ne,
	Lt,
	Le,
	Gt,
	Ge,
}

Value_Kind :: enum {
	Number,
	Bool,
	String,
}

Check_Value :: struct {
	kind:    Value_Kind,
	number:  f64,
	boolean: bool,
	text:    string,
}

Look_Command :: struct {
	dx: f32,
	dy: f32,
}

Face_Command :: struct {
	yaw:   f32,
	pitch: f32,
}

Input_Command :: struct {
	forward:     f32,
	right:       f32,
	jump:        bool,
	has_forward: bool,
	has_right:   bool,
	has_jump:    bool,
}

Step_Command :: struct {
	frames: int,
}

Capture_Command :: struct {
	name:      string,
	frame:     int,
	has_frame: bool,
	alpha:     f32,
	has_alpha: bool,
}

Camera_Command :: struct {
	position: [3]f32,
	yaw:      f32,
	pitch:    f32,
	clear:    bool,
}

View_Command :: struct {
	hud:       bool,
	debug:     bool,
	hint:      bool,
	has_hud:   bool,
	has_debug: bool,
	has_hint:  bool,
}

Check_Command :: struct {
	field:  string,
	op:     Check_Op,
	value:  Check_Value,
	warmup: int,
}

Record_Command :: struct {
	path:     string,
	has_path: bool,
}

Replay_Command :: struct {
	path: string,
}

Command :: struct {
	kind:    Command_Kind,
	look:    Look_Command,
	face:    Face_Command,
	input:   Input_Command,
	step:    Step_Command,
	capture: Capture_Command,
	camera:  Camera_Command,
	view:    View_Command,
	menu:    Menu_Command,
	check:   Check_Command,
	record:  Record_Command,
	replay:  Replay_Command,
}

command_name :: proc(kind: Command_Kind) -> string {
	switch kind {
	case .Reset:
		return "reset"
	case .Look:
		return "look"
	case .Face:
		return "face"
	case .Input:
		return "input"
	case .Step:
		return "step"
	case .State:
		return "state"
	case .Capture:
		return "capture"
	case .Camera:
		return "camera"
	case .View:
		return "view"
	case .Menu:
		return "menu"
	case .Check:
		return "check"
	case .Record:
		return "record"
	case .Replay:
		return "replay"
	case .Quit:
		return "quit"
	}
	return "unknown"
}

command_destroy :: proc(command: ^Command, allocator: mem.Allocator) {
	#partial switch command.kind {
	case .Capture:
		delete(command.capture.name, allocator)
	case .Check:
		delete(command.check.field, allocator)
		check_value_destroy(&command.check.value, allocator)
	case .Record:
		delete(command.record.path, allocator)
	case .Replay:
		delete(command.replay.path, allocator)
	}
	command^ = {}
}

check_value_destroy :: proc(value: ^Check_Value, allocator: mem.Allocator) {
	if value.kind == .String && value.text != "" {
		delete(value.text, allocator)
	}
	value^ = {}
}

check_op_name :: proc(op: Check_Op) -> string {
	switch op {
	case .Eq:
		return "eq"
	case .Ne:
		return "ne"
	case .Lt:
		return "lt"
	case .Le:
		return "le"
	case .Gt:
		return "gt"
	case .Ge:
		return "ge"
	}
	return "eq"
}

check_op_parse :: proc(name: string) -> (op: Check_Op, ok: bool) {
	switch name {
	case "eq":
		return .Eq, true
	case "ne":
		return .Ne, true
	case "lt":
		return .Lt, true
	case "le":
		return .Le, true
	case "gt":
		return .Gt, true
	case "ge":
		return .Ge, true
	}
	return .Eq, false
}

command_parse_string :: proc(line: string, allocator := context.allocator) -> (Command, string) {
	value, parse_error := json.parse_string(line, .JSON, true, allocator)
	if parse_error != .None {
		return {}, format_error("invalid JSON: %v", parse_error)
	}
	defer json.destroy_value(value, allocator)
	return command_parse(value, allocator)
}

command_parse :: proc(value: json.Value, allocator := context.allocator) -> (Command, string) {
	object, object_ok := json_object(value)
	if !object_ok {
		return {}, "command must be an object"
	}
	cmd_value, has_cmd := json_get(object, "cmd")
	if !has_cmd {
		return {}, "command is missing 'cmd'"
	}
	name, name_ok := json_string(cmd_value)
	if !name_ok {
		return {}, "'cmd' must be a string"
	}

	switch name {
	case "reset":
		if key, unknown := json_unknown_key(object, {"cmd"}); unknown {
			return {}, format_error("unknown key %q", key)
		}
		return {kind = .Reset}, ""
	case "look":
		return parse_look(object)
	case "face":
		return parse_face(object)
	case "input":
		return parse_input(object)
	case "step":
		return parse_step(object)
	case "state":
		if key, unknown := json_unknown_key(object, {"cmd"}); unknown {
			return {}, format_error("unknown key %q", key)
		}
		return {kind = .State}, ""
	case "capture":
		return parse_capture(object, allocator)
	case "camera":
		return parse_camera(object)
	case "view":
		return parse_view(object)
	case "menu":
		return parse_menu(object)
	case "check":
		return parse_check(object, allocator)
	case "record":
		return parse_record(object, allocator)
	case "replay":
		return parse_replay(object, allocator)
	case "quit":
		if key, unknown := json_unknown_key(object, {"cmd"}); unknown {
			return {}, format_error("unknown key %q", key)
		}
		return {kind = .Quit}, ""
	}
	return {}, format_error("unknown command %q", name)
}

