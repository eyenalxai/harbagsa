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
	Settle,
	State,
	Capture,
	Camera,
	View,
	Sun,
	Debug_Mode,
	Menu,
	Check,
	Record,
	Replay,
	Perf,
	Renderer_Debug,
	Quit,
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
	target:    Capture_Target,
	format:    Capture_Format,
}

Camera_Command :: struct {
	position: [3]f32,
	yaw:      f32,
	pitch:    f32,
	clear:    bool,
}

Sun_Command :: struct {
	azimuth:       f32,
	elevation:     f32,
	diameter:      f32,
	has_azimuth:   bool,
	has_elevation: bool,
	has_diameter:  bool,
}

View_Command :: struct {
	hud:       bool,
	debug:     bool,
	hint:      bool,
	perf:      bool,
	has_hud:   bool,
	has_debug: bool,
	has_hint:  bool,
	has_perf:  bool,
}

Record_Command :: struct {
	path:     string,
	has_path: bool,
}

Replay_Command :: struct {
	path: string,
}

Renderer_Debug_Command :: struct {
	clear:                   bool,
	taa:                     bool,
	jitter:                  bool,
	history_weight:          f32,
	clamp:                   bool,
	depth_trust:             bool,
	freeze_shadow_phase:     bool,
	shadow_phase:            int,
	sky:                     bool,
	ao:                      bool,
	has_taa:                 bool,
	has_jitter:              bool,
	has_history_weight:      bool,
	has_clamp:               bool,
	has_depth_trust:         bool,
	has_freeze_shadow_phase: bool,
	has_shadow_phase:        bool,
	has_sky:                 bool,
	has_ao:                  bool,
}

Command :: struct {
	kind:    Command_Kind,
	look:    Look_Command,
	face:    Face_Command,
	input:   Input_Command,
	step:    Step_Command,
	settle:  Settle_Command,
	capture: Capture_Command,
	camera:  Camera_Command,
	view:       View_Command,
	sun:        Sun_Command,
	debug_mode: Debug_Mode_Command,
	menu:       Menu_Command,
	check:   Check_Command,
	record:  Record_Command,
	replay:  Replay_Command,
	perf:    Perf_Command,
	renderer_debug: Renderer_Debug_Command,
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
	case .Settle:
		return "settle"
	case .State:
		return "state"
	case .Capture:
		return "capture"
	case .Camera:
		return "camera"
	case .View:
		return "view"
	case .Sun:
		return "sun"
	case .Debug_Mode:
		return "debug_mode"
	case .Menu:
		return "menu"
	case .Check:
		return "check"
	case .Record:
		return "record"
	case .Replay:
		return "replay"
	case .Perf:
		return "perf"
	case .Renderer_Debug:
		return "renderer_debug"
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
	case .Perf:
		if command.perf.has_trace {
			delete(command.perf.trace, allocator)
		}
	}
	command^ = {}
}

check_value_destroy :: proc(value: ^Check_Value, allocator: mem.Allocator) {
	if value.kind == .String && value.text != "" {
		delete(value.text, allocator)
	}
	value^ = {}
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
	case "settle":
		return parse_settle(object)
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
	case "sun":
		return parse_sun(object)
	case "debug_mode":
		return parse_debug_mode(object)
	case "menu":
		return parse_menu(object)
	case "check":
		return parse_check(object, allocator)
	case "record":
		return parse_record(object, allocator)
	case "replay":
		return parse_replay(object, allocator)
	case "perf":
		return parse_perf(object, allocator)
	case "renderer_debug":
		return parse_renderer_debug(object)
	case "quit":
		if key, unknown := json_unknown_key(object, {"cmd"}); unknown {
			return {}, format_error("unknown key %q", key)
		}
		return {kind = .Quit}, ""
	}
	return {}, format_error("unknown command %q", name)
}

