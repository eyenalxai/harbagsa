#+vet explicit-allocators
package game

import b3 "libs:box3d"

DEBUG_AIM_RAY_LENGTH :: 100.0

debug_aim_ray :: proc(dm: ^Debug_Mode, sim: ^Simulation) -> b3.RayResult {
	return b3.World_CastRayClosest(
		sim.world_id,
		b3.ToPos(dm.camera.position),
		debug_camera_forward(dm.camera) * DEBUG_AIM_RAY_LENGTH,
		b3.DefaultQueryFilter(),
	)
}

// A hit uses the surface point. A miss uses a point ahead of the camera, so the
// caller always has a target even when no box is under the crosshair.
debug_aim_point :: proc(dm: ^Debug_Mode, sim: ^Simulation, fallback_distance: f32) -> [3]f32 {
	hit := debug_aim_ray(dm, sim)
	if hit.hit {
		return b3.ToVec3(hit.point)
	}
	return dm.camera.position + debug_camera_forward(dm.camera) * fallback_distance
}
