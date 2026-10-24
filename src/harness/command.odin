#+vet explicit-allocators
package harness

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
	Editor,
	Menu,
	Check,
	Record,
	Replay,
	Perf,
	Renderer_Debug,
	Displays,
	Rows,
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
	region:    Maybe(Capture_Region),
	profile:   Maybe(Capture_Profile),
	crop:      Maybe(Capture_Crop),
	histogram: Maybe(int),
}

Camera_Command :: struct {
	position:     [3]f32,
	look_at:      [3]f32,
	yaw:          f32,
	pitch:        f32,
	fov:          f32,
	has_look_at:  bool,
	has_fov:      bool,
	has_angles:   bool,
	clear:        bool,
}

Sun_Command :: struct {
	azimuth:       f32,
	elevation:     f32,
	diameter:      f32,
	has_azimuth:   bool,
	has_elevation: bool,
	has_diameter:  bool,
	clear:         bool,
}

Display_Mode_Def :: struct {
	width:  i32,
	height: i32,
}

Display_Def :: struct {
	name:    string,
	desktop: Display_Mode_Def,
	has_desktop: bool,
	modes:   []Display_Mode_Def,
}

Displays_Command :: struct {
	set:     []Display_Def,
	clear:   bool,
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
	light_shadows:           bool,
	synthetic_lights:        int,
	sky:                     bool,
	ao:                      bool,
	has_taa:                 bool,
	has_jitter:              bool,
	has_history_weight:      bool,
	has_clamp:               bool,
	has_depth_trust:         bool,
	has_freeze_shadow_phase: bool,
	has_shadow_phase:        bool,
	has_light_shadows:       bool,
	has_synthetic_lights:    bool,
	has_sky:                 bool,
	has_ao:                  bool,
}

Command :: struct {
	kind:           Command_Kind,
	look:           Look_Command,
	face:           Face_Command,
	input:          Input_Command,
	step:           Step_Command,
	settle:         Settle_Command,
	capture:        Capture_Command,
	camera:         Camera_Command,
	view:           View_Command,
	sun:            Sun_Command,
	debug_mode:     Debug_Mode_Command,
	editor:         Editor_Command,
	menu:           Menu_Command,
	check:          Check_Command,
	record:         Record_Command,
	replay:         Replay_Command,
	perf:           Perf_Command,
	renderer_debug: Renderer_Debug_Command,
	displays:       Displays_Command,
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
	case .Editor:
		return "editor"
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
	case .Displays:
		return "displays"
	case .Rows:
		return "rows"
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
		if command.check.has_other {
			delete(command.check.other, allocator)
		}
		check_value_destroy(&command.check.value, allocator)
	case .Record:
		delete(command.record.path, allocator)
	case .Replay:
		delete(command.replay.path, allocator)
	case .Perf:
		if command.perf.has_trace {
			delete(command.perf.trace, allocator)
		}
		if command.perf.has_name {
			delete(command.perf.name, allocator)
		}
	case .Displays:
		displays_command_destroy(&command.displays, allocator)
	}
	command^ = {}
}

check_value_destroy :: proc(value: ^Check_Value, allocator: mem.Allocator) {
	if value.kind == .String && value.text != "" {
		delete(value.text, allocator)
	}
	value^ = {}
}
