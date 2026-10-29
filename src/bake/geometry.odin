#+vet explicit-allocators
package bake

import "core:math"

import "src:geometry"

DVec3 :: [3]f64
DQuat :: [4]f64

FACE_COUNT :: 6

// The face order is +X, -X, +Y, -Y, +Z, -Z. `u` and `v` are unit-local axes:
// s = dot(local, u) + 0.5 and t = dot(local, v) + 0.5, with local in
// [-0.5, 0.5] as in the cube vertex buffer. The shader mirror must use the
// same table.
Face_Basis :: struct {
	normal: [3]i8,
	u:      [3]i8,
	v:      [3]i8,
}

FACE_BASES := [FACE_COUNT]Face_Basis {
	{{1, 0, 0}, {0, 0, 1}, {0, -1, 0}},
	{{-1, 0, 0}, {0, 0, -1}, {0, -1, 0}},
	{{0, 1, 0}, {1, 0, 0}, {0, 0, -1}},
	{{0, -1, 0}, {1, 0, 0}, {0, 0, 1}},
	{{0, 0, 1}, {1, 0, 0}, {0, 1, 0}},
	{{0, 0, -1}, {-1, 0, 0}, {0, 1, 0}},
}

dv :: proc(value: [3]f32) -> DVec3 {
	return {f64(value.x), f64(value.y), f64(value.z)}
}

dv_axis :: proc(axis: int) -> DVec3 {
	return {axis == 0 ? 1.0 : 0.0, axis == 1 ? 1.0 : 0.0, axis == 2 ? 1.0 : 0.0}
}

dv_add :: #force_inline proc(a, b: DVec3) -> DVec3 {
	return {a.x + b.x, a.y + b.y, a.z + b.z}
}

dv_sub :: #force_inline proc(a, b: DVec3) -> DVec3 {
	return {a.x - b.x, a.y - b.y, a.z - b.z}
}

dv_mul :: #force_inline proc(a: DVec3, scale: f64) -> DVec3 {
	return {a.x * scale, a.y * scale, a.z * scale}
}

dv_dot :: #force_inline proc(a, b: DVec3) -> f64 {
	return a.x * b.x + a.y * b.y + a.z * b.z
}

dv_cross :: #force_inline proc(a, b: DVec3) -> DVec3 {
	return {
		a.y * b.z - a.z * b.y,
		a.z * b.x - a.x * b.z,
		a.x * b.y - a.y * b.x,
	}
}

dv_length :: #force_inline proc(value: DVec3) -> f64 {
	return math.sqrt(dv_dot(value, value))
}

dv_normalize :: proc(value: DVec3) -> DVec3 {
	length := dv_length(value)
	if length <= 1e-12 {
		return {0, 0, 0}
	}
	return dv_mul(value, 1.0 / length)
}

quat_normalize :: proc(value: [4]f32) -> (DQuat, bool) {
	quaternion := DQuat{f64(value.x), f64(value.y), f64(value.z), f64(value.w)}
	length := math.sqrt(
		quaternion.x * quaternion.x +
		quaternion.y * quaternion.y +
		quaternion.z * quaternion.z +
		quaternion.w * quaternion.w,
	)
	if length <= 1e-9 {
		return {}, false
	}
	scale := 1.0 / length
	return {
		quaternion.x * scale,
		quaternion.y * scale,
		quaternion.z * scale,
		quaternion.w * scale,
	}, true
}

quat_rotate :: #force_inline proc(q: DQuat, value: DVec3) -> DVec3 {
	if q.x == 0 && q.y == 0 && q.z == 0 && q.w == 1 {
		return value
	}
	axis := DVec3{q.x, q.y, q.z}
	uv := dv_cross(axis, value)
	uuv := dv_cross(axis, uv)
	return dv_add(value, dv_mul(dv_add(dv_mul(uv, q.w), uuv), 2.0))
}

quat_inverse_rotate :: #force_inline proc(q: DQuat, value: DVec3) -> DVec3 {
	return quat_rotate({-q.x, -q.y, -q.z, q.w}, value)
}

// The epsilon makes a point on a shared face belong to neither box.
box_contains_rotation :: proc(
	box: geometry.Box,
	rotation: DQuat,
	point: DVec3,
	epsilon: f64,
) -> bool {
	for half in box.half_extents {
		if f64(half) <= epsilon {
			return false
		}
	}
	local := quat_inverse_rotate(rotation, dv_sub(point, dv(box.center)))
	return(
		math.abs(local.x) < f64(box.half_extents.x) - epsilon &&
		math.abs(local.y) < f64(box.half_extents.y) - epsilon &&
		math.abs(local.z) < f64(box.half_extents.z) - epsilon \
	)
}

box_world_bounds :: proc(box: geometry.Box) -> (lower, upper: DVec3) {
	rotation, ok := quat_normalize(box.rotation)
	if !ok {
		return {}, {}
	}
	half := dv(box.half_extents)
	center := dv(box.center)
	lower = center
	upper = center
	for corner_index in 0 ..< 8 {
		local := DVec3 {
			corner_index & 1 == 0 ? -half.x : half.x,
			corner_index & 2 == 0 ? -half.y : half.y,
			corner_index & 4 == 0 ? -half.z : half.z,
		}
		corner := dv_add(center, quat_rotate(rotation, local))
		lower.x = min(lower.x, corner.x)
		lower.y = min(lower.y, corner.y)
		lower.z = min(lower.z, corner.z)
		upper.x = max(upper.x, corner.x)
		upper.y = max(upper.y, corner.y)
		upper.z = max(upper.z, corner.z)
	}
	return
}

face_axis :: proc(value: [3]i8) -> int {
	if value.x != 0 {
		return 0
	}
	if value.y != 0 {
		return 1
	}
	return 2
}

face_size :: proc(box: geometry.Box, face: int) -> (width, height: f64) {
	basis := FACE_BASES[face]
	half := [3]f32{box.half_extents.x, box.half_extents.y, box.half_extents.z}
	return 2.0 * f64(half[face_axis(basis.u)]), 2.0 * f64(half[face_axis(basis.v)])
}

face_point :: proc(box: geometry.Box, face: int, s, t: f64) -> (position, normal: DVec3) {
	rotation, ok := quat_normalize(box.rotation)
	if !ok {
		return {}, {}
	}
	basis := FACE_BASES[face]
	half := [3]f32{box.half_extents.x, box.half_extents.y, box.half_extents.z}
	normal_index := face_axis(basis.normal)
	local := dv_mul(
		{f64(basis.normal.x), f64(basis.normal.y), f64(basis.normal.z)},
		f64(half[normal_index]),
	)
	u_value := (s - 0.5) * 2.0 * f64(half[face_axis(basis.u)])
	v_value := (t - 0.5) * 2.0 * f64(half[face_axis(basis.v)])
	local = dv_add(local, dv_mul({f64(basis.u.x), f64(basis.u.y), f64(basis.u.z)}, u_value))
	local = dv_add(local, dv_mul({f64(basis.v.x), f64(basis.v.y), f64(basis.v.z)}, v_value))
	position = dv_add(dv(box.center), quat_rotate(rotation, local))
	normal = quat_rotate(
		rotation,
		{f64(basis.normal.x), f64(basis.normal.y), f64(basis.normal.z)},
	)
	return
}

// SplitMix64: fixed, portable, and independent of process or thread state.
hash64 :: proc(value: u64) -> u64 {
	z := value + 0x9e3779b97f4a7c15
	z = (z ~ (z >> 30)) * 0xbf58476d1ce4e5b9
	z = (z ~ (z >> 27)) * 0x94d049bb133111eb
	return z ~ (z >> 31)
}

seed_for :: proc(kind, index: u64) -> u64 {
	return hash64(SEED ~ (kind << 56) ~ index)
}

unit_from_hash :: proc(value: u64) -> f64 {
	return f64(value >> 11) * (1.0 / f64(u64(1) << 53))
}
