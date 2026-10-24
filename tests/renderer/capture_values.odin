#+vet explicit-allocators
#+vet !unused-procedures // @(test) procs are called by the test runner, not by name
package renderer_test

import "core:testing"

import "src:renderer"

@(test)
capture_values_decode_rgba16f :: proc(t: ^testing.T) {
	// 1.0, 2.0, 3.0, 4.0 as little-endian binary16.
	bytes := []u8{0x00, 0x3C, 0x00, 0x40, 0x00, 0x42, 0x00, 0x44}
	values := renderer.capture_values(bytes, .R16G16B16A16_SFLOAT, context.temp_allocator)
	testing.expect_value(t, len(values), 4)
	if len(values) != 4 {
		return
	}
	testing.expect_value(t, values[0], f32(1))
	testing.expect_value(t, values[1], f32(2))
	testing.expect_value(t, values[2], f32(3))
	testing.expect_value(t, values[3], f32(4))
}

@(test)
capture_values_decode_depth_into_the_first_channel :: proc(t: ^testing.T) {
	depth := f32(2.5)
	bytes := slice_to_bytes(depth)
	values := renderer.capture_values(bytes, .D32_SFLOAT, context.temp_allocator)
	testing.expect_value(t, len(values), 4)
	if len(values) != 4 {
		return
	}
	testing.expect_value(t, values[0], depth)
	testing.expect_value(t, values[1], f32(0))
}

@(private)
slice_to_bytes :: proc(value: f32) -> []u8 {
	bytes := make([]u8, 4, context.temp_allocator)
	bits := transmute(u32)value
	bytes[0] = u8(bits)
	bytes[1] = u8(bits >> 8)
	bytes[2] = u8(bits >> 16)
	bytes[3] = u8(bits >> 24)
	return bytes
}
