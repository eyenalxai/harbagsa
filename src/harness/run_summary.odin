#+vet explicit-allocators
package harness

import "core:fmt"
import "core:mem"

verbose_summary_lines :: proc(report: Report, allocator: mem.Allocator) -> []string {
	capacity := 8 +
		len(report.screenshots) +
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
	append(&lines, fmt.aprintf("captures: %d", len(report.screenshots), allocator = allocator))
	for capture in report.screenshots {
		append(&lines, fmt.aprintf(
			"  %s frame %d %dx%d %s",
			capture.name,
			capture.frame,
			capture.width,
			capture.height,
			capture.path,
			allocator = allocator,
		))
	}
	append(&lines, fmt.aprintf("checks: %d", len(report.checks), allocator = allocator))
	for check in report.checks {
		status := check.ok ? "PASS" : "FAIL"
		tolerance := check_tolerance_note(check, allocator)
		if check.error != "" {
			append(&lines, fmt.aprintf(
				"  %s %s %s %s%s actual %s error %s",
				status,
				check.field,
				check.op,
				check.expected,
				tolerance,
				check.actual,
				check.error,
				allocator = allocator,
			))
			delete(tolerance, allocator)
			continue
		}
		append(&lines, fmt.aprintf(
			"  %s %s %s %s%s actual %s",
			status,
			check.field,
			check.op,
			check.expected,
			tolerance,
			check.actual,
			allocator = allocator,
		))
		delete(tolerance, allocator)
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
