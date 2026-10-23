#+vet explicit-allocators
package game

import b3 "libs:box3d"

Ledge_Path :: struct {
	forward_distance: f32,
	up_distance:      f32,
	across_scale:     f32,
	min_across:       f32,
	down_distance:    f32,
}

Ledge_Probe :: struct {
	candidate: b3.Vec3,
	ground:    Ground_Probe,
}

@(private)
probe_ledge :: proc(
	sim: ^Simulation,
	start, direction: b3.Vec3,
	path: Ledge_Path,
) -> (Ledge_Probe, bool) {
	capsule := player_capsule(sim.player.stance)
	forward_fraction := b3.World_CastMover(
		sim.world_id,
		start,
		capsule,
		direction * path.forward_distance,
		b3.DefaultQueryFilter(),
		nil,
		nil,
	)
	if forward_fraction >= 1.0 {
		return {}, false
	}

	up_fraction := b3.World_CastMover(
		sim.world_id,
		start,
		capsule,
		b3.Vec3{0.0, path.up_distance, 0.0},
		b3.DefaultQueryFilter(),
		nil,
		nil,
	)
	if up_fraction < 0.99 {
		return {}, false
	}

	lifted := start + b3.Vec3{0.0, path.up_distance * up_fraction, 0.0}
	across_distance := max(
		path.min_across,
		path.forward_distance * (1.0 - forward_fraction) + PLAYER_RADIUS * path.across_scale,
	)
	across_fraction := b3.World_CastMover(
		sim.world_id,
		lifted,
		capsule,
		direction * across_distance,
		b3.DefaultQueryFilter(),
		nil,
		nil,
	)
	if across_fraction < 0.01 {
		return {}, false
	}

	across := lifted + direction * (across_distance * across_fraction)
	down_fraction := b3.World_CastMover(
		sim.world_id,
		across,
		capsule,
		b3.Vec3{0.0, -path.down_distance, 0.0},
		b3.DefaultQueryFilter(),
		nil,
		nil,
	)
	if down_fraction >= 1.0 {
		return {}, false
	}

	candidate := across + b3.Vec3{0.0, -path.down_distance * down_fraction, 0.0}
	ground := probe_ground_at(sim, candidate, path.down_distance)
	if !ground.hit || ground.normal.y < GROUND_NORMAL_THRESHOLD {
		return {}, false
	}
	return {candidate = candidate, ground = ground}, true
}
