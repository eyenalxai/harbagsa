#+vet explicit-allocators
package game

import "core:c"
import b3 "libs:box3d"

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
	shape_id: b3.ShapeId,
}

@(private)
collide_mover :: proc(sim: ^Simulation, point: b3.Vec3, capsule: b3.Capsule) -> Solver_Context {
	contacts: Solver_Context
	b3.World_CollideMover(
		sim.world_id,
		point,
		capsule,
		b3.DefaultQueryFilter(),
		collect_planes,
		&contacts,
	)
	return contacts
}

// A short downward capsule cast finds the surface under the feet. The cast end
// is collided to recover the surface normal. A capsule bottom rests above a
// slope by its radius, so callers compare the gap to the slope clearance.
@(private)
probe_ground_at :: proc(sim: ^Simulation, feet: b3.Vec3, length: f32) -> Ground_Probe {
	capsule := player_capsule(sim.player.stance)
	origin := feet + b3.Vec3{0.0, GROUND_PROBE_LIFT, 0.0}
	fraction := b3.World_CastMover(
		sim.world_id,
		origin,
		capsule,
		b3.Vec3{0.0, -length, 0.0},
		b3.DefaultQueryFilter(),
		nil,
		nil,
	)
	if fraction >= 1.0 {
		return {}
	}

	end := origin + b3.Vec3{0.0, -length * fraction, 0.0}
	contacts := collide_mover(sim, end, capsule)

	best: Ground_Probe
	for index in 0 ..< contacts.count {
		normal := contacts.planes[index].plane.normal
		if normal.y < GROUND_NORMAL_THRESHOLD {
			continue
		}
		if !best.hit || normal.y > best.normal.y {
			best = {
				hit = true,
				normal = normal,
				shape_id = contacts.shape_ids[index],
			}
		}
	}
	if !best.hit {
		return {}
	}

	best.distance = max(length * fraction - GROUND_PROBE_LIFT, 0.0)
	return best
}

@(private)
probe_ground :: proc(sim: ^Simulation, length: f32 = GROUND_PROBE_LENGTH) -> Ground_Probe {
	return probe_ground_at(sim, sim.player.position, length)
}

// A capsule bottom rests above a slope by the radius times (1 / normal.y - 1).
// The clearance is not a gap in the contact; it is the capsule geometry.
@(private)
slope_clearance :: proc(normal: b3.Vec3) -> f32 {
	return PLAYER_RADIUS * (1.0 / normal.y - 1.0)
}

@(private)
is_grounded :: proc(sim: ^Simulation, probe: Ground_Probe) -> bool {
	if !probe.hit || probe.normal.y < GROUND_NORMAL_THRESHOLD {
		return false
	}
	return probe.distance <= slope_clearance(probe.normal) + GROUND_CONTACT_TOLERANCE
}

@(private)
player_capsule :: proc(stance: Stance) -> b3.Capsule {
	return {
		center1 = {0.0, PLAYER_RADIUS, 0.0},
		center2 = {0.0, stance_height(stance) - PLAYER_RADIUS, 0.0},
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
		capsule := player_capsule(sim.player.stance)
		origin := sim.player.position
		contacts = collide_mover(sim, origin, capsule)

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

	sim.player.on_steep_slope = false
	for index in 0 ..< contacts.count {
		normal := contacts.planes[index].plane.normal
		if normal.y <= 0.1 || normal.y >= GROUND_NORMAL_THRESHOLD {
			continue
		}
		if b3.Dot(sim.player.velocity, normal) < 0.0 {
			sim.player.on_steep_slope = true
			sim.player.steep_normal = normal
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
