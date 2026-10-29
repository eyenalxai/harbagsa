#+vet explicit-allocators
package renderer

import "core:fmt"
import "core:log"

import "src:bake"
import vk "vendor:vulkan"

// The lightmap image, the face rects, and the shared sampler are one unit. The
// placeholder and the loaded artifact use the same path so a missing bake
// cannot drift from a real one.
@(private)
create_bake_lightmap :: proc(
	r: ^Renderer,
	b: ^Bake_Resources,
	width, height: u32,
	format: vk.Format,
	atlas: []u8,
	faces: []bake.Face,
) -> bool {
	if !format_supports(r, format, {.SAMPLED_IMAGE_FILTER_LINEAR}) {
		log_bake_error(r, "the device cannot filter the lightmap format")
		return false
	}
	lightmap, lightmap_ok := upload_texture(r, width, height, format, atlas)
	if !lightmap_ok {
		return false
	}
	b.lightmap = lightmap
	if !create_device_buffer(
		r,
		raw_data(faces),
		vk.DeviceSize(len(faces) * size_of(bake.Face)),
		{.STORAGE_BUFFER},
		&b.faces_buffer,
		&b.faces_memory,
	) {
		return false
	}
	b.faces_bytes = len(faces) * size_of(bake.Face)
	return create_clamp_sampler(r, &b.sampler)
}

@(private)
create_bake_resources :: proc(r: ^Renderer, b: ^Bake_Resources) -> bool {
	data := &b.data
	if !format_supports(r, .R16G16_SFLOAT, {.SAMPLED_IMAGE_FILTER_LINEAR}) {
		log_bake_error(r, "the device cannot filter R16G16_SFLOAT")
		return false
	}
	if !create_bake_lightmap(
		r,
		b,
		data.header.atlas_width,
		data.header.atlas_height,
		.R16G16B16A16_SFLOAT,
		data.atlas,
		data.faces,
	) {
		return false
	}

	b.slot_lookup = make(map[u64]u32, len(data.slots), r.allocator)
	for slot, index in data.slots {
		b.slot_lookup[slot.key] = u32(index)
	}

	if !create_device_buffer(
		r,
		raw_data(data.slots),
		vk.DeviceSize(len(data.slots) * size_of(bake.Slot)),
		{.STORAGE_BUFFER},
		&b.slots_buffer,
		&b.slots_memory,
	) {
		return false
	}
	volume := Bake_Volume_Uniform {
		min           = data.header.probe_min,
		spacing       = data.header.probe_spacing,
		counts        = data.header.probe_counts,
		probe_texels  = data.header.probe_texels,
		atlas_columns = data.header.probe_atlas_columns,
		probe_count   = data.header.probe_count,
		atlas_width   = data.probe_atlas_width,
		atlas_height  = data.probe_atlas_height,
	}
	if !create_bake_probes(
		r,
		b,
		data.probe_atlas_width,
		data.probe_atlas_height,
		.R16G16B16A16_SFLOAT,
		.R16G16_SFLOAT,
		data.probe_irradiance,
		data.probe_moments,
		data.probe_states,
		&volume,
	) {
		return false
	}

	b.gpu_bytes = len(data.atlas) + len(data.probe_irradiance) + len(data.probe_moments)
	b.gpu_bytes += len(data.faces) * size_of(bake.Face)
	b.gpu_bytes += len(data.slots) * size_of(bake.Slot)
	b.gpu_bytes += len(data.probe_states) * size_of(bake.Probe_State)
	b.gpu_bytes += size_of(Bake_Volume_Uniform)
	return true
}

// The artifact data, the path, and the error belong to the owner. This drops
// only the device resources, so a publish can replace them without losing the
// report state it is about to overwrite.
@(private)
destroy_bake_resources :: proc(r: ^Renderer, b: ^Bake_Resources) {
	destroy_image(r, &b.lightmap)
	destroy_image(r, &b.probe_irradiance)
	destroy_image(r, &b.probe_moments)
	if r.device != nil && b.sampler != 0 {
		vk.DestroySampler(r.device, b.sampler, nil)
	}
	b.sampler = 0
	destroy_buffer(r, &b.faces_buffer, &b.faces_memory)
	destroy_buffer(r, &b.slots_buffer, &b.slots_memory)
	destroy_buffer(r, &b.states_buffer, &b.states_memory)
	destroy_buffer(r, &b.volume_buffer, &b.volume_memory)
	if b.slot_lookup != nil {
		delete(b.slot_lookup)
		b.slot_lookup = nil
	}
	b.faces_bytes = 0
	b.states_bytes = 0
	b.gpu_bytes = 0
	b.probe_missing = 0
}

@(private)
log_bake_error :: proc(r: ^Renderer, message: string) {
	r.bake.status = .Failed
	if r.bake.error != "" {
		delete(r.bake.error, r.allocator)
	}
	r.bake.error = fmt.aprintf("%s: %s", r.bake.path, message, allocator = r.allocator)
	log.errorf("renderer: %s", r.bake.error)
}
