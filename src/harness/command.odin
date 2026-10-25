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
	Repro,
	Perf,
	Renderer_Debug,
	Displays,
	Rows,
	Scene,
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
	name:      string,
	frame:     int,
	has_frame: bool,
	alpha:     f32,
	has_alpha: bool,
	target:    Capture_Target,
	format:    Capture_Format,
	png:       bool,
	region:    Maybe(Capture_Region),
	profile:   Maybe(Capture_Profile),
	crop:      Maybe(Capture_Crop),
	histogram: Maybe(int),
}

Camera_Command :: struct {
	position:     [3]f32,
	look_at:      [3]f32,
	yaw_rad:      f32,
	pitch_rad:    f32,
	fov_deg:      f32,
	has_look_at:  bool,
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
}

Replay_Command :: struct {
	path: string,
}

Repro_Command :: struct {
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
	repro:          Repro_Command,
	perf:           Perf_Command,
	renderer_debug: Renderer_Debug_Command,
	displays:       Displays_Command,
	scene:          Scene_Command,
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
