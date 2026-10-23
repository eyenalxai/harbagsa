#+vet explicit-allocators
package game

import "core:math"
import b3 "libs:box3d"

// Plain player state. Position is the feet, not the capsule center.
Player :: struct {
	position:          b3.Vec3,
	previous_position: b3.Vec3,
	velocity:          b3.Vec3,
	yaw:               f32,
	pitch:             f32,
	grounded:          bool,
	stance:            Stance,
	gait:              Gait,
	movement_state:    Movement_State,
	crouch_engaged:    bool,
	prone_engaged:     bool,
	sprint_toggled:    bool,
	sprint_wanted:  bool,
	eye_height:        f32,
	previous_eye_height: f32,
	on_steep_slope:    bool,
	steep_normal:      b3.Vec3,
	jump_buffer:       f32,
	coyote:            f32,
	air_cap:           f32,
	slide_direction:    b3.Vec3,
	slide_speed:       f32,
	slide_elapsed:     f32,
	mantle:            Mantle_State,
}

@(private)
update_look :: proc(player: ^Player, look_delta: b3.Vec2) {
	player.yaw = b3.UnwindAngle(player.yaw - look_delta.x * YAW_SENSITIVITY)
	player.pitch = clamp(
		player.pitch - look_delta.y * PITCH_SENSITIVITY,
		-PITCH_LIMIT,
		PITCH_LIMIT,
	)
}

// Apply a relative mouse delta to the player's view. The main loop calls this
// once per frame, outside the fixed step, so look still works when no step runs.
simulation_look :: proc(sim: ^Simulation, look_delta: b3.Vec2) {
	update_look(&sim.player, look_delta)
}

@(private)
movement_direction :: proc(player: ^Player, input: Input_Snapshot) -> b3.Vec3 {
	forward := b3.Vec3{-math.sin(player.yaw), 0.0, -math.cos(player.yaw)}
	right := b3.Vec3{math.cos(player.yaw), 0.0, -math.sin(player.yaw)}
	direction := forward * input.move_forward + right * input.move_right
	length := b3.Length(direction)
	if length > 1.0 {
		direction /= length
	}
	return direction
}

@(private)
update_horizontal_velocity :: proc(player: ^Player, input: Input_Snapshot, time_step: f32) {
	if player.movement_state != .None {
		return
	}
	desired_direction := movement_direction(player, input)
	input_length := b3.Length(desired_direction)
	if player.on_steep_slope && b3.Dot(desired_direction, player.steep_normal) < 0.0 {
		desired_direction = b3.Vec3_zero
		input_length = 0.0
	}
	current := b3.Vec3{player.velocity.x, 0.0, player.velocity.z}

	if player.grounded {
		if input_length > 0.0 {
			desired_velocity := desired_direction * stance_speed(player.stance, player.gait)
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
	} else if input_length > 0.0 {
		direction_length := b3.Length(desired_direction)
		if direction_length > 0.0 {
			current += desired_direction * (PLAYER_AIR_CONTROL * time_step / direction_length)
		}

		// Steering may turn the velocity, but it must not add speed.
		speed := b3.Length(current)
		if speed > player.air_cap {
			current *= player.air_cap / speed
		}
	}

	player.velocity.x = current.x
	player.velocity.z = current.z
}

