#+vet explicit-allocators
#+vet !unused-procedures // @(test) procs are called by the test runner, not by name
package harness_test

import "core:testing"

import "src:harness"

@(test)
every_window_setting_changes_the_digest :: proc(t: ^testing.T) {
	base := harness.State {
		settings = {
			window_mode       = "Borderless",
			display           = "Display 1",
			display_index     = 0,
			resolution        = "1920x1080",
			window_resolution = "1280x720",
			sprint_mode       = "Hold",
			type_weight       = 400,
		},
		menu = {selected = 0, item = "Window mode"},
	}

	mode := base
	mode.settings.window_mode = "Windowed"
	expect_digest_differs(t, base, mode, "window mode")

	display := base
	display.settings.display = "Display 2"
	expect_digest_differs(t, base, display, "display")

	display_index := base
	display_index.settings.display_index = 1
	expect_digest_differs(t, base, display_index, "display index")

	resolution := base
	resolution.settings.resolution = "1280x720"
	expect_digest_differs(t, base, resolution, "resolution")

	window_resolution := base
	window_resolution.settings.window_resolution = "1920x1080"
	expect_digest_differs(t, base, window_resolution, "window resolution")

	weight := base
	weight.settings.type_weight = 900
	expect_digest_differs(t, base, weight, "type weight")
}

@(private)
expect_digest_differs :: proc(t: ^testing.T, a, b: harness.State, label: string) {
	digest_a := harness.state_digest(a, context.allocator)
	defer delete(digest_a, context.allocator)
	digest_b := harness.state_digest(b, context.allocator)
	defer delete(digest_b, context.allocator)
	testing.expectf(t, digest_a != digest_b, "%s did not change the digest", label)
}
