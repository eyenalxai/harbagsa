#+vet explicit-allocators
package game

import b3 "libs:box3d"

LOCAL_BOX_CORNERS :: [8][3]f32 {
	{-1.0, -1.0, -1.0},
	{1.0, -1.0, -1.0},
	{1.0, 1.0, -1.0},
	{-1.0, 1.0, -1.0},
	{-1.0, -1.0, 1.0},
	{1.0, -1.0, 1.0},
	{1.0, 1.0, 1.0},
	{-1.0, 1.0, 1.0},
}

oriented_box_corners :: proc(
	center, half_extents: [3]f32,
	rotation: b3.Quat,
) -> [8][3]f32 {
	corners: [8][3]f32
	for corner, index in LOCAL_BOX_CORNERS {
		local := b3.Vec3 {
			corner.x * half_extents.x,
			corner.y * half_extents.y,
			corner.z * half_extents.z,
		}
		corners[index] = center + rotate_vector(rotation, local)
	}
	return corners
}

// The vendored b3.RotateVector binding multiplies the wrong term, so the game
// keeps its own copy of the standard formula.
@(private)
rotate_vector :: proc(q: b3.Quat, v: b3.Vec3) -> b3.Vec3 {
	axis := b3.Vec3{q.x, q.y, q.z}
	return v + 2.0 * b3.Cross(axis, b3.Cross(axis, v) + v * q.w)
}

oriented_aabb_half_extents :: proc(half_extents: [3]f32, rotation: b3.Quat) -> [3]f32 {
	corners := oriented_box_corners({}, half_extents, rotation)
	lower := corners[0]
	upper := corners[0]
	for corner in corners {
		lower.x = min(lower.x, corner.x)
		lower.y = min(lower.y, corner.y)
		lower.z = min(lower.z, corner.z)
		upper.x = max(upper.x, corner.x)
		upper.y = max(upper.y, corner.y)
		upper.z = max(upper.z, corner.z)
	}
	return (upper - lower) * 0.5
}
