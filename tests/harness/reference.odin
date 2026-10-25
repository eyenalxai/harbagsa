#+vet explicit-allocators
#+vet !unused-procedures // @(test) procs are called by the test runner, not by name
package harness_test

import "core:testing"

import "src:harness"

@(test)
reference_parse_defaults_and_tolerance :: proc(t: ^testing.T) {
	command, error := harness.command_parse_string(
		`{"cmd":"reference","name":"chamber","gi":"gi-on","direct":"gi-off",
		  "tolerance":{"ratio_min":0.8,"ratio_max":1.25}}`,
		context.allocator,
	)
	defer harness.command_destroy(&command, context.allocator)
	testing.expectf(t, error == "", "reference parse failed: %s", error)
	if error != "" {
		return
	}
	testing.expect_value(t, command.kind, harness.Command_Kind.Reference)
	testing.expect_value(t, command.reference.name, "chamber")
	testing.expect_value(t, command.reference.gi, "gi-on")
	testing.expect_value(t, command.reference.direct, "gi-off")
	testing.expect_value(t, command.reference.settings.samples, 48)
	testing.expect_value(t, command.reference.settings.bounces, 3)
	testing.expect_value(t, command.reference.settings.stride, 16)
	testing.expect_value(t, command.reference.settings.sun_samples, 16)
	testing.expect_value(t, command.reference.tolerance.ratio_min, 0.8)
	testing.expect_value(t, command.reference.tolerance.ratio_max, 1.25)
	testing.expect_value(t, command.reference.tolerance.error_max, 0.35)
}

@(test)
reference_parse_rejects_a_bad_field :: proc(t: ^testing.T) {
	lines := [?]string{
		`{"cmd":"reference","name":"a","gi":"b"}`,
		`{"cmd":"reference","name":"a","gi":"b","direct":"c","bounces":1}`,
		`{"cmd":"reference","name":"a","gi":"b","direct":"c","samples":0}`,
		`{"cmd":"reference","name":"a","gi":"b","direct":"c","colour":"x"}`,
		`{"cmd":"reference","name":"a","gi":"b","direct":"c",
		  "tolerance":{"ratio_min":2,"ratio_max":1}}`,
	}
	for line in lines {
		command, error := harness.command_parse_string(line, context.allocator)
		harness.command_destroy(&command, context.allocator)
		testing.expectf(t, error != "", "a bad reference line parsed: %s", line)
		if error != "" {
			delete(error, context.allocator)
		}
	}
}
