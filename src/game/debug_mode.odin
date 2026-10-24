#+vet explicit-allocators
#+vet !unused-procedures // the agent harness and tests call this API; the game binary does not
package game

import "core:math"
import "core:mem"

import b3 "libs:box3d"

DEBUG_FLY_SPEED :: 10.0

Debug_Selection :: enum {
	None,
	Object,
}

Debug_Drag :: enum {
	None,
	Object,
}

Debug_Camera :: struct {
	position: b3.Vec3,
	yaw:      f32,
	pitch:    f32,
}

Saved_Player :: struct {
	position: b3.Vec3,
	yaw:      f32,
	pitch:    f32,
}

Sun_Placement :: struct {
	active:         bool,
	saved_position: [3]f32,
	position:       [3]f32,
}

Debug_Mode :: struct {
	active:             bool,
	camera:             Debug_Camera,
	saved_player:       Saved_Player,
	sun:                Sun_Placement,
	selection:          Debug_Selection,
	selected_object_id: Object_Id,
	dragging:           Debug_Drag,
	drag_position:      b3.Vec3,
	drag_recorded:      bool,
	history:            ^Object_History,
	history_allocator:  mem.Allocator,
	palette:            Palette,
	placement:          Placement,
}

Debug_Input :: struct {
	move_forward:           f32,
	move_right:            f32,
	move_up:               f32,
	look_delta:            [2]f32,
	wheel_delta:           f32,
	primary_pressed:       bool,
	primary_released:      bool,
	secondary_pressed:     bool,
	delete_pressed:        bool,
	duplicate_pressed:     bool,
	undo_pressed:          bool,
	redo_pressed:          bool,
	rotate_left:           bool,
	rotate_right:          bool,
	large_step:            bool,
	sun_placement_pressed: bool,
	light_color_pressed:          bool,
	light_intensity_down_pressed: bool,
	light_intensity_up_pressed:   bool,
	light_range_down_pressed:     bool,
	light_range_up_pressed:       bool,
	captured:              bool,
}

debug_mode_create :: proc(allocator: mem.Allocator) -> Debug_Mode {
	return {
		sun = {position = DEFAULT_SUN_POSITION},
		history_allocator = allocator,
		palette = {
			selected = 0,
			body_mode = prefab(.Crate).body_mode,
		},
		placement = {
			prefab = .Crate,
		},
	}
}

debug_mode_destroy :: proc(dm: ^Debug_Mode) {
	if dm.history != nil {
		allocator := dm.history.allocator
		object_history_destroy(dm.history)
		free(dm.history, allocator)
		dm.history = nil
	}
	dm^ = {}
}

// The history itself lives on the heap. It is allocated on the first edit, so a
// fresh debug mode and a fresh Session stay small.
debug_history :: proc(dm: ^Debug_Mode) -> ^Object_History {
	if dm.history == nil {
		dm.history = new(Object_History, dm.history_allocator)
		dm.history^ = object_history_create(dm.history_allocator)
	}
	return dm.history
}

debug_mode_toggle :: proc(dm: ^Debug_Mode, sim: ^Simulation) {
	if dm.active {
		debug_mode_exit(dm, sim)
	} else {
		debug_mode_enter(dm, sim)
	}
}

debug_mode_sun_direction :: proc(dm: ^Debug_Mode) -> [3]f32 {
	return sun_direction_from_position(dm.sun.position)
}

debug_mode_sun_angles :: proc(dm: ^Debug_Mode) -> (azimuth, elevation: f32) {
	return sun_angles_from_direction(debug_mode_sun_direction(dm))
}

debug_mode_clear_selection :: proc(dm: ^Debug_Mode) {
	debug_mode_end_drag(dm)
	dm.selection = .None
	dm.selected_object_id = INVALID_OBJECT_ID
}

debug_mode_end_drag :: proc(dm: ^Debug_Mode) {
	dm.dragging = .None
	dm.drag_recorded = false
}

debug_history_depth :: proc(dm: ^Debug_Mode) -> int {
	if dm.history == nil {
		return 0
	}
	return object_history_depth(dm.history)
}

debug_history_redo_depth :: proc(dm: ^Debug_Mode) -> int {
	if dm.history == nil {
		return 0
	}
	return object_history_redo_depth(dm.history)
}

debug_selected_object_id :: proc(dm: ^Debug_Mode, sim: ^Simulation) -> (Object_Id, bool) {
	if dm.selection != .Object || dm.selected_object_id == INVALID_OBJECT_ID {
		return INVALID_OBJECT_ID, false
	}
	if _, ok := simulation_object_find(sim, dm.selected_object_id); !ok {
		return INVALID_OBJECT_ID, false
	}
	return dm.selected_object_id, true
}

debug_camera_forward :: proc(camera: Debug_Camera) -> b3.Vec3 {
	cos_pitch := math.cos(camera.pitch)
	return {
		-math.sin(camera.yaw) * cos_pitch,
		math.sin(camera.pitch),
		-math.cos(camera.yaw) * cos_pitch,
	}
}

debug_camera_forward_horizontal :: proc(camera: Debug_Camera) -> b3.Vec3 {
	return yaw_forward_horizontal(camera.yaw)
}

debug_camera_right :: proc(camera: Debug_Camera) -> b3.Vec3 {
	return yaw_right(camera.yaw)
}

debug_mode_reset_player :: proc(dm: ^Debug_Mode, sim: ^Simulation) {
	simulation_reset(sim)
	debug_mode_end_drag(dm)
	save_player_and_sync_camera(dm, sim)
}

debug_mode_reset_scene :: proc(dm: ^Debug_Mode, sim: ^Simulation) {
	simulation_reset_scene(sim)
	if dm.history != nil {
		object_history_clear(dm.history)
	}
	debug_sun_reset(dm)
	debug_mode_clear_selection(dm)
	save_player_and_sync_camera(dm, sim)
}

debug_mode_update :: proc(dm: ^Debug_Mode, sim: ^Simulation, input: Debug_Input, delta: f32) {
	if !dm.active {
		return
	}
	if !input.captured {
		debug_mode_end_drag(dm)
	}

	if input.captured && dm.dragging == .None && !input.primary_pressed {
		dm.camera.yaw = b3.UnwindAngle(dm.camera.yaw - input.look_delta.x * YAW_SENSITIVITY)
		dm.camera.pitch = clamp(
			dm.camera.pitch - input.look_delta.y * PITCH_SENSITIVITY,
			-PITCH_LIMIT,
			PITCH_LIMIT,
		)
	}

	debug_fly(dm, input, delta)
	// The sun mode owns the click that leaves it, so the same click cannot also
	// select a placed object.
	if !debug_edit_sun(dm, sim, input) {
		debug_edit_lights(dm, sim, input)
		debug_edit_objects(dm, sim, input)
	}
	debug_placement_refresh(dm, sim)
}

// The palette, the placement tool, and the sun placement are mutually
// exclusive, and the settings menu owns the input while it is open.
debug_mode_cancel_editing :: proc(dm: ^Debug_Mode) {
	debug_mode_end_drag(dm)
	palette_close(&dm.palette)
	debug_placement_cancel(dm)
	debug_sun_cancel(dm)
}

@(private)
debug_mode_enter :: proc(dm: ^Debug_Mode, sim: ^Simulation) {
	dm.active = true
	debug_mode_clear_selection(dm)
	save_player_and_sync_camera(dm, sim)
}

@(private)
debug_mode_exit :: proc(dm: ^Debug_Mode, sim: ^Simulation) {
	dm.active = false
	debug_mode_clear_selection(dm)
	debug_mode_cancel_editing(dm)

	player_place(&sim.player, dm.saved_player.position, dm.saved_player.yaw, dm.saved_player.pitch)
}

@(private)
saved_player :: proc(sim: ^Simulation) -> Saved_Player {
	return {
		position = sim.player.position,
		yaw = sim.player.yaw,
		pitch = sim.player.pitch,
	}
}

@(private)
save_player_and_sync_camera :: proc(dm: ^Debug_Mode, sim: ^Simulation) {
	dm.saved_player = saved_player(sim)
	if dm.active {
		dm.camera = camera_from_player(sim)
	}
}

@(private)
camera_from_player :: proc(sim: ^Simulation) -> Debug_Camera {
	return {
		position = sim.player.position + b3.Vec3{0.0, sim.player.eye_height, 0.0},
		yaw = sim.player.yaw,
		pitch = sim.player.pitch,
	}
}

@(private)
debug_fly :: proc(dm: ^Debug_Mode, input: Debug_Input, delta: f32) {
	if delta <= 0.0 {
		return
	}

	forward := debug_camera_forward_horizontal(dm.camera)
	right := debug_camera_right(dm.camera)
	move := forward * input.move_forward + right * input.move_right
	move.y = input.move_up

	length := b3.Length(move)
	if length > 1.0 {
		move = move * (1.0 / length)
	}
	dm.camera.position += move * (DEBUG_FLY_SPEED * delta)
}
