#+vet explicit-allocators
package game

import "core:math"
import b3 "libs:box3d"

// Plain player state. Position is the feet, not the capsule center. The legs are
// presented from the feet, and each one holds a world foot target.
Player :: struct {
	position:               b3.Vec3,
	previous_position:      b3.Vec3,
	velocity:               b3.Vec3,
	yaw:                    f32,
	previous_yaw:           f32,
	camera_yaw:             f32,
	camera_pitch:           f32,
	grounded:               bool,
	grounded_last_step:     bool,
	ground_normal:          b3.Vec3,
	gait:                   Gait,
	sprint_toggled:         bool,
	sprint_wanted:          bool,
	step_smoothing:         f32,
	previous_step_smoothing: f32,
	step_grace:             f32,
	on_steep_slope:         bool,
	steep_normal:           b3.Vec3,
	jump_buffer:            f32,
	coyote:                 f32,
	air_cap:                f32,
	legs:                   [LEG_COUNT]Leg,
	next_gait_group:        u8,
}

// Places the player without carrying motion or a leg pose into the new position.
player_place :: proc(player: ^Player, position: b3.Vec3, yaw, pitch: f32) {
	player.position = position
	player.previous_position = position
	player.velocity = b3.Vec3_zero
	player.yaw = yaw
	player.previous_yaw = yaw
	player.camera_yaw = yaw
	player.camera_pitch = pitch
	player.grounded = false
	player.grounded_last_step = false
	player.ground_normal = {0.0, 1.0, 0.0}
	player.step_smoothing = 0.0
	player.previous_step_smoothing = 0.0
	player.step_grace = 0.0
	player.jump_buffer = 0.0
	player.coyote = 0.0
	player.air_cap = PLAYER_WALK_SPEED
	player.on_steep_slope = false
	player.steep_normal = {}
	player.legs = {}
	player.next_gait_group = 0
}

@(private)
update_look :: proc(player: ^Player, look_delta: b3.Vec2) {
	player.camera_yaw = b3.UnwindAngle(
		player.camera_yaw - look_delta.x * YAW_SENSITIVITY,
	)
	player.camera_pitch = clamp(
		player.camera_pitch - look_delta.y * PITCH_SENSITIVITY,
		CAMERA_PITCH_MIN,
		CAMERA_PITCH_MAX,
	)
}

// Apply a relative mouse delta to the orbit camera. The main loop calls this
// once per frame, outside the fixed step, so look still works when no step runs.
simulation_look :: proc(sim: ^Simulation, look_delta: b3.Vec2) {
	update_look(&sim.player, look_delta)
}

@(private)
movement_direction :: proc(player: ^Player, input: Input_Snapshot) -> b3.Vec3 {
	direction :=
		yaw_forward_horizontal(player.camera_yaw) * input.move_forward +
		yaw_right(player.camera_yaw) * input.move_right
	length := b3.Length(direction)
	if length > 1.0 {
		direction /= length
	}
	return direction
}

// The wish velocity lies in the ground plane. Its length is the gait speed, so
// a straight climb trades horizontal speed for height instead of speeding up.
ground_velocity :: proc(direction, normal: b3.Vec3, speed: f32) -> b3.Vec3 {
	if speed <= 0.0 {
		return b3.Vec3_zero
	}
	projected := direction - normal * b3.Dot(direction, normal)
	length := b3.Length(projected)
	if length <= 0.0001 {
		return b3.Vec3_zero
	}
	return projected * (speed / length)
}

@(private)
update_horizontal_velocity :: proc(player: ^Player, input: Input_Snapshot, time_step: f32) {
	desired_direction := movement_direction(player, input)
	input_length := b3.Length(desired_direction)
	if player.on_steep_slope && b3.Dot(desired_direction, player.steep_normal) < 0.0 {
		desired_direction = b3.Vec3_zero
		input_length = 0.0
	}

	if player.grounded {
		current := player.velocity
		if input_length > 0.0 {
			desired_velocity := ground_velocity(
				desired_direction,
				player.ground_normal,
				gait_speed(player.gait),
			)
			change := desired_velocity - current
			change_length := b3.Length(change)
			max_change := PLAYER_GROUND_ACCELERATION * time_step
			if change_length <= max_change {
				current = desired_velocity
			} else if change_length > 0.0 {
				current += change * (max_change / change_length)
			}
		} else {
			speed := b3.Length(current)
			max_change := PLAYER_GROUND_DECELERATION * time_step
			if speed <= max_change {
				current = b3.Vec3_zero
			} else {
				current *= (speed - max_change) / speed
			}
		}
		player.velocity = current
		return
	}

	current := b3.Vec3{player.velocity.x, 0.0, player.velocity.z}
	if input_length > 0.0 {
		direction_length := b3.Length(desired_direction)
		if direction_length > 0.0 {
			current += desired_direction * (PLAYER_AIR_CONTROL * time_step / direction_length)
		}

		// Steering may turn the velocity, but it must not exceed the air cap.
		speed := b3.Length(current)
		if speed > player.air_cap {
			current *= player.air_cap / speed
		}
	}

	player.velocity.x = current.x
	player.velocity.z = current.z
}

@(private)
update_sprint_input :: proc(player: ^Player, input: Input_Snapshot, mode: Input_Mode) {
	if mode == .Hold {
		player.sprint_wanted = input.sprint_held
		return
	}
	if input.sprint_pressed {
		player.sprint_toggled = !player.sprint_toggled
	}
	player.sprint_wanted = player.sprint_toggled
}

// The body faces the direction of travel. Look only moves the camera, so a
// spider can strafe while it keeps its heading. A slow walk below the minimum
// speed keeps the last heading instead of spinning in place.
@(private)
update_body_yaw :: proc(player: ^Player, time_step: f32) {
	speed := horizontal_speed(player.velocity)
	if speed < SPIDER_TURN_MIN_SPEED {
		return
	}
	desired := math.atan2(-player.velocity.x, -player.velocity.z)
	delta := b3.UnwindAngle(desired - player.yaw)
	alpha := 1.0 - math.exp(-SPIDER_TURN_RATE * time_step)
	player.yaw = b3.UnwindAngle(player.yaw + delta * alpha)
}
