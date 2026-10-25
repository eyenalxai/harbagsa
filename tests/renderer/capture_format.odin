#+vet explicit-allocators
#+vet !unused-procedures // @(test) procs are called by the test runner, not by name
package renderer_test

import "core:strings"
import "core:testing"

import "src:renderer"

@(test)
every_capture_format_fits_the_readback_and_has_a_decoder :: proc(t: ^testing.T) {
	for entry in renderer.CAPTURE_FORMATS {
		testing.expectf(
			t,
			entry.info.decode != .Unknown,
			"%s has no decode kind",
			entry.info.name,
		)
		testing.expectf(
			t,
			entry.info.texel_bytes > 0,
			"%s has no texel size",
			entry.info.name,
		)
		testing.expectf(
			t,
			entry.info.texel_bytes <= renderer.MAX_CAPTURE_TEXEL_BYTES,
			"%s needs %d bytes per texel, the readback stride is %d",
			entry.info.name,
			entry.info.texel_bytes,
			renderer.MAX_CAPTURE_TEXEL_BYTES,
		)
		testing.expect_value(t, renderer.texel_bytes(entry.format), entry.info.texel_bytes)
		testing.expect_value(t, renderer.format_name(entry.format), entry.info.name)
	}
}

@(test)
readback_without_an_allocation_names_the_cause :: proc(t: ^testing.T) {
	state: renderer.Renderer
	_, _, _, _, error := renderer.read_capture_target(&state, .Color)
	testing.expectf(
		t,
		strings.contains(error, "not allocated"),
		"the readback error is not specific: %s",
		error,
	)
	if error != "" {
		delete(error, context.allocator)
	}
}

@(test)
capture_values_decode_rgba8 :: proc(t: ^testing.T) {
	values := renderer.capture_values(
		[]u8{1, 2, 3, 255},
		.R8G8B8A8_UNORM,
		context.temp_allocator,
	)
	testing.expect_value(t, len(values), 4)
	if len(values) == 4 {
		testing.expect_value(t, values[0], f32(1))
		testing.expect_value(t, values[1], f32(2))
		testing.expect_value(t, values[2], f32(3))
		testing.expect_value(t, values[3], f32(255))
	}
}
