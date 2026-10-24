#+vet explicit-allocators
#+vet !unused-procedures
package harness_test

import "core:strings"
import "core:testing"

import "src:harness"

@(test)
ab_base_maps_to_ref :: proc(t: ^testing.T) {
	ab_expect_args(
		t,
		[]string{"--base", "origin/main"},
		[]string{"--ref", "origin/main"},
	)
	ab_expect_args(
		t,
		[]string{"--ref", "main"},
		[]string{"--ref", "main"},
	)
}

@(test)
ab_pass_through_flags_keep_their_order_and_values :: proc(t: ^testing.T) {
	ab_expect_args(
		t,
		[]string {
			"--scenario",
			"scenarios/perf.json",
			"--size",
			"1280x720",
			"--scenario",
			"scenarios/perf-crates.json",
			"--runs",
			"3",
			"--prime",
			"2.5",
			"--out",
			"runs/ab-test",
		},
		[]string {
			"--scenario",
			"scenarios/perf.json",
			"--size",
			"1280x720",
			"--scenario",
			"scenarios/perf-crates.json",
			"--runs",
			"3",
			"--prime",
			"2.5",
			"--out",
			"runs/ab-test",
		},
	)
}

@(test)
ab_unknown_flag_is_an_error :: proc(t: ^testing.T) {
	argv, error := harness.ab_build_args([]string{"--bogus"}, context.allocator)
	defer delete(argv, context.allocator)
	if error == "" {
		testing.expectf(t, false, "the unknown flag was accepted")
		return
	}
	defer delete(error, context.allocator)
	testing.expectf(
		t,
		strings.contains(error, "unknown option"),
		"the error does not name the unknown option: %s",
		error,
	)
	testing.expect_value(t, harness.cli_ab([]string{"--bogus"}), harness.EXIT_SCENARIO)
}

@(test)
ab_flag_without_a_value_is_an_error :: proc(t: ^testing.T) {
	argv, error := harness.ab_build_args([]string{"--base"}, context.allocator)
	defer delete(argv, context.allocator)
	if error == "" {
		testing.expectf(t, false, "a missing value was accepted")
		return
	}
	defer delete(error, context.allocator)
	testing.expectf(
		t,
		strings.contains(error, "--base"),
		"the error does not name the flag: %s",
		error,
	)
}

@(test)
ab_help_is_recognized :: proc(t: ^testing.T) {
	ab_expect_args(t, []string{"-h"}, []string{"--help"})
	ab_expect_args(t, []string{"--help"}, []string{"--help"})
	testing.expect_value(t, harness.cli_ab([]string{"-h"}), harness.EXIT_OK)
}

@(private)
ab_expect_args :: proc(t: ^testing.T, args, expected: []string) {
	argv, error := harness.ab_build_args(args, context.allocator)
	defer delete(argv, context.allocator)
	if error != "" {
		defer delete(error, context.allocator)
		testing.expectf(t, false, "ab_build_args failed: %s", error)
		return
	}
	if len(argv) != len(expected) {
		testing.expectf(
			t,
			false,
			"ab_build_args returned %d arguments, expected %d",
			len(argv),
			len(expected),
		)
		return
	}
	for argument, index in expected {
		testing.expectf(
			t,
			argv[index] == argument,
			"argument %d is %q, expected %q",
			index,
			argv[index],
			argument,
		)
	}
}
