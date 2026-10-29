#+vet explicit-allocators
package renderer

import "src:bake"
import vk "vendor:vulkan"

// The loaded artifact and the missing-artifact placeholder share this path, so
// the probe bindings cannot drift between the two states.
@(private)
create_bake_probes :: proc(
	r: ^Renderer,
	width, height: u32,
	irradiance_bytes, moment_bytes: []u8,
	states: []bake.Probe_State,
	volume: Bake_Volume_Uniform,
) -> bool {
	irradiance, irradiance_ok := upload_texture(
		r,
		width,
		height,
		.R16G16B16A16_SFLOAT,
		irradiance_bytes,
	)
	if !irradiance_ok {
		return false
	}
	r.bake.probe_irradiance = irradiance

	moments, moments_ok := upload_texture(
		r,
		width,
		height,
		.R16G16_SFLOAT,
		moment_bytes,
	)
	if !moments_ok {
		return false
	}
	r.bake.probe_moments = moments

	if !create_device_buffer(
		r,
		raw_data(states),
		vk.DeviceSize(len(states) * size_of(bake.Probe_State)),
		{.STORAGE_BUFFER},
		&r.bake.states_buffer,
		&r.bake.states_memory,
	) {
		return false
	}
	r.bake.states_bytes = len(states) * size_of(bake.Probe_State)
	volume_copy := volume
	return create_device_buffer(
		r,
		&volume_copy,
		vk.DeviceSize(size_of(Bake_Volume_Uniform)),
		{.UNIFORM_BUFFER},
		&r.bake.volume_buffer,
		&r.bake.volume_memory,
	)
}
