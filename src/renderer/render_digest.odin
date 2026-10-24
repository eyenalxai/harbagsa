#+vet explicit-allocators
package renderer

import "src:digest"
import "src:geometry"

View_Flag :: enum {
	HUD,
	Menu,
	Debug_Draw,
	Capture_Hint,
	Perf,
}

View_Flags :: bit_set[View_Flag]

// The digest names the effective render inputs, not the game state. Two frames
// with the same digest draw the same scene, so a measurement can assert the
// inputs before it compares pixels.
Render_Digest_Input :: struct {
	camera:               Camera,
	light_direction:      [3]f32,
	sun_angular_diameter: f32,
	boxes:                []geometry.Box,
	jitter:               [2]f32,
	shadow_phase:         u32,
	sky:                  bool,
	ao:                   bool,
	view_flags:           View_Flags,
}

render_digest :: proc(input: Render_Digest_Input) -> digest.FNV {
	hash := digest.fnv()
	digest.write_f32(&hash, input.camera.position.x)
	digest.write_f32(&hash, input.camera.position.y)
	digest.write_f32(&hash, input.camera.position.z)
	digest.write_f32(&hash, input.camera.yaw)
	digest.write_f32(&hash, input.camera.pitch)
	digest.write_f32(&hash, input.camera.fov_x)
	digest.write_f32(&hash, input.light_direction.x)
	digest.write_f32(&hash, input.light_direction.y)
	digest.write_f32(&hash, input.light_direction.z)
	digest.write_f32(&hash, input.sun_angular_diameter)
	digest.write_u64(&hash, u64(len(input.boxes)))
	for box in input.boxes {
		digest.write_f32(&hash, box.center.x)
		digest.write_f32(&hash, box.center.y)
		digest.write_f32(&hash, box.center.z)
		digest.write_f32(&hash, box.half_extents.x)
		digest.write_f32(&hash, box.half_extents.y)
		digest.write_f32(&hash, box.half_extents.z)
		digest.write_f32(&hash, box.rotation.x)
		digest.write_f32(&hash, box.rotation.y)
		digest.write_f32(&hash, box.rotation.z)
		digest.write_f32(&hash, box.rotation.w)
		digest.write_f32(&hash, box.color.x)
		digest.write_f32(&hash, box.color.y)
		digest.write_f32(&hash, box.color.z)
		digest.write_f32(&hash, box.color.w)
		digest.write_bool(&hash, box.visual_only)
	}
	digest.write_f32(&hash, input.jitter.x)
	digest.write_f32(&hash, input.jitter.y)
	digest.write_u32(&hash, input.shadow_phase)
	digest.write_bool(&hash, input.sky)
	digest.write_bool(&hash, input.ao)
	digest.write_u32(&hash, u32(transmute(u8)input.view_flags))
	return hash
}
