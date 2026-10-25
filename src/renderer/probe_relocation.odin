#+vet explicit-allocators
package renderer

import "src:geometry"

PROBE_RELOCATION_EPSILON :: 0.02

@(private)
cross3 :: proc(a, b: [3]f32) -> [3]f32 {
	return {
		a.y * b.z - a.z * b.y,
		a.z * b.x - a.x * b.z,
		a.x * b.y - a.y * b.x,
	}
}

@(private)
quat_rotate :: proc(rotation: [4]f32, value: [3]f32) -> [3]f32 {
	axis := [3]f32{rotation.x, rotation.y, rotation.z}
	uv := cross3(axis, value)
	uuv := cross3(axis, uv)
	return value + 2 * (uv * rotation.w + uuv)
}

@(private)
quat_rotate_inverse :: proc(rotation: [4]f32, value: [3]f32) -> [3]f32 {
	return quat_rotate({-rotation.x, -rotation.y, -rotation.z, rotation.w}, value)
}

// A probe inside a wall samples both sides of it. Push it out along the
// shallowest local axis before the rays run. Two passes handle a corner where
// two boxes overlap.
@(private)
relocate_out_of_boxes :: proc(position: [3]f32, boxes: []geometry.Box) -> [3]f32 {
	result := position
	for _ in 0 ..< 2 {
		for box in boxes {
			scale := 2 * box.half_extents
			if scale.x == 0 || scale.y == 0 || scale.z == 0 {
				continue
			}
			local := quat_rotate_inverse(box.rotation, result - box.center)
			local /= scale
			if abs(local.x) >= 0.5 || abs(local.y) >= 0.5 || abs(local.z) >= 0.5 {
				continue
			}

			penetration := [3]f32{
				0.5 - abs(local.x),
				0.5 - abs(local.y),
				0.5 - abs(local.z),
			}
			axis := 0
			if penetration.y < penetration[axis] {
				axis = 1
			}
			if penetration.z < penetration[axis] {
				axis = 2
			}
			sign := f32(local[axis] >= 0 ? 1 : -1)
			local[axis] = sign * (0.5 + PROBE_RELOCATION_EPSILON)
			result = box.center + quat_rotate(box.rotation, local * scale)
		}
	}
	return result
}

write_probe_positions :: proc(r: ^Renderer, boxes: []geometry.Box) {
	if r.probe.probe_count == 0 {
		return
	}
	data := cast([^][4]f32)r.probe.positions[r.frame_index].mapped
	if data == nil {
		return
	}
	for volume in r.probe.volumes {
		for z in 0 ..< int(volume.counts.z) {
			for y in 0 ..< int(volume.counts.y) {
				for x in 0 ..< int(volume.counts.x) {
					position := volume.min +
						([3]f32{f32(x), f32(y), f32(z)} + 0.5) * volume.spacing
					position = relocate_out_of_boxes(position, boxes)
					index := volume.probe_offset +
						u32((z * int(volume.counts.y) + y) * int(volume.counts.x) + x)
					data[index] = {position.x, position.y, position.z, 1.0}
				}
			}
		}
	}
}

