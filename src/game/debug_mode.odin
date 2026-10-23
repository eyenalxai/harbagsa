#+vet explicit-allocators
package game

import "core:math"

import b3 "libs:box3d"

DEFAULT_SUN_DIRECTION :: [3]f32{-0.45, -1.0, -0.35}
DEBUG_FLY_SPEED :: 10.0

Debug_Selection :: enum {
	None,
	Crate,
	Sun,
}

Debug_Drag :: enum {
	None,
	Crate,
	Sun,
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

Debug_Mode :: struct {
	active:            bool,
	camera:            Debug_Camera,
	saved_player:      Saved_Player,
	sun_direction:     [3]f32,
	selection:         Debug_Selection,
	selected_crate:    int,
	dragging:          Debug_Drag,
	drag_position:     b3.Vec3,
	sun_azimuth:       f32,
	sun_elevation:     f32,
	sun_drag_dx:       f32,
	sun_drag_dy:       f32,
}

Debug_Input :: struct {
	move_forward:     f32,
	move_right:       f32,
	move_up:          f32,
	look_delta:       [2]f32,
	wheel_delta:      f32,
	primary_pressed:  bool,
	primary_released: bool,
	add_pressed:      bool,
	delete_pressed:   bool,
	sun_pressed:      bool,
	captured:         bool,
}

debug_mode_create :: proc() -> Debug_Mode {
	return {
		sun_direction = DEFAULT_SUN_DIRECTION,
		selected_crate = -1,
	}
}

debug_mode_toggle :: proc(dm: ^Debug_Mode, sim: ^Simulation) {
	if dm.active {
		debug_mode_exit(dm, sim)
	} else {
		debug_mode_enter(dm, sim)
	}
}

debug_mode_sun_direction :: proc(dm: ^Debug_Mode) -> [3]f32 {
	length := math.sqrt(
		dm.sun_direction.x * dm.sun_direction.x +
		dm.sun_direction.y * dm.sun_direction.y +
		dm.sun_direction.z * dm.sun_direction.z,
	)
	if length <= 0.0 {
		return DEFAULT_SUN_DIRECTION
	}
	return dm.sun_direction * (1.0 / length)
}

debug_mode_sun_angles :: proc(dm: ^Debug_Mode) -> (azimuth, elevation: f32) {
	return sun_angles_from_direction(dm.sun_direction)
}

debug_mode_clear_selection :: proc(dm: ^Debug_Mode) {
	debug_mode_end_drag(dm)
	dm.selection = .None
	dm.selected_crate = -1
}

debug_mode_end_drag :: proc(dm: ^Debug_Mode) {
	dm.dragging = .None
	dm.sun_drag_dx = 0.0
	dm.sun_drag_dy = 0.0
}

debug_selected_crate :: proc(dm: ^Debug_Mode, sim: ^Simulation) -> (index: int, ok: bool) {
	if dm.selection != .Crate ||
	   dm.selected_crate < 0 ||
	   dm.selected_crate >= simulation_crate_count(sim) {
		return -1, false
	}
	return dm.selected_crate, true
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
	dm.sun_direction = DEFAULT_SUN_DIRECTION
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
	debug_edit_crates(dm, sim, input)
	debug_edit_sun(dm, input)
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
		position = sim.player.position + b3.Vec3{0.0, PLAYER_EYE_HEIGHT, 0.0},
		yaw = sim.player.yaw,
		pitch = sim.player.pitch,
	}
}

@(private)
debug_fly :: proc(dm: ^Debug_Mode, input: Debug_Input, delta: f32) {
	if !input.captured || delta <= 0.0 {
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
