#+vet explicit-allocators
#+vet !unused-procedures // shared by the renderer tests
package renderer_test

import "src:platform"
import "src:renderer"

Test_Device :: struct {
	headless: platform.Headless,
	state:    renderer.Renderer,
	opened:   bool,
}

open_test_device :: proc(device: ^Test_Device) -> bool {
	if !platform.headless_init(&device.headless, TEST_WIDTH, TEST_HEIGHT) {
		return false
	}
	state, init_error := renderer.init(
		renderer.Config {
			platform = platform.headless_platform(&device.headless),
			target = .Offscreen,
			width = TEST_WIDTH,
			height = TEST_HEIGHT,
		},
		context.allocator,
	)
	if init_error != .None {
		platform.headless_deinit(&device.headless)
		return false
	}
	device.state = state
	device.opened = true
	return true
}

close_test_device :: proc(device: ^Test_Device) {
	if !device.opened {
		return
	}
	renderer.deinit(&device.state)
	platform.headless_deinit(&device.headless)
	device.opened = false
}
