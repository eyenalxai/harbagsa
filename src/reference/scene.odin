#+vet explicit-allocators
package reference

import "core:math"
import "core:math/linalg"

import "src:geometry"

// A path-traced reference for the renderer's diffuse term. It mirrors the
// renderer's shading scale: a point light is an irradiance, a box emits
// `color.rgb * emissive`, and a diffuse surface returns
// `albedo * (direct + indirect)` with no 1/pi. The estimator is documented in
// docs/evidence/ddgi-reference.md.

RAY_BIAS :: f32(0.001)
RAY_FAR :: f32(1000.0)
CAMERA_UP :: [3]f32{0, 1, 0}

Light :: struct {
	position:  [3]f32,
	color:     [3]f32,
	intensity: f32,
	range:     f32,
}

Camera :: struct {
	position: [3]f32,
	yaw:      f32,
	pitch:    f32,
	fov_x:    f32,
}

Scene :: struct {
	boxes:  []geometry.Box,
	lights: []Light,
	camera: Camera,
}

// A hit carries the surface the path or the camera reached. `box` is the index
// in `Scene.boxes`; the comparison uses it to prove the CPU and the GPU shaded
// the same surface.
Hit :: struct {
	hit:      bool,
	distance: f32,
	box:      int,
	position: [3]f32,
	normal:   [3]f32,
	albedo:   [3]f32,
	emission: [3]f32,
}

Ray_Box :: struct {
	distance: f32,
	axis:     int,
	sign:     f32,
}

// The vendored Box3D RotateVector binding multiplies the wrong term, so this
// package keeps the standard quaternion formula.
quat_rotate :: proc(rotation: [4]f32, vector: [3]f32) -> [3]f32 {
	axis := [3]f32{rotation.x, rotation.y, rotation.z}
	return vector +
	       2.0 * linalg.vector_cross3(axis, linalg.vector_cross3(axis, vector) + vector * rotation.w)
}

// One slab test in the box's local frame. A hit whose entry distance is at or
// behind `t_min` is ignored, so a ray that leaves the surface it starts on does
// not count that surface as an occluder.
ray_box :: proc(box: geometry.Box, origin, direction: [3]f32, t_min: f32) -> (Ray_Box, bool) {
	inverse := [4]f32{-box.rotation.x, -box.rotation.y, -box.rotation.z, box.rotation.w}
	local_origin := quat_rotate(inverse, origin - box.center)
	local_direction := quat_rotate(inverse, direction)
	near: f32 = -math.F32_MAX
	far: f32 = math.F32_MAX
	axis := 0
	sign: f32 = 1

	for index in 0 ..< 3 {
		offset := local_origin[index]
		step := local_direction[index]
		half := box.half_extents[index]
		if abs(step) < 1e-9 {
			if offset < -half || offset > half {
				return {}, false
			}
			continue
		}
		inverse_step := 1.0 / step
		entry := (-half - offset) * inverse_step
		exit := (half - offset) * inverse_step
		entry_sign: f32 = -1.0
		if entry > exit {
			entry, exit = exit, entry
			entry_sign = 1.0
		}
		if entry > near {
			near = entry
			axis = index
			sign = entry_sign
		}
		if exit < far {
			far = exit
		}
		if near > far {
			return {}, false
		}
	}
	if near <= t_min || far <= t_min {
		return {}, false
	}
	return {distance = near, axis = axis, sign = sign}, true
}

// Visual-only boxes are in the renderer's acceleration structure, so the
// reference keeps them too. Every box is an occluder and a diffuse surface.
intersect :: proc(scene: Scene, origin, direction: [3]f32) -> Hit {
	result := Hit{distance = math.F32_MAX}
	for box, index in scene.boxes {
		box_hit, ok := ray_box(box, origin, direction, RAY_BIAS)
		if !ok || box_hit.distance >= result.distance {
			continue
		}
		local_normal := [3]f32{}
		local_normal[box_hit.axis] = box_hit.sign
		result = {
			hit = true,
			distance = box_hit.distance,
			box = index,
			position = origin + direction * box_hit.distance,
			normal = linalg.vector_normalize0(quat_rotate(box.rotation, local_normal)),
			albedo = {box.color.x, box.color.y, box.color.z},
			emission = {box.color.x, box.color.y, box.color.z} * box.emissive,
		}
	}
	return result
}

// The renderer's point-light shadow mask (0x02) does not match a lamp instance
// (0x01), so a lamp never blocks its own point light.
occluded :: proc(
	scene: Scene,
	origin, direction: [3]f32,
	skip_lamps: bool,
	max_distance: f32,
) -> bool {
	for box in scene.boxes {
		if skip_lamps && box.emissive > 0 {
			continue
		}
		box_hit, ok := ray_box(box, origin, direction, RAY_BIAS)
		if ok && box_hit.distance < max_distance {
			return true
		}
	}
	return false
}

// The primary ray mirrors camera.vert, camera.glsl, and mat4_perspective: the
// projection flips Y, so pixel y grows along world "down".
camera_ray :: proc(camera: Camera, width, height: u32, x, y: int) -> [3]f32 {
	cos_pitch := math.cos(camera.pitch)
	forward := [3]f32{
		-math.sin(camera.yaw) * cos_pitch,
		math.sin(camera.pitch),
		-math.cos(camera.yaw) * cos_pitch,
	}
	side := linalg.vector_normalize0(linalg.vector_cross3(forward, CAMERA_UP))
	upward := linalg.vector_cross3(side, forward)
	tan_x := math.tan(camera.fov_x * 0.5)
	aspect := f32(width) / f32(height)
	tan_y := tan_x / aspect
	ndc_x := 2.0 * (f32(x) + 0.5) / f32(width) - 1.0
	ndc_y := 2.0 * (f32(y) + 0.5) / f32(height) - 1.0
	return linalg.vector_normalize0(
		forward + side * (ndc_x * tan_x) + upward * (-ndc_y * tan_y),
	)
}
