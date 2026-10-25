#+vet explicit-allocators
package harness

import "core:fmt"
import "core:mem"

verbose_summary_lines :: proc(report: Report, allocator: mem.Allocator) -> []string {
	capacity := 8 +
		len(report.captures) +
		len(report.checks) +
		len(report.failures) +
		len(report.perf)
	lines := make([dynamic]string, 0, capacity, allocator)
	append(&lines, fmt.aprintf("run: %s", report.scenario.path, allocator = allocator))
	append(&lines, fmt.aprintf(
		"setup: revision %s dirty %v target %s %dx%d",
		report.setup.revision,
		report.setup.dirty,
		report.setup.target,
		report.setup.width,
		report.setup.height,
		allocator = allocator,
	))
	append(&lines, fmt.aprintf("captures: %d", len(report.captures), allocator = allocator))
	for capture in report.captures {
		append(&lines, capture_line(capture, allocator))
	}
	append(&lines, fmt.aprintf("checks: %d", len(report.checks), allocator = allocator))
	for check in report.checks {
		append(&lines, check_line(check, allocator))
	}
	append(&lines, fmt.aprintf("failures: %d", len(report.failures), allocator = allocator))
	for failure in report.failures {
		append(&lines, fmt.aprintf("  %s", failure, allocator = allocator))
	}
	append(&lines, fmt.aprintf("perf: %d", len(report.perf), allocator = allocator))
	for perf in report.perf {
		append(&lines, fmt.aprintf(
			"  %s measured %d warmup %d prime %d frames interval p50 %.3f p95 %.3f mean %.3f spikes %d",
			perf.name,
			perf.measured,
			perf.warmup,
			perf.prime_frames,
			perf.interval.p50,
			perf.interval.p95,
			perf.interval.mean,
			perf.spikes,
			allocator = allocator,
		))
	}
	return lines[:]
}

summary_lines :: proc(report: Report, allocator: mem.Allocator) -> []string {
	lines := make([dynamic]string, 0, 4 + len(report.captures) + len(report.checks), allocator)
	append(&lines, fmt.aprintf("run: %s", report.scenario.path, allocator = allocator))
	status := report.ok ? "ok" : "failed"
	append(&lines, fmt.aprintf("result: %s (exit %d)", status, report.exit_code, allocator = allocator))
	append(&lines, fmt.aprintf("captures: %d", len(report.captures), allocator = allocator))
	for capture in report.captures {
		append(&lines, capture_line(capture, allocator))
	}
	failed := 0
	for check in report.checks {
		if !check.ok {
			failed += 1
		}
	}
	append(&lines, fmt.aprintf(
		"checks: %d, failed: %d",
		len(report.checks),
		failed,
		allocator = allocator,
	))
	for check in report.checks {
		append(&lines, check_line(check, allocator))
	}
	for failure in report.failures {
		append(&lines, fmt.aprintf("  failure %s", failure, allocator = allocator))
	}
	if report.error != "" {
		append(&lines, fmt.aprintf("  error %s", report.error, allocator = allocator))
	}
	return lines[:]
}

@(private)
capture_line :: proc(capture: Capture_Result, allocator: mem.Allocator) -> string {
	path := capture.path == "" ? "-" : capture.path
	return fmt.aprintf(
		"  %-24s %-10s %-7s png %-3s %s",
		capture.name,
		capture.target,
		capture.format,
		capture_has_png(capture) ? "yes" : "no",
		path,
		allocator = allocator,
	)
}

@(private)
check_line :: proc(check: Check_Result, allocator: mem.Allocator) -> string {
	status := check.ok ? "PASS" : "FAIL"
	tolerance := check_tolerance_note(check, allocator)
	defer delete(tolerance, allocator)
	if check.error != "" {
		return fmt.aprintf(
			"  %s %s %s %s%s actual %s error %s",
			status,
			check.field,
			check.op,
			check.expected,
			tolerance,
			check.actual,
			check.error,
			allocator = allocator,
		)
	}
	return fmt.aprintf(
		"  %s %s %s %s%s actual %s",
		status,
		check.field,
		check.op,
		check.expected,
		tolerance,
		check.actual,
		allocator = allocator,
	)
}

verbose_summary_destroy :: proc(lines: []string, allocator: mem.Allocator) {
	for line in lines {
		delete(line, allocator)
	}
	delete(lines, allocator)
}

print_verbose_summary :: proc(report: Report) {
	lines := verbose_summary_lines(report, context.allocator)
	defer verbose_summary_destroy(lines, context.allocator)
	for line in lines {
		fmt.eprintln(line)
	}
}

print_compact_summary :: proc(report: Report) {
	lines := summary_lines(report, context.allocator)
	defer verbose_summary_destroy(lines, context.allocator)
	for line in lines {
		fmt.eprintln(line)
	}
}
