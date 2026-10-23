#+vet explicit-allocators
package game

import "core:math"

import b3 "libs:box3d"

DEFAULT_LIGHT_DIRECTION :: [3]f32{-0.45, -1.0, -0.35}
DEBUG_FLY_SPEED :: 10.0

Debug_Selection :: enum {
	None,
	Crate,
	Light,
}

Debug_Drag :: enum {
	None,
	Crate,
	Light,
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
	light_direction:   [3]f32,
	selection:         Debug_Selection,
	selected_crate:    int,
	dragging:          Debug_Drag,
	drag_position:     b3.Vec3,
	light_azimuth:     f32,
	light_elevation:   f32,
	light_drag_motion: f32,
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
	light_pressed:    bool,
	captured:         bool,
}

debug_mode_create :: proc() -> Debug_Mode {
	return {
		light_direction = DEFAULT_LIGHT_DIRECTION,
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

debug_mode_camera :: proc(dm: ^Debug_Mode) -> Debug_Camera {
	return dm.camera
}

debug_mode_light_direction :: proc(dm: ^Debug_Mode) -> [3]f32 {
	length := math.sqrt(
		dm.light_direction.x * dm.light_direction.x +
		dm.light_direction.y * dm.light_direction.y +
		dm.light_direction.z * dm.light_direction.z,
	)
	if length <= 0.0 {
		return DEFAULT_LIGHT_DIRECTION
	}
	return dm.light_direction * (1.0 / length)
}

debug_mode_light_angles :: proc(dm: ^Debug_Mode) -> (azimuth, elevation: f32) {
	return light_angles_from_direction(dm.light_direction)
}

debug_mode_reset_player :: proc(dm: ^Debug_Mode, sim: ^Simulation) {
	simulation_reset(sim)
	dm.saved_player = saved_player(sim)
	dm.dragging = .None
	if dm.active {
		dm.camera = camera_from_player(sim)
	}
}

debug_mode_reset_scene :: proc(dm: ^Debug_Mode, sim: ^Simulation) {
	simulation_reset_scene(sim)
	dm.light_direction = DEFAULT_LIGHT_DIRECTION
	dm.selection = .None
	dm.selected_crate = -1
	dm.dragging = .None
	dm.light_drag_motion = 0.0
	dm.saved_player = saved_player(sim)
	if dm.active {
		dm.camera = camera_from_player(sim)
	}
}

debug_mode_update :: proc(dm: ^Debug_Mode, sim: ^Simulation, input: Debug_Input, delta: f32) {
	if !dm.active {
		return
	}
	if !input.captured {
		dm.dragging = .None
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
	debug_edit_light(dm, input)
}

@(private)
debug_mode_enter :: proc(dm: ^Debug_Mode, sim: ^Simulation) {
	dm.active = true
	dm.selection = .None
	dm.selected_crate = -1
	dm.dragging = .None
	dm.light_drag_motion = 0.0
	dm.saved_player = saved_player(sim)
	dm.camera = camera_from_player(sim)
}

@(private)
debug_mode_exit :: proc(dm: ^Debug_Mode, sim: ^Simulation) {
	dm.active = false
	dm.selection = .None
	dm.selected_crate = -1
	dm.dragging = .None
	dm.light_drag_motion = 0.0

	sim.player.position = dm.saved_player.position
	sim.player.previous_position = dm.saved_player.position
	sim.player.velocity = b3.Vec3_zero
	sim.player.yaw = dm.saved_player.yaw
	sim.player.pitch = dm.saved_player.pitch
	sim.player.grounded = false
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

	forward := b3.Vec3{-math.sin(dm.camera.yaw), 0.0, -math.cos(dm.camera.yaw)}
	right := b3.Vec3{math.cos(dm.camera.yaw), 0.0, -math.sin(dm.camera.yaw)}
	move := forward * input.move_forward + right * input.move_right
	move.y = input.move_up

	length := b3.Length(move)
	if length > 1.0 {
		move = move * (1.0 / length)
	}
	dm.camera.position += move * (DEBUG_FLY_SPEED * delta)
}
