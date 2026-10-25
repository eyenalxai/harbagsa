#+vet explicit-allocators
package harness

import "core:mem"

import "src:renderer"

No_Fields_Command :: struct {}

Command_Kind :: enum {
	Reset,
	Look,
	Face,
	Input,
	Step,
	Settle,
	State,
	Capture,
	Captures,
	Camera,
	View,
	Sun,
	Debug_Mode,
	Editor,
	Menu,
	Check,
	Record,
	Replay,
	Repro,
	Perf,
	Renderer_Debug,
	Displays,
	Rows,
	Scene,
	Place,
	Remove,
	Get,
	Reference,
	Quit,
}

Look_Command :: struct {
	dx: f32,
	dy: f32,
}

Face_Command :: struct {
	yaw_rad:   f32,
	pitch_rad: f32,
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
	using spec: Capture_Spec,
	frame:     int,
	has_frame: bool,
	alpha:     f32,
	has_alpha: bool,
}

Captures_Command :: struct {
	frame:      int,
	has_frame:  bool,
	alpha:      f32,
	has_alpha:  bool,
	outputs:    []Capture_Command,
}

Camera_Command :: struct {
	position:     [3]f32,
	yaw_rad:      f32,
	pitch_rad:    f32,
	fov_deg:      f32,
	has_fov:      bool,
	has_angles:   bool,
	clear:        bool,
}

Sun_Command :: struct {
	azimuth_deg:   f32,
	elevation_deg: f32,
	diameter_deg:  f32,
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
	actions:  bool,
}

Replay_Command :: struct {
	path: string,
}

Repro_Command :: struct {
	path: string,
}

Renderer_Debug_Field :: enum {
	TAA,
	Jitter,
	History_Weight,
	Clamp,
	Depth_Trust,
	Freeze_Shadow_Phase,
	Shadow_Phase,
	Light_Shadows,
	Synthetic_Lights,
	Sky,
	GI,
	AO,
	AO_Radius,
	AO_Strength,
	Clip_Height,
}

Renderer_Debug_Resets :: bit_set[Renderer_Debug_Field]

Renderer_Debug_Command :: struct {
	clear: bool,
	reset: Renderer_Debug_Resets,
	using patch: renderer.Renderer_Debug_Patch,
}

Command :: struct {
	kind:           Command_Kind,
	look:           Look_Command,
	face:           Face_Command,
	input:          Input_Command,
	step:           Step_Command,
	settle:         Settle_Command,
	capture:        Capture_Command,
	captures:       Captures_Command,
	camera:         Camera_Command,
	view:           View_Command,
	sun:            Sun_Command,
	debug_mode:     Debug_Mode_Command,
	editor:         Editor_Command,
	menu:           Menu_Command,
	check:          Check_Command,
	record:         Record_Command,
	replay:         Replay_Command,
	repro:          Repro_Command,
	perf:           Perf_Command,
	renderer_debug: Renderer_Debug_Command,
	displays:       Displays_Command,
	scene:          Scene_Command,
	place:          Place_Command,
	remove:         Remove_Command,
	get:            Get_Command,
	reference:      Reference_Command,
}

command_name :: proc(kind: Command_Kind) -> string {
	return command_row_by_kind(kind).name
}

command_destroy :: proc(command: ^Command, allocator: mem.Allocator) {
	row := command_row_by_kind(command.kind)
	if row.destroy != nil {
		row.destroy(command, allocator)
		return
	}
	command^ = {}
}

check_value_destroy :: proc(value: ^Check_Value, allocator: mem.Allocator) {
	if value.kind == .String && value.text != "" {
		delete(value.text, allocator)
	}
	value^ = {}
}
