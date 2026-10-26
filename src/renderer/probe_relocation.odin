#+vet explicit-allocators
package renderer

import "src:geometry"

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

// A probe inside a box samples the box interior. Its rays, blend, and gather
// terms are invalid. The gather needs the flag because a relocated probe sits
// on the far side of a face: the trilinear weight still favours it, and the
// depth test cuts it at a hard edge.
@(private)
point_inside_boxes :: proc(position: [3]f32, boxes: []geometry.Box) -> bool {
	for box in boxes {
		scale := 2 * box.half_extents
		if scale.x == 0 || scale.y == 0 || scale.z == 0 {
			continue
		}
		local := quat_rotate_inverse(box.rotation, position - box.center)
		local /= scale
		if abs(local.x) < 0.5 && abs(local.y) < 0.5 && abs(local.z) < 0.5 {
			return true
		}
	}
	return false
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
					valid: f32 = 1.0
					if point_inside_boxes(position, boxes) {
						valid = 0.0
					}
					index := volume.probe_offset +
						u32((z * int(volume.counts.y) + y) * int(volume.counts.x) + x)
					data[index] = {position.x, position.y, position.z, valid}
				}
			}
		}
	}
}
