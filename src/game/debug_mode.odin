#+vet explicit-allocators
#+vet !unused-procedures // the agent harness and tests call this API; the game binary does not
package game

import "core:math"
import "core:mem"

import b3 "libs:box3d"

// The real sun subtends about 0.53 degrees. A wider disk softens every shadow
// by the same factor and smears a wall shadow when the sun sits low.
SUN_ANGULAR_DIAMETER :: 0.53 * math.PI / 180.0

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
	sun_angular_diameter: f32,
}

Debug_Motion :: struct {
	move_forward: f32,
	move_right:   f32,
	move_up:      f32,
	look_delta:   [2]f32,
	captured:     bool,
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
		sun_angular_diameter = SUN_ANGULAR_DIAMETER,
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
	return sun_angles_from_direction(sun_direction_from_light(debug_mode_sun_direction(dm)))
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
	dm.sun_angular_diameter = SUN_ANGULAR_DIAMETER
	debug_mode_clear_selection(dm)
	save_player_and_sync_camera(dm, sim)
}


// The palette, the placement tool, and the sun placement are mutually
// exclusive, and the settings menu owns the input while it is open.
debug_mode_cancel_editing :: proc(dm: ^Debug_Mode) {
	debug_mode_end_drag(dm)
	take_tool(dm, .None)
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

