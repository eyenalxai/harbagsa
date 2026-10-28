#+vet explicit-allocators
package bake

import "src:digest"
import "src:geometry"

// -0.0 and 0.0 are the same input, so the key must see the same bits.
canonical_f32 :: proc(value: f32) -> f32 {
	if value == 0 {
		return 0
	}
	return value
}

key :: proc(input: Input) -> u64 {
	hash := digest.fnv()
	digest.write_u32(&hash, KEY_VERSION)
	digest.write_u32(&hash, TOOL_VERSION)
	write_quality(&hash, input.quality)

	digest.write_u64(&hash, u64(len(input.boxes)))
	for entry in input.boxes {
		digest.write_u64(&hash, u64(entry.source))
		digest.write_u32(&hash, entry.id)
		write_box(&hash, entry.box)
	}

	digest.write_u64(&hash, u64(len(input.lights)))
	for light in input.lights {
		digest.write_u32(&hash, light.id)
		write_vec3(&hash, light.position)
		write_vec3(&hash, light.color)
		digest.write_f32(&hash, canonical_f32(light.intensity))
		digest.write_f32(&hash, canonical_f32(light.range))
		digest.write_f32(&hash, canonical_f32(light.emissive))
	}
	return hash.value
}

@(private)
write_quality :: proc(hash: ^digest.FNV, quality: Quality) {
	digest.write_u32(hash, quality.atlas_size)
	digest.write_u32(hash, quality.texels_per_meter)
	digest.write_u32(hash, quality.gutter_texels)
	digest.write_u32(hash, quality.min_chart)
	digest.write_u32(hash, quality.lightmap_rays)
	digest.write_u32(hash, quality.probe_rays)
	digest.write_u32(hash, quality.bounces)
	digest.write_f32(hash, canonical_f32(quality.probe_spacing))
	digest.write_u32(hash, quality.probe_texels)
}

@(private)
write_box :: proc(hash: ^digest.FNV, box: geometry.Box) {
	write_vec3(hash, box.center)
	write_vec3(hash, box.half_extents)
	digest.write_f32(hash, canonical_f32(box.rotation.x))
	digest.write_f32(hash, canonical_f32(box.rotation.y))
	digest.write_f32(hash, canonical_f32(box.rotation.z))
	digest.write_f32(hash, canonical_f32(box.rotation.w))
	digest.write_f32(hash, canonical_f32(box.color.x))
	digest.write_f32(hash, canonical_f32(box.color.y))
	digest.write_f32(hash, canonical_f32(box.color.z))
	digest.write_f32(hash, canonical_f32(box.color.w))
	digest.write_f32(hash, canonical_f32(box.emissive))
	digest.write_bool(hash, box.visual_only)
}

@(private)
write_vec3 :: proc(hash: ^digest.FNV, value: [3]f32) {
	digest.write_f32(hash, canonical_f32(value.x))
	digest.write_f32(hash, canonical_f32(value.y))
	digest.write_f32(hash, canonical_f32(value.z))
}
