#+vet explicit-allocators
#+vet !unused-procedures
package harness_test

import "core:encoding/json"
import "core:strings"
import "core:testing"

import "src:harness"

@(test)
perf_report_marshals_with_and_without_gpu :: proc(t: ^testing.T) {
	report := harness.Perf_Report {
		name          = "base",
		measured      = 1,
		warmup        = 0,
		prime_seconds = 2.0,
		prime_frames  = 12,
		interval      = {p50 = 16.6, p95 = 17.1, p99 = 17.2},
		cpu           = {events = {p50 = 0.1, p95 = 0.2, mean = 0.15}},
	}
	cpu_data, cpu_error := json.marshal(report, {}, context.allocator)
	defer delete(cpu_data, context.allocator)
	testing.expectf(t, cpu_error == nil, "CPU marshal failed: %v", cpu_error)
	testing.expect(t, strings.contains(string(cpu_data), `"prime_frames":12`), "prime frames are missing")
	testing.expect(t, !strings.contains(string(cpu_data), `"gpu"`), "CPU-only report has GPU fields")

	report.gpu = harness.Perf_Gpu_Report {
		tlas    = {p50 = 0.1, p95 = 0.1, mean = 0.1},
		depth   = {p50 = 0.4, p95 = 0.5, mean = 0.45},
		scene   = {p50 = 2.6, p95 = 2.7, mean = 2.65},
		taa     = {p50 = 0.2, p95 = 0.2, mean = 0.2},
		overlay = {p50 = 0.1, p95 = 0.1, mean = 0.1},
		total   = {p50 = 3.4, p95 = 3.5, mean = 3.45},
	}
	gpu_data, gpu_error := json.marshal(report, {}, context.allocator)
	defer delete(gpu_data, context.allocator)
	testing.expectf(t, gpu_error == nil, "GPU marshal failed: %v", gpu_error)
	testing.expect(t, strings.contains(string(gpu_data), `"depth"`), "depth pass is missing")

	warm := report
	warm.name = "warm"
	outer := harness.Report {
		perf = []harness.Perf_Report{report, warm},
	}
	outer_data, outer_error := json.marshal(outer, {}, context.allocator)
	defer delete(outer_data, context.allocator)
	testing.expectf(t, outer_error == nil, "outer marshal failed: %v", outer_error)
	text := string(outer_data)
	testing.expect(t, strings.contains(text, `"base"`), "the first perf name is missing")
	testing.expect(t, strings.contains(text, `"warm"`), "the second perf name is missing")
}
