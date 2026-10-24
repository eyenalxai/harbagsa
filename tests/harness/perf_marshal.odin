#+vet explicit-allocators
#+vet !unused-procedures
package harness_test

import "core:encoding/json"
import "core:testing"

import "src:harness"

@(test)
perf_report_marshals_with_and_without_gpu :: proc(t: ^testing.T) {
	report := harness.Perf_Report {
		measured = 1,
		warmup   = 0,
		interval = {p50 = 16.6, p95 = 17.1, p99 = 17.2},
		cpu      = {events = 0.1, simulation = 0.2},
	}
	cpu_data, cpu_error := json.marshal(report, {}, context.allocator)
	defer delete(cpu_data, context.allocator)
	testing.expectf(t, cpu_error == nil, "CPU marshal failed: %v", cpu_error)

	report.gpu = harness.Perf_Gpu_Report {
		tlas  = 0.1,
		scene = 2.7,
		taa   = 0.2,
		total = 3.0,
	}
	gpu_data, gpu_error := json.marshal(report, {}, context.allocator)
	defer delete(gpu_data, context.allocator)
	testing.expectf(t, gpu_error == nil, "GPU marshal failed: %v", gpu_error)

	outer := harness.Report {
		perf = report,
	}
	outer_data, outer_error := json.marshal(outer, {}, context.allocator)
	defer delete(outer_data, context.allocator)
	testing.expectf(t, outer_error == nil, "outer marshal failed: %v", outer_error)
}
