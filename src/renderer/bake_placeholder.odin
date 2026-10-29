#+vet explicit-allocators
package renderer

import "src:bake"
import vk "vendor:vulkan"

// A descriptor set must name every image and buffer even when no bake is
// loaded. Nothing samples the placeholders: every object's lightmap and probe
// weights are zero while the status reports missing or failed. The formats are
// mandatory ones, so a device without float filtering still starts and reports
// the missing indirect data.
@(private)
create_bake_placeholder :: proc(r: ^Renderer) -> bool {
	zero := [4]u8{}
	faces := [1]bake.Face{}
	if !create_bake_lightmap(r, 1, 1, .R8G8B8A8_UNORM, zero[:], faces[:]) {
		return false
	}
	irradiance, irradiance_ok := upload_texture(r, 1, 1, .R8G8B8A8_UNORM, zero[:])
	if !irradiance_ok {
		return false
	}
	r.bake.probe_irradiance = irradiance
	moments, moments_ok := upload_texture(r, 1, 1, .R8G8B8A8_UNORM, zero[:])
	if !moments_ok {
		return false
	}
	r.bake.probe_moments = moments

	state := [1]bake.Probe_State{}
	if !create_device_buffer(
		r,
		raw_data(state[:]),
		vk.DeviceSize(size_of(bake.Probe_State)),
		{.STORAGE_BUFFER},
		&r.bake.states_buffer,
		&r.bake.states_memory,
	) {
		return false
	}
	r.bake.states_bytes = size_of(bake.Probe_State)
	volume := Bake_Volume_Uniform {
		spacing       = 1,
		counts        = {1, 1, 1},
		probe_texels  = bake.PROBE_TEXELS,
		atlas_columns = 1,
		probe_count   = 1,
		atlas_width   = 1,
		atlas_height  = 1,
	}
	return create_device_buffer(
		r,
		&volume,
		vk.DeviceSize(size_of(Bake_Volume_Uniform)),
		{.UNIFORM_BUFFER},
		&r.bake.volume_buffer,
		&r.bake.volume_memory,
	)
}
