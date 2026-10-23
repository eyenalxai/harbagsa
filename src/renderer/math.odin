#+vet explicit-allocators
package renderer

import "core:math"

// Column-major 4x4 matrix. The memory layout matches GLSL `mat4`, so a Mat4
// can be uploaded directly to a uniform buffer or push constant block.
Mat4 :: [16]f32

MAT4_IDENTITY :: Mat4 {
	1, 0, 0, 0,
	0, 1, 0, 0,
	0, 0, 1, 0,
	0, 0, 0, 1,
}

// mat4_multiply returns a * b for column vectors.
mat4_multiply :: proc(a, b: Mat4) -> (m: Mat4) {
	for column in 0 ..< 4 {
		for row in 0 ..< 4 {
			value: f32
			for k in 0 ..< 4 {
				value += a[k * 4 + row] * b[column * 4 + k]
			}
			m[column * 4 + row] = value
		}
	}
	return
}

mat4_translation :: proc(translation: [3]f32) -> Mat4 {
	m := MAT4_IDENTITY
	m[12] = translation.x
	m[13] = translation.y
	m[14] = translation.z
	return m
}

mat4_scale :: proc(scale: [3]f32) -> Mat4 {
	m := MAT4_IDENTITY
	m[0] = scale.x
	m[5] = scale.y
	m[10] = scale.z
	return m
}

// mat4_perspective builds a right-handed projection with a Vulkan clip space:
// depth in 0..1 and the Y axis pointing down. The Y flip makes world +Y render
// at the top of a viewport with positive height.
mat4_perspective :: proc(fov_y, aspect, near, far: f32) -> (m: Mat4) {
	tan_half_fov := math.tan(fov_y * 0.5)
	m[0] = 1 / (aspect * tan_half_fov)
	m[5] = -1 / tan_half_fov
	m[10] = far / (near - far)
	m[11] = -1
	m[14] = near * far / (near - far)
	return
}

// mat4_look_at builds a right-handed view matrix.
mat4_look_at :: proc(eye, target, up: [3]f32) -> (m: Mat4) {
	forward := vec3_normalize(target - eye)
	side := vec3_normalize(vec3_cross(forward, up))
	upward := vec3_cross(side, forward)

	m[0] = side.x
	m[4] = side.y
	m[8] = side.z
	m[12] = -vec3_dot(side, eye)

	m[1] = upward.x
	m[5] = upward.y
	m[9] = upward.z
	m[13] = -vec3_dot(upward, eye)

	m[2] = -forward.x
	m[6] = -forward.y
	m[10] = -forward.z
	m[14] = vec3_dot(forward, eye)

	m[3] = 0
	m[7] = 0
	m[11] = 0
	m[15] = 1
	return
}

vec3_dot :: proc(a, b: [3]f32) -> f32 {
	return a.x * b.x + a.y * b.y + a.z * b.z
}

vec3_cross :: proc(a, b: [3]f32) -> [3]f32 {
	return {
		a.y * b.z - a.z * b.y,
		a.z * b.x - a.x * b.z,
		a.x * b.y - a.y * b.x,
	}
}

vec3_normalize :: proc(v: [3]f32) -> [3]f32 {
	length := math.sqrt(vec3_dot(v, v))
	if length == 0 {
		return {}
	}
	return v / length
}
