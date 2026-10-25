#+vet explicit-allocators
package harness

import "core:mem"

Diff_Pair :: struct {
	name:             string `json:"name"`,
	width:            u32    `json:"width"`,
	height:           u32    `json:"height"`,
	different_pixels: int    `json:"different_pixels"`,
	max_delta:        u8     `json:"max_delta"`,
	mean_delta:       f32    `json:"mean_delta"`,
	over_16:          int    `json:"over_16"`,
	identical:        bool   `json:"identical"`,
}

Diff_Report :: struct {
	run_a:        string      `json:"run_a"`,
	run_b:        string      `json:"run_b"`,
	revision_a:   string      `json:"revision_a"`,
	dirty_a:      bool        `json:"dirty_a"`,
	scenario_a:   string      `json:"scenario_a"`,
	width_a:      u32         `json:"width_a,omitempty"`,
	height_a:     u32         `json:"height_a,omitempty"`,
	screenshots_a: int        `json:"screenshots_a,omitempty"`,
	revision_b:   string      `json:"revision_b"`,
	dirty_b:      bool        `json:"dirty_b"`,
	scenario_b:   string      `json:"scenario_b"`,
	width_b:      u32         `json:"width_b,omitempty"`,
	height_b:     u32         `json:"height_b,omitempty"`,
	screenshots_b: int        `json:"screenshots_b,omitempty"`,
	ok:           bool        `json:"ok"`,
	pairs:        []Diff_Pair `json:"pairs"`,
	errors:       []string    `json:"errors,omitempty"`,
}

Diff_Options :: struct {
	run_a:          string,
	run_b:          string,
	has_max_pixels: bool,
	max_pixels:     int,
	json:           bool,
}

diff_pair_build :: proc(name: string, first, second: []u8, width, height: u32) -> Diff_Pair {
	delta := capture_delta(first, second)
	return {
		name = name,
		width = width,
		height = height,
		different_pixels = delta.different,
		max_delta = delta.max,
		mean_delta = delta.mean,
		over_16 = delta.over_16,
		identical = delta.different == 0,
	}
}

diff_report_destroy :: proc(report: ^Diff_Report, allocator: mem.Allocator) {
	delete(report.run_a, allocator)
	delete(report.run_b, allocator)
	delete(report.revision_a, allocator)
	delete(report.scenario_a, allocator)
	delete(report.revision_b, allocator)
	delete(report.scenario_b, allocator)
	for pair in report.pairs {
		delete(pair.name, allocator)
	}
	delete(report.pairs, allocator)
	for message in report.errors {
		delete(message, allocator)
	}
	delete(report.errors, allocator)
	report^ = {}
}
