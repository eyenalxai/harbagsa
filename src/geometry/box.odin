#+vet explicit-allocators
#+vet !unused-procedures // the frame package calls box_between; test builds do not
package geometry

import "core:math"

IDENTITY_ROTATION :: [4]f32{0, 0, 0, 1}

Box :: struct {
	center:       [3]f32,
	half_extents: [3]f32,
	color:        [4]f32,
	rotation:     [4]f32,
	// A non-zero strength makes the box a lamp: it glows and it does not block
	// its own point light.
	emissive:     f32,
	visual_only:  bool,
}

// A box that spans two points, with the segment along local +X. Joints and limb
// segments use this so the two-bone chain reads as solid geometry.
box_between :: proc(
	from, to: [3]f32,
	half_thickness: f32,
	color: [4]f32,
) -> Box {
	delta := to - from
	length := math.sqrt(delta.x * delta.x + delta.y * delta.y + delta.z * delta.z)
	if length <= 0.00001 {
		return {
			center = from,
			half_extents = {half_thickness, half_thickness, half_thickness},
			color = color,
			rotation = IDENTITY_ROTATION,
		}
	}
	direction := delta / length
	// Quaternion that maps +X to the segment direction.
	axis := [3]f32{0.0, -direction.z, direction.y}
	c := direction.x
	axis_length := math.sqrt(axis.x * axis.x + axis.y * axis.y + axis.z * axis.z)
	rotation: [4]f32
	if axis_length <= 0.00001 {
		rotation = c > 0.0 ? IDENTITY_ROTATION : [4]f32{0.0, 1.0, 0.0, 0.0}
	} else {
		scale := 1.0 / axis_length
		rotation = {axis.x * scale, axis.y * scale, axis.z * scale, 1.0 + c}
		q_length := rotation.x * rotation.x +
			rotation.y * rotation.y +
			rotation.z * rotation.z +
			rotation.w * rotation.w
		if q_length > 0.00001 {
			q_scale := 1.0 / math.sqrt(q_length)
			rotation = {
				rotation.x * q_scale,
				rotation.y * q_scale,
				rotation.z * q_scale,
				rotation.w * q_scale,
			}
		}
	}
	return {
		center = (from + to) * 0.5,
		half_extents = {length * 0.5, half_thickness, half_thickness},
		color = color,
		rotation = rotation,
	}
}
