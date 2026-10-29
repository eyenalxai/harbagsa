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
	Debug_Mode,
	Editor,
	Menu,
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
	Bake,
	Get,
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
	sprint:      bool,
	has_forward: bool,
	has_right:   bool,
	has_jump:    bool,
	has_sprint:  bool,
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
	// A list of one to eight views; the command expands into one capture entry
	// per view, named `<name>-<view>`.
	views:     []renderer.Capture_View,
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
	Synthetic_Lights,
	Clip_Height,
	Light_Shadows,
	Lightmap,
	Probe,
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
	debug_mode:     Debug_Mode_Command,
	editor:         Editor_Command,
	menu:           Menu_Command,
	record:         Record_Command,
	replay:         Replay_Command,
	repro:          Repro_Command,
	perf:           Perf_Command,
	renderer_debug: Renderer_Debug_Command,
	displays:       Displays_Command,
	scene:          Scene_Command,
	place:          Place_Command,
	remove:         Remove_Command,
	bake:           Bake_Command,
	get:            Get_Command,
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
