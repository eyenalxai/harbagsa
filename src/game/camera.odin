#+vet explicit-allocators
package game

import "core:math"
import b3 "libs:box3d"

Camera_Pose :: struct {
	position: b3.Vec3,
	yaw:      f32,
	pitch:    f32,
}

// The orbit camera. The pivot follows the interpolated body, and a capsule cast
// down the arm stops it before the first floor, wall, or prop. The arm only
// shortens; the look direction stays the one the mouse set, so the view answers
// the hand and never drifts.
spider_camera :: proc(sim: ^Simulation, alpha: f32) -> Camera_Pose {
	player := &sim.player
	weight := clamp(alpha, 0.0, 1.0)
	feet :=
		player.previous_position + (player.position - player.previous_position) * weight
	smoothing :=
		player.previous_step_smoothing +
		(player.step_smoothing - player.previous_step_smoothing) * weight

	pivot := feet + b3.Vec3{0.0, SPIDER_BODY_HEIGHT + CAMERA_PIVOT_RISE - smoothing, 0.0}
	yaw := player.camera_yaw
	pitch := player.camera_pitch

	// A low ceiling would put the pivot inside it and the camera above the
	// shell. Drop the pivot below the ceiling and flatten a downward look, so
	// the tunnel view stays level and inside.
	ceiling := b3.World_CastRayClosest(
		sim.world_id,
		feet + b3.Vec3{0.0, 0.20, 0.0},
		b3.Vec3{0.0, CAMERA_CEILING_PROBE, 0.0},
		b3.DefaultQueryFilter(),
	)
	if ceiling.hit {
		limit := b3.ToVec3(ceiling.point).y - CAMERA_CEILING_PAD
		if pivot.y > limit {
			pivot.y = max(limit, feet.y + 0.25)
			pitch = max(pitch, 0.0)
		}
	}

	cos_pitch := math.cos(pitch)
	forward := b3.Vec3{-math.sin(yaw) * cos_pitch, math.sin(pitch), -math.cos(yaw) * cos_pitch}
	desired := pivot - forward * CAMERA_DISTANCE

	capsule := b3.Capsule {
		center1 = {0.0, -CAMERA_PROBE_HALF, 0.0},
		center2 = {0.0, CAMERA_PROBE_HALF, 0.0},
		radius  = CAMERA_PROBE_RADIUS,
	}
	fraction := b3.World_CastMover(
		sim.world_id,
		pivot,
		capsule,
		desired - pivot,
		b3.DefaultQueryFilter(),
		nil,
		nil,
	)
	distance := CAMERA_DISTANCE
	if fraction < 1.0 {
		distance = max(CAMERA_DISTANCE * f32(fraction) - CAMERA_WALL_PAD, CAMERA_MIN_DISTANCE)
	}
	distance = min(distance, CAMERA_DISTANCE)

	return {position = pivot - forward * distance, yaw = yaw, pitch = pitch}
}
