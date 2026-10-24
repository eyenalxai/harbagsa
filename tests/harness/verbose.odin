#+vet explicit-allocators
#+vet !unused-procedures
package harness_test

import "core:strings"
import "core:testing"

import "src:harness"

@(test)
verbose_summary_lists_captures_checks_failures_and_perf :: proc(t: ^testing.T) {
	report := harness.Report {
		scenario = {path = "scenarios/smoke.json", hash = "0123456789abcdef"},
		setup = {
			revision = "abc1234",
			dirty = true,
			target = "offscreen",
			width = 1280,
			height = 720,
		},
		screenshots = []harness.Capture_Result {
			{name = "frame_0090", frame = 90, width = 1280, height = 720, path = "/tmp/frame_0090.png"},
		},
		checks = []harness.Check_Result {
			{field = "crates.0.position.z", op = "lt", expected = "7.5", actual = "3.2", ok = true},
		},
		failures = []string{"the backend failed"},
		perf = []harness.Perf_Report {
			{
				name = "arena",
				measured = 120,
				warmup = 60,
				prime_frames = 12,
				interval = {p50 = 16.6, p95 = 17.1, mean = 16.7},
			},
		},
	}
	lines := harness.verbose_summary_lines(report, context.allocator)
	defer harness.verbose_summary_destroy(lines, context.allocator)
	text := strings.join(lines, "\n", context.allocator)
	defer delete(text, context.allocator)

	expectations := []string {
		"revision abc1234",
		"dirty true",
		"frame_0090",
		"PASS crates.0.position.z",
		"the backend failed",
		"arena measured 120",
	}
	for expectation in expectations {
		testing.expectf(
			t,
			strings.contains(text, expectation),
			"the summary is missing %q:\n%s",
			expectation,
			text,
		)
	}
}
