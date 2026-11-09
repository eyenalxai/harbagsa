#+vet explicit-allocators
package game

import b3 "libs:box3d"

DEBUG_AIM_RAY_LENGTH :: 100.0

debug_aim_ray :: proc(sim: ^Simulation, camera: Debug_Camera) -> b3.RayResult {
	if !simulation_is_valid(sim) {
		return {}
	}
	return b3.World_CastRayClosest(
		sim.world_id,
		b3.ToPos(camera.position),
		debug_camera_forward(camera) * DEBUG_AIM_RAY_LENGTH,
		b3.DefaultQueryFilter(),
	)
}

// A hit uses the surface point. A miss uses a point ahead of the camera, so the
// caller always has a target even when no box is under the aim.
debug_aim_point :: proc(sim: ^Simulation, camera: Debug_Camera, fallback_distance: f32) -> [3]f32 {
	hit := debug_aim_ray(sim, camera)
	if hit.hit {
		return b3.ToVec3(hit.point)
	}
	return camera.position + debug_camera_forward(camera) * fallback_distance
}
