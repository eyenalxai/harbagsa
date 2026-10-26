#+vet explicit-allocators
#+vet !unused-procedures // @(test) procs are called by the test runner, not by name
package harness_test

import "core:testing"

import "src:harness"

@(test)
capture_json_round_trips_every_option :: proc(t: ^testing.T) {
	cases := []harness.Capture_Command {
		{
			spec = {
				name = "stats-shot",
				note = "the statistics path\nwith a control byte",
				target = .Color,
				format = .Stats,
				png = true,
				region = harness.Capture_Region_Spec {
					unit = .Normalized,
					normalized = {0.25, 0.5, 0.25, 0.5},
				},
				histogram = 8,
				steps = {blur = 5, min = 0.5, max = 4},
				color_key = {r = 1, g = 2, b = 3, tolerance = 2.5},
				coverage = {black = 1.0, lit = 16.0},
			},
			has_frame = true,
			frame = 3,
			has_alpha = true,
			alpha = 0.5,
		},
		{
			spec = {
				name = "crop-shot",
				target = .Color,
				format = .Png,
				crop = {x = 1, y = 2, w = 3, h = 4, scale = 2},
			},
		},
		{
			spec = {
				name = "profile-shot",
				target = .Color,
				format = .Profile,
				profile = {
					axis = .Y,
					channel = .Z,
					at = 3,
					from = 1,
					to = 9,
					mean = true,
					low = 0.1,
					has_low = true,
					high = 0.9,
					has_high = true,
				},
			},
		},
		{
			spec = {
				name = "velocity",
				target = .Velocity,
				format = .Float,
			},
		},
	}
	for expected in cases {
		text := harness.capture_command_json(expected, context.temp_allocator)
		command, error := harness.command_parse_string(text, context.allocator)
		defer harness.command_destroy(&command, context.allocator)
		testing.expectf(t, error == "", "capture JSON did not parse for %s: %s", expected.name, error)
		if error != "" {
			delete(error, context.allocator)
			continue
		}
		testing.expect_value(t, command.kind, harness.Command_Kind.Capture)
		testing.expect_value(t, command.capture, expected)
	}
}
