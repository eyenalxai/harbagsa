#+vet explicit-allocators
package renderer

import vk "vendor:vulkan"

TAA_JITTER_SAMPLES :: 8

halton :: proc(index, base: u32) -> f32 {
	result: f32
	factor := f32(1)
	i := index
	for i > 0 {
		factor /= f32(base)
		result += factor * f32(i % base)
		i /= base
	}
	return result
}

taa_jitter :: proc(sample: int, extent: vk.Extent2D) -> [2]f32 {
	index := u32(sample % TAA_JITTER_SAMPLES) + 1
	offset := [2]f32{halton(index, 2) - 0.5, halton(index, 3) - 0.5}
	return {
		2 * offset.x / f32(extent.width),
		2 * offset.y / f32(extent.height),
	}
}
