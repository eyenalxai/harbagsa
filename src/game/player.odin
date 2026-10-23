#+vet explicit-allocators
package game

import "core:c"
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
}

player_place :: proc(player: ^Player, position: b3.Vec3, yaw, pitch: f32) {
	player.position = position
	player.previous_position = position
	player.velocity = b3.Vec3_zero
	player.yaw = yaw
	player.pitch = pitch
	player.grounded = false
}

// One call to World_CollideMover can report several planes for the same shape.
// Keep the shape id and the origin-relative contact point with each plane so
// the controller can push dynamic bodies after the slide is resolved.
@(private)
Solver_Context :: struct {
	planes:    [MAX_COLLISION_PLANES]b3.CollisionPlane,
	points:    [MAX_COLLISION_PLANES]b3.Vec3,
	shape_ids: [MAX_COLLISION_PLANES]b3.ShapeId,
	count:     int,
}

@(private)
Ground_Probe :: struct {
	hit:      bool,
	distance: f32,
	normal:   b3.Vec3,
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
update_horizontal_velocity :: proc(player: ^Player, input: Input_Snapshot, time_step: f32) {
	move_forward := input.move_forward
	move_right := input.move_right
	input_length := math.sqrt(move_forward * move_forward + move_right * move_right)
	if input_length > 1.0 {
		move_forward /= input_length
		move_right /= input_length
		input_length = 1.0
	}

	forward := yaw_forward_horizontal(player.yaw)
	right := yaw_right(player.yaw)
	desired_direction := forward * move_forward + right * move_right
	current := b3.Vec3{player.velocity.x, 0.0, player.velocity.z}

	if player.grounded {
		if input_length > 0.0 {
			desired_velocity := desired_direction * PLAYER_WALK_SPEED
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
		if speed > PLAYER_WALK_SPEED {
			current *= PLAYER_WALK_SPEED / speed
		}
	}

	player.velocity.x = current.x
	player.velocity.z = current.z
}

// A short downward ray from just above the capsule bottom. The ray is longer
// than the contact tolerance so a landing frame still sees the floor, but only
// a hit close to the feet counts as grounded.
@(private)
probe_ground :: proc(sim: ^Simulation) -> Ground_Probe {
	origin := sim.player.position + b3.Vec3{0.0, GROUND_PROBE_LIFT, 0.0}
	translation := b3.Vec3{0.0, -GROUND_PROBE_LENGTH, 0.0}
	result := b3.World_CastRayClosest(
		sim.world_id,
		origin,
		translation,
		b3.DefaultQueryFilter(),
	)
	if !result.hit {
		return {}
	}

	return {
		hit = true,
		distance = result.fraction * GROUND_PROBE_LENGTH,
		normal = result.normal,
	}
}

@(private)
is_grounded :: proc(sim: ^Simulation, probe: Ground_Probe) -> bool {
	if !probe.hit || probe.normal.y < GROUND_NORMAL_THRESHOLD {
		return false
	}
	if sim.player.velocity.y > 0.0 {
		return false
	}

	gap := probe.distance - GROUND_PROBE_LIFT
	return gap <= GROUND_CONTACT_TOLERANCE
}

@(private)
player_capsule :: proc() -> b3.Capsule {
	return {
		center1 = {0.0, PLAYER_RADIUS, 0.0},
		center2 = {0.0, PLAYER_HEIGHT - PLAYER_RADIUS, 0.0},
		radius = PLAYER_RADIUS,
	}
}

// Move toward the target with collide-and-slide. Each iteration gathers the
// planes at the current position, solves them, then sweeps the capsule along the
// solved delta so it cannot tunnel through a wall.
@(private)
move_player :: proc(sim: ^Simulation, time_step: f32) {
	target := sim.player.position + sim.player.velocity * time_step
	contacts: Solver_Context

	for _ in 0 ..< MOVE_ITERATIONS {
		contacts = {}

		capsule := player_capsule()
		origin := sim.player.position
		b3.World_CollideMover(
			sim.world_id,
			origin,
			capsule,
			b3.DefaultQueryFilter(),
			collect_planes,
			&contacts,
		)

		target_delta := target - sim.player.position
		solved := b3.SolvePlanes(
			target_delta,
			raw_data(contacts.planes[:]),
			c.int(contacts.count),
		)

		delta := solved.delta
		fraction := b3.World_CastMover(
			sim.world_id,
			origin,
			capsule,
			delta,
			b3.DefaultQueryFilter(),
			nil,
			nil,
		)
		delta *= fraction
		sim.player.position += delta

		if b3.LengthSquared(delta) < MOVE_TOLERANCE * MOVE_TOLERANCE {
			break
		}
	}

	apply_crate_impulses(sim, &contacts)
	sim.player.velocity = b3.ClipVector(
		sim.player.velocity,
		raw_data(contacts.planes[:]),
		c.int(contacts.count),
	)
}

@(private)
collect_planes :: proc "c" (
	shape_id: b3.ShapeId,
	results: [^]b3.PlaneResult,
	result_count: c.int,
	ctx: rawptr,
) -> bool {
	collector := cast(^Solver_Context)ctx

	for index in 0 ..< int(result_count) {
		if collector.count >= MAX_COLLISION_PLANES {
			return false
		}

		result := results[index]
		if !b3.IsValidPlane(result.plane) {
			continue
		}

		collector.planes[collector.count] = {
			plane = result.plane,
			pushLimit = max(f32),
			clipVelocity = true,
		}
		collector.points[collector.count] = result.point
		collector.shape_ids[collector.count] = shape_id
		collector.count += 1
	}

	return true
}

// Push dynamic crates with the same impulse the official mover sample applies.
// The player has infinite mass, so only the crate receives the impulse.
@(private)
apply_crate_impulses :: proc(sim: ^Simulation, contacts: ^Solver_Context) {
	for index in 0 ..< contacts.count {
		body_id := b3.Shape_GetBody(contacts.shape_ids[index])
		if !b3.Body_IsValid(body_id) || b3.Body_GetType(body_id) != .dynamicBody {
			continue
		}

		point := sim.player.position + contacts.points[index]
		normal := -contacts.planes[index].plane.normal

		inverse_mass := b3.Body_GetInverseMass(body_id)
		inverse_inertia := b3.Body_GetWorldInverseRotationalInertia(body_id)
		center := b3.Body_GetWorldCenter(body_id)
		arm := point - b3.ToVec3(center)
		angular_arm := b3.Cross(arm, normal)
		angular_term := b3.Dot(angular_arm, inverse_inertia * angular_arm)
		normal_mass: f32 = 0.0
		if inverse_mass + angular_term > 0.0 {
			normal_mass = 1.0 / (inverse_mass + angular_term)
		}

		body_velocity := b3.Body_GetLinearVelocity(body_id)
		body_angular_velocity := b3.Body_GetAngularVelocity(body_id)
		point_velocity := body_velocity + b3.Cross(body_angular_velocity, arm)
		normal_velocity := b3.Dot(point_velocity - sim.player.velocity, normal)
		impulse := max(-normal_mass * normal_velocity, 0.0)
		if impulse <= 0.0 {
			continue
		}

		b3.Body_ApplyLinearImpulse(body_id, impulse * normal, point, true)
	}
}
