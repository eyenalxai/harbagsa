#+vet explicit-allocators
#+vet !unused-procedures // @(test) procs are called by the test runner, not by name
package platform_test

import "core:testing"

import "vendor:sdl3"

import "src:platform"

@(test)
scancodes_map_to_the_key_edges_the_input_module_reads :: proc(t: ^testing.T) {
	cases := []struct {
		code: sdl3.Scancode,
		key:  platform.Key,
	} {
		{.TAB, .Tab},
		{.Q, .Q},
		{.E, .E},
		{.G, .G},
		{.M, .M},
		{.L, .L},
		{.C, .C},
		{.LEFTBRACKET, .Left_Bracket},
		{.RIGHTBRACKET, .Right_Bracket},
		{.COMMA, .Comma},
		{.PERIOD, .Period},
		{.UP, .Up},
		{.DOWN, .Down},
		{.LEFT, .Left},
		{.RIGHT, .Right},
		{.RETURN, .Enter},
		{.KP_ENTER, .Enter},
		{.ESCAPE, .Escape},
		{.DELETE, .Delete},
		{.X, .X},
		{.D, .D},
		{.Z, .Z},
		{.SPACE, .Space},
		{.R, .R},
		{.LSHIFT, .LShift},
		{.F1, .F1},
		{.F2, .F2},
		{.F3, .F3},
		{.F4, .F4},
		{.F5, .F5},
		{._1, .Digit_1},
		{._9, .Digit_9},
	}
	for value in cases {
		testing.expectf(
			t,
			platform.key_from_scancode(value.code) == value.key,
			"%v mapped to %v, want %v",
			value.code,
			platform.key_from_scancode(value.code),
			value.key,
		)
	}
	testing.expect_value(t, platform.key_from_scancode(.A), platform.Key.None)
}

@(test)
normalized_pointer_maps_window_coordinates_to_unit_space :: proc(t: ^testing.T) {
	testing.expect_value(t, platform.normalize_pointer(640, 360, 1280, 720), [2]f32{0.5, 0.5})
	testing.expect_value(t, platform.normalize_pointer(0, 0, 1280, 720), [2]f32{0, 0})
	testing.expect_value(t, platform.normalize_pointer(1280, 720, 1280, 720), [2]f32{1, 1})
	testing.expect_value(t, platform.normalize_pointer(1440, 360, 1280, 720), [2]f32{1.125, 0.5})
	testing.expect_value(t, platform.normalize_pointer(-1280, 0, 1280, 720), [2]f32{-1, 0})
	testing.expect_value(t, platform.normalize_pointer(640, 360, 0, 720), [2]f32{0, 0})
	testing.expect_value(t, platform.normalize_pointer(640, 360, 1280, 0), [2]f32{0, 0})
}
