#+vet explicit-allocators
#+vet !unused-procedures // @(test) procs are called by the test runner, not by name
package simulation

import "core:math"
import "core:testing"

import "src:ui"

@(test)
slider_hit_uses_the_full_track_and_the_knob_travel :: proc(t: ^testing.T) {
	rect := ui.Slider_Rect{x = 10, y = 20, width = 100, height = 12, knob = 10}

	left, left_inside := ui.slider_hit(rect, {10, 26})
	testing.expect(t, left_inside, "the left track edge is outside")
	testing.expect_value(t, left, f32(0))

	left_knob, left_knob_inside := ui.slider_hit(rect, {15, 26})
	testing.expect(t, left_knob_inside, "the left knob edge is outside")
	testing.expect_value(t, left_knob, f32(0))

	middle, middle_inside := ui.slider_hit(rect, {60, 26})
	testing.expect(t, middle_inside, "the midpoint is outside")
	testing.expect(t, math.abs(middle - 0.5) < 0.0001, "the midpoint ratio is wrong")

	right_knob, right_knob_inside := ui.slider_hit(rect, {105, 26})
	testing.expect(t, right_knob_inside, "the right knob edge is outside")
	testing.expect_value(t, right_knob, f32(1))

	right, right_inside := ui.slider_hit(rect, {110, 26})
	testing.expect(t, right_inside, "the right track edge is outside")
	testing.expect_value(t, right, f32(1))
}

@(test)
slider_hit_rejects_points_outside_the_track :: proc(t: ^testing.T) {
	rect := ui.Slider_Rect{x = 10, y = 20, width = 100, height = 12, knob = 10}

	_, left := ui.slider_hit(rect, {9, 26})
	testing.expect(t, !left, "a point left of the track is inside")

	_, right := ui.slider_hit(rect, {111, 26})
	testing.expect(t, !right, "a point right of the track is inside")

	_, above := ui.slider_hit(rect, {60, 19})
	testing.expect(t, !above, "a point above the track is inside")

	_, below := ui.slider_hit(rect, {60, 33})
	testing.expect(t, !below, "a point below the track is inside")
}

@(test)
slider_hit_handles_a_zero_width_track :: proc(t: ^testing.T) {
	rect := ui.Slider_Rect{x = 10, y = 20, width = 0, height = 12, knob = 10}
	ratio, inside := ui.slider_hit(rect, {10, 26})
	testing.expect(t, !inside, "a zero width track has an inside point")
	testing.expect_value(t, ratio, f32(0))
}

@(test)
slider_hit_clamps_the_ratio_outside_the_travel :: proc(t: ^testing.T) {
	rect := ui.Slider_Rect{x = 10, y = 20, width = 100, height = 12, knob = 10}

	left, _ := ui.slider_hit(rect, {0, 26})
	testing.expect_value(t, left, f32(0))

	right, _ := ui.slider_hit(rect, {200, 26})
	testing.expect_value(t, right, f32(1))
}
