#+vet explicit-allocators
package renderer

import "src:bake"
import vk "vendor:vulkan"

// The loaded artifact and the missing-artifact placeholder share this path, so
// the probe bindings cannot drift between the two states.
@(private)
create_bake_probes :: proc(
	r: ^Renderer,
	b: ^Bake_Resources,
	width, height: u32,
	irradiance_format, moment_format: vk.Format,
	irradiance_bytes, moment_bytes: []u8,
	states: []bake.Probe_State,
	volume: ^Bake_Volume_Uniform,
) -> bool {
	irradiance, irradiance_ok := upload_texture(
		r,
		width,
		height,
		irradiance_format,
		irradiance_bytes,
	)
	if !irradiance_ok {
		return false
	}
	b.probe_irradiance = irradiance

	moments, moments_ok := upload_texture(
		r,
		width,
		height,
		moment_format,
		moment_bytes,
	)
	if !moments_ok {
		return false
	}
	b.probe_moments = moments

	if !create_device_buffer(
		r,
		raw_data(states),
		vk.DeviceSize(len(states) * size_of(bake.Probe_State)),
		{.STORAGE_BUFFER},
		&b.states_buffer,
		&b.states_memory,
	) {
		return false
	}
	b.states_bytes = len(states) * size_of(bake.Probe_State)
	return create_device_buffer(
		r,
		volume,
		vk.DeviceSize(size_of(Bake_Volume_Uniform)),
		{.UNIFORM_BUFFER},
		&b.volume_buffer,
		&b.volume_memory,
	)
}
