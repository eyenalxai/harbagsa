#+vet explicit-allocators
package renderer

import "src:bake"
import vk "vendor:vulkan"

// The descriptor set is written before a frame knows whether an artifact
// exists. The shader never samples these stand-ins; a box without a slot skips
// the fetch, the volume has no probes, and the bake status reports the missing
// or failed load.
create_bake_placeholder :: proc(r: ^Renderer) -> bool {
	if !create_clamp_sampler(r, &r.bake.sampler) {
		return false
	}
	zeros := [8]u8{}
	lightmap, lightmap_ok := upload_texture(
		r,
		1,
		1,
		.R16G16B16A16_SFLOAT,
		zeros[:],
	)
	if !lightmap_ok {
		return false
	}
	r.bake.lightmap = lightmap
	irradiance, irradiance_ok := upload_texture(
		r,
		1,
		1,
		.R16G16B16A16_SFLOAT,
		zeros[:],
	)
	if !irradiance_ok {
		return false
	}
	r.bake.probe_irradiance = irradiance
	moments, moments_ok := upload_texture(r, 1, 1, .R16G16_SFLOAT, zeros[:4])
	if !moments_ok {
		return false
	}
	r.bake.probe_moments = moments
	face := bake.Face{}
	if !create_device_buffer(
		r,
		&face,
		vk.DeviceSize(size_of(bake.Face)),
		{.STORAGE_BUFFER},
		&r.bake.faces_buffer,
		&r.bake.faces_memory,
	) {
		return false
	}
	r.bake.faces_bytes = size_of(bake.Face)
	state := bake.Probe_State{}
	if !create_device_buffer(
		r,
		&state,
		vk.DeviceSize(size_of(bake.Probe_State)),
		{.STORAGE_BUFFER},
		&r.bake.states_buffer,
		&r.bake.states_memory,
	) {
		return false
	}
	r.bake.states_bytes = size_of(bake.Probe_State)
	volume: Bake_Volume_Uniform
	if !create_device_buffer(
		r,
		&volume,
		vk.DeviceSize(size_of(Bake_Volume_Uniform)),
		{.UNIFORM_BUFFER},
		&r.bake.volume_buffer,
		&r.bake.volume_memory,
	) {
		return false
	}
	return true
}
