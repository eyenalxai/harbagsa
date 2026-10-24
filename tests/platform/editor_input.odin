#+vet explicit-allocators
#+vet !unused-procedures // @(test) procs are called by the test runner, not by name
package platform_test

import "core:testing"

import "src:platform"

Editor_Case :: struct {
	key:    platform.Key,
	mods:   platform.Modifiers,
	action: platform.Editor_Action,
	index:  int,
}

@(test)
editor_keys_map_to_actions :: proc(t: ^testing.T) {
	cases := []Editor_Case {
		{key = .Tab, action = .Toggle_Palette},
		{key = .Up, action = .Navigate_Up},
		{key = .Down, action = .Navigate_Down},
		{key = .Left, action = .Navigate_Left},
		{key = .Right, action = .Navigate_Right},
		{key = .Enter, action = .Confirm},
		{key = .M, action = .Flip_Body},
		{key = .G, action = .Toggle_Snap},
		{key = .Q, action = .Rotate_Left},
		{key = .E, action = .Rotate_Right},
		{key = .L, action = .Sun_Placement},
		{key = .C, action = .Light_Color},
		{key = .Left_Bracket, action = .Light_Intensity_Down},
		{key = .Right_Bracket, action = .Light_Intensity_Up},
		{key = .Comma, action = .Light_Range_Down},
		{key = .Period, action = .Light_Range_Up},
		{key = .Delete, action = .Delete},
		{key = .X, action = .Delete},
		{key = .Escape, action = .Cancel},
		{key = .D, mods = {.Ctrl}, action = .Duplicate},
		{key = .D, mods = {.Ctrl, .Shift}, action = .Duplicate},
		{key = .Z, mods = {.Ctrl}, action = .Undo},
		{key = .Z, mods = {.Ctrl, .Shift}, action = .Redo},
		{key = .Digit_1, action = .Select_Card, index = 1},
		{key = .Digit_2, action = .Select_Card, index = 2},
		{key = .Digit_3, action = .Select_Card, index = 3},
		{key = .Digit_4, action = .Select_Card, index = 4},
		{key = .Digit_5, action = .Select_Card, index = 5},
		{key = .Digit_6, action = .Select_Card, index = 6},
		{key = .Digit_7, action = .Select_Card, index = 7},
		{key = .Digit_8, action = .Select_Card, index = 8},
		{key = .Digit_9, action = .Select_Card, index = 9},
	}

	for value in cases {
		command := platform.editor_command(value.key, value.mods)
		testing.expectf(
			t,
			command.action == value.action && command.index == value.index,
			"%v with %v mapped to %v/%d, want %v/%d",
			value.key,
			value.mods,
			command.action,
			command.index,
			value.action,
			value.index,
		)
	}
}

@(test)
editor_keys_without_a_modifier_command_stay_clear :: proc(t: ^testing.T) {
	unmodified := []platform.Key{.D, .Z}
	for key in unmodified {
		command := platform.editor_command(key, {})
		testing.expectf(t, command.action == .None, "%v acted without Ctrl", key)
	}

	shift_only := platform.editor_command(.Z, {.Shift})
	testing.expect_value(t, shift_only.action, platform.Editor_Action.None)
	unknown := platform.editor_command(.None, {.Ctrl, .Shift})
	testing.expect_value(t, unknown.action, platform.Editor_Action.None)
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
