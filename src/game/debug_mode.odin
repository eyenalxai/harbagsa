#+vet explicit-allocators
#+vet !unused-procedures // the agent harness calls this API; the game binary does not
package game

import "core:math"
import "core:mem"

import b3 "libs:box3d"

DEBUG_FLY_SPEED :: 10.0

Debug_Camera :: struct {
	position: b3.Vec3,
	yaw:      f32,
	pitch:    f32,
}

Saved_Player :: struct {
	position:     b3.Vec3,
	yaw:          f32,
	camera_yaw:   f32,
	camera_pitch: f32,
}

// Debug mode is the F2 camera mode: the active flag, the free-fly camera, and the
// saved player. The editor owns the editing state and survives a mode toggle.
Debug_Mode :: struct {
	active:        bool,
	physics_debug: bool,
	camera:        Debug_Camera,
	saved_player:  Saved_Player,
	editor:        Editor,
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
		editor = editor_create(allocator),
	}
}

debug_mode_destroy :: proc(dm: ^Debug_Mode) {
	editor_destroy(&dm.editor)
	dm^ = {}
}

debug_mode_toggle :: proc(dm: ^Debug_Mode, sim: ^Simulation) {
	if dm.active {
		debug_mode_exit(dm, sim)
	} else {
		debug_mode_enter(dm, sim)
	}
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
	editor_end_drag(&dm.editor)
	save_player_and_sync_camera(dm, sim)
}

debug_mode_reset_scene :: proc(dm: ^Debug_Mode, sim: ^Simulation) {
	simulation_reset_scene(sim)
	editor_reset(&dm.editor)
	save_player_and_sync_camera(dm, sim)
}

// The settings menu owns the input while it is open, so opening it ends the
// current edit.
debug_mode_cancel_editing :: proc(dm: ^Debug_Mode) {
	editor_cancel_editing(&dm.editor)
}

debug_mode_open_menu :: proc(dm: ^Debug_Mode, menu: ^Menu_State) {
	menu_open(menu)
	debug_mode_cancel_editing(dm)
	_ = editor_set_inspector(&dm.editor, false)
}

@(private)
debug_mode_enter :: proc(dm: ^Debug_Mode, sim: ^Simulation) {
	dm.active = true
	dm.editor.inspector_open = false
	editor_clear_selection(&dm.editor)
	save_player_and_sync_camera(dm, sim)
}

@(private)
debug_mode_exit :: proc(dm: ^Debug_Mode, sim: ^Simulation) {
	dm.active = false
	dm.editor.inspector_open = false
	editor_clear_selection(&dm.editor)
	debug_mode_cancel_editing(dm)

	player_place(&sim.player, dm.saved_player.position, dm.saved_player.yaw, 0.0)
	sim.player.camera_yaw = dm.saved_player.camera_yaw
	sim.player.camera_pitch = dm.saved_player.camera_pitch
	spider_plant_legs(sim)
}

@(private)
saved_player :: proc(sim: ^Simulation) -> Saved_Player {
	return {
		position = sim.player.position,
		yaw = sim.player.yaw,
		camera_yaw = sim.player.camera_yaw,
		camera_pitch = sim.player.camera_pitch,
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
	camera := spider_camera(sim, 1.0)
	return {
		position = camera.position,
		yaw = camera.yaw,
		pitch = camera.pitch,
	}
}
