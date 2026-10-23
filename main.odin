#+vet explicit-allocators
package main

import "core:log"
import "core:os"

import "src:platform"
import "src:renderer"

WINDOW_WIDTH :: 1280
WINDOW_HEIGHT :: 720

main :: proc() {
	context.logger = log.create_console_logger(lowest = .Info, allocator = context.allocator)
	defer log.destroy_console_logger(context.logger, allocator = context.allocator)

	if !run() {
		os.exit(1)
	}
}

run :: proc() -> bool {
	window, platform_error := platform.init("harbagsa", WINDOW_WIDTH, WINDOW_HEIGHT)
	if platform_error != .None {
		log.errorf("harbagsa: platform init failed: %v", platform_error)
		return false
	}
	defer platform.deinit(&window)

	state, renderer_error := renderer.init(&window, context.allocator)
	if renderer_error != .None {
		log.errorf("harbagsa: renderer init failed: %v", renderer_error)
		return false
	}
	defer renderer.deinit(&state)

	for {
		events := platform.poll_events()
		if events.quit {
			return true
		}

		width, height := platform.pixel_size(&window)
		if platform.is_minimized(&window) || width == 0 || height == 0 {
			// Do not spin while minimized or while the window has no drawable
			// area. Block until an event or a short timeout, then try again.
			waited := platform.wait_events(100)
			if waited.quit {
				return true
			}
			continue
		}

		frame, begin_status := renderer.begin_frame(&state)
		switch begin_status {
		case .Ok:
		case .Skipped:
			continue
		case .Fatal:
			return false
		}

		switch renderer.end_frame(&state, frame) {
		case .Ok:
		case .Skipped:
			// The swapchain is out of date. The next frame recreates it.
		case .Fatal:
			return false
		}
	}
}
