#+vet explicit-allocators
#+vet !unused-procedures // the tests read the table
package renderer

import "src:digest"

Render_Digest_Field :: struct {
	name:   string,
	hashed: bool,
	write:  proc(hash: ^digest.FNV, input: Render_Input),
	reason: string,
}

// The digest names the effective render inputs, not the game state. Two frames
// with the same digest draw the same scene before the resolve. `hud` and
// `debug_lines` are unhashed on purpose: they draw after the resolve. The view
// flags cover the HUD and the F1 world draw, but editor lines follow F2 and the
// active tool, so `renderer.debug_vertices` is the count to check.
RENDER_DIGEST_FIELDS := [?]Render_Digest_Field {
	{"width", true, write_width, ""},
	{"height", true, write_height, ""},
	{"camera", true, write_camera, ""},
	{"light_direction", true, write_light_direction, ""},
	{"sun_angular_diameter", true, write_sun_angular_diameter, ""},
	{"boxes", true, write_boxes, ""},
	{"lights", true, write_lights, ""},
	{"probe_volumes", true, write_probe_volumes, ""},
	{"jitter", true, write_jitter, ""},
	{"shadow_phase", true, write_shadow_phase, ""},
	{"atlas_weight", true, write_atlas_weight, ""},
	{"sky", true, write_sky, ""},
	{"gi", true, write_gi, ""},
	{"ao", true, write_ao, ""},
	{"ao_radius", true, write_ao_radius, ""},
	{"ao_strength", true, write_ao_strength, ""},
	{"clip_height", true, write_clip_height, ""},
	{"view_flags", true, write_view_flags, ""},
	{"debug_lines", false, nil, "draws after the resolve"},
	{"hud", false, nil, "draws after the resolve"},
}

// The digest names the effective render inputs, not the game state. Two frames
// with the same digest draw the same scene, so a measurement can assert the
// inputs before it compares pixels.
render_digest :: proc(input: Render_Input) -> digest.FNV {
	hash := digest.fnv()
	for field in RENDER_DIGEST_FIELDS {
		if field.hashed {
			field.write(&hash, input)
		}
	}
	return hash
}

@(private)
write_width :: proc(hash: ^digest.FNV, input: Render_Input) {
	// The aspect changes the projection, so two sizes with one camera do not
	// draw the same image.
	digest.write_u32(hash, input.width)
}

@(private)
write_height :: proc(hash: ^digest.FNV, input: Render_Input) {
	digest.write_u32(hash, input.height)
}

@(private)
write_camera :: proc(hash: ^digest.FNV, input: Render_Input) {
	digest.write_f32(hash, input.camera.position.x)
	digest.write_f32(hash, input.camera.position.y)
	digest.write_f32(hash, input.camera.position.z)
	digest.write_f32(hash, input.camera.yaw)
	digest.write_f32(hash, input.camera.pitch)
	digest.write_f32(hash, input.camera.fov_x)
}

@(private)
write_light_direction :: proc(hash: ^digest.FNV, input: Render_Input) {
	digest.write_f32(hash, input.light_direction.x)
	digest.write_f32(hash, input.light_direction.y)
	digest.write_f32(hash, input.light_direction.z)
}

@(private)
write_sun_angular_diameter :: proc(hash: ^digest.FNV, input: Render_Input) {
	digest.write_f32(hash, input.sun_angular_diameter)
}

@(private)
write_boxes :: proc(hash: ^digest.FNV, input: Render_Input) {
	digest.write_u64(hash, u64(len(input.boxes)))
	for box in input.boxes {
		digest.write_f32(hash, box.center.x)
		digest.write_f32(hash, box.center.y)
		digest.write_f32(hash, box.center.z)
		digest.write_f32(hash, box.half_extents.x)
		digest.write_f32(hash, box.half_extents.y)
		digest.write_f32(hash, box.half_extents.z)
		digest.write_f32(hash, box.rotation.x)
		digest.write_f32(hash, box.rotation.y)
		digest.write_f32(hash, box.rotation.z)
		digest.write_f32(hash, box.rotation.w)
		digest.write_f32(hash, box.color.x)
		digest.write_f32(hash, box.color.y)
		digest.write_f32(hash, box.color.z)
		digest.write_f32(hash, box.color.w)
		digest.write_f32(hash, box.emissive)
		digest.write_bool(hash, box.visual_only)
	}
}

@(private)
write_lights :: proc(hash: ^digest.FNV, input: Render_Input) {
	digest.write_u64(hash, u64(len(input.lights)))
	for light in input.lights {
		digest.write_f32(hash, light.position.x)
		digest.write_f32(hash, light.position.y)
		digest.write_f32(hash, light.position.z)
		digest.write_f32(hash, light.intensity)
		digest.write_f32(hash, light.color.x)
		digest.write_f32(hash, light.color.y)
		digest.write_f32(hash, light.color.z)
		digest.write_f32(hash, light.range)
	}
}

@(private)
write_probe_volumes :: proc(hash: ^digest.FNV, input: Render_Input) {
	digest.write_u64(hash, u64(len(input.probe_volumes)))
	for volume in input.probe_volumes {
		digest.write_f32(hash, volume.min.x)
		digest.write_f32(hash, volume.min.y)
		digest.write_f32(hash, volume.min.z)
		digest.write_f32(hash, volume.spacing)
		digest.write_u32(hash, volume.counts.x)
		digest.write_u32(hash, volume.counts.y)
		digest.write_u32(hash, volume.counts.z)
	}
}

@(private)
write_jitter :: proc(hash: ^digest.FNV, input: Render_Input) {
	digest.write_f32(hash, input.jitter.x)
	digest.write_f32(hash, input.jitter.y)
}

@(private)
write_shadow_phase :: proc(hash: ^digest.FNV, input: Render_Input) {
	digest.write_u32(hash, input.shadow_phase)
}

@(private)
write_atlas_weight :: proc(hash: ^digest.FNV, input: Render_Input) {
	// The applied atlas weight changes the text pixels, so it belongs to the
	// render digest, not the simulation digest.
	digest.write_f32(hash, input.atlas_weight)
}

@(private)
write_sky :: proc(hash: ^digest.FNV, input: Render_Input) {
	digest.write_bool(hash, input.sky)
}

@(private)
write_gi :: proc(hash: ^digest.FNV, input: Render_Input) {
	digest.write_bool(hash, input.gi)
}

@(private)
write_ao :: proc(hash: ^digest.FNV, input: Render_Input) {
	digest.write_bool(hash, input.ao)
}

@(private)
write_ao_radius :: proc(hash: ^digest.FNV, input: Render_Input) {
	digest.write_f32(hash, input.ao_radius)
}

@(private)
write_ao_strength :: proc(hash: ^digest.FNV, input: Render_Input) {
	digest.write_f32(hash, input.ao_strength)
}

@(private)
write_clip_height :: proc(hash: ^digest.FNV, input: Render_Input) {
	digest.write_f32(hash, input.clip_height)
}

@(private)
write_view_flags :: proc(hash: ^digest.FNV, input: Render_Input) {
	digest.write_u32(hash, u32(transmute(u8)input.view_flags))
}
