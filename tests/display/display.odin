#+vet explicit-allocators
#+vet !unused-procedures // @(test) procs are called by the test runner, not by name
package display_test

import "core:testing"

import "src:display"

@(test)
modes_deduplicate_and_sort_largest_first :: proc(t: ^testing.T) {
	info: display.Info
	display.set_name(&info, "HDMI-A-1")
	display.set_desktop(&info, {1920, 1080})
	display.add_mode(&info, {1280, 720})
	display.add_mode(&info, {1920, 1080})
	display.add_mode(&info, {1600, 900})
	display.sort_modes(&info)

	testing.expect_value(t, info.mode_count, 3)
	testing.expect_value(t, info.modes[0], display.Mode{1920, 1080})
	testing.expect_value(t, info.modes[1], display.Mode{1600, 900})
	testing.expect_value(t, info.modes[2], display.Mode{1280, 720})
}

@(test)
snap_mode_picks_the_nearest_size :: proc(t: ^testing.T) {
	info: display.Info
	display.set_desktop(&info, {1920, 1080})
	display.add_mode(&info, {1600, 900})
	display.add_mode(&info, {1280, 720})
	display.sort_modes(&info)

	testing.expect_value(t, display.snap_mode(&info, {1280, 720}), display.Mode{1280, 720})
	testing.expect_value(t, display.snap_mode(&info, {1366, 768}), display.Mode{1280, 720})
	testing.expect_value(t, display.snap_mode(&info, {1024, 768}), display.Mode{1280, 720})
}

@(test)
cycle_mode_moves_in_both_directions_and_wraps :: proc(t: ^testing.T) {
	info: display.Info
	display.set_desktop(&info, {1920, 1080})
	display.add_mode(&info, {1600, 900})
	display.add_mode(&info, {1280, 720})
	display.sort_modes(&info)

	testing.expect_value(t, display.cycle_mode(&info, {1920, 1080}, 1), display.Mode{1600, 900})
	testing.expect_value(t, display.cycle_mode(&info, {1920, 1080}, -1), display.Mode{1280, 720})
	testing.expect_value(t, display.cycle_mode(&info, {1280, 720}, 1), display.Mode{1920, 1080})
	testing.expect_value(t, display.cycle_mode(&info, {1366, 768}, 1), display.Mode{1920, 1080})
	testing.expect_value(t, display.cycle_mode(&info, {1366, 768}, -1), display.Mode{1280, 720})
}

@(test)
small_windowed_modes_are_filtered :: proc(t: ^testing.T) {
	testing.expect(t, display.keep_windowed_mode({800, 600}), "800x600 was rejected")
	testing.expect(t, display.keep_windowed_mode({1024, 768}), "1024x768 was rejected")
	testing.expect(t, !display.keep_windowed_mode({800, 480}), "800x480 was kept")
	testing.expect(t, !display.keep_windowed_mode({640, 480}), "640x480 was kept")
}

@(test)
display_index_clamps_to_the_list :: proc(t: ^testing.T) {
	list := display.fallback_list()
	testing.expect_value(t, list.count, 2)
	testing.expect_value(t, display.clamp_index(&list, -1), 0)
	testing.expect_value(t, display.clamp_index(&list, 2), 0)
	testing.expect_value(t, display.clamp_index(&list, 1), 1)
	testing.expect_value(t, display.name(display.info_at(&list, 0)), "Display 1")
	testing.expect_value(t, display.name(display.info_at(&list, 8)), "Display 1")
}

@(test)
fallback_displays_start_at_their_desktop_mode :: proc(t: ^testing.T) {
	list := display.fallback_list()
	second := display.info_at(&list, 1)

	testing.expect_value(t, display.name(second), "Display 2")
	testing.expect_value(t, second.desktop, display.Mode{2560, 1440})
	testing.expect_value(t, second.mode_count, 3)
	testing.expect_value(t, second.modes[0], display.Mode{2560, 1440})
	testing.expect_value(t, second.modes[2], display.Mode{1280, 720})
}
