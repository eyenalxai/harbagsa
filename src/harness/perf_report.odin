#+vet explicit-allocators
package harness

import "core:mem"
import "core:strings"

import "src:perf"

Perf_Duration_Report :: struct {
	p50:  f64 `json:"p50"`,
	p95:  f64 `json:"p95"`,
	mean: f64 `json:"mean"`,
}

Perf_Interval_Report :: struct {
	p50:     f64 `json:"p50"`,
	p95:     f64 `json:"p95"`,
	p99:     f64 `json:"p99"`,
	minimum: f64 `json:"minimum"`,
	maximum: f64 `json:"maximum"`,
	mean:    f64 `json:"mean"`,
}

Perf_Cpu_Report :: struct {
	events:     Perf_Duration_Report `json:"events"`,
	simulation: Perf_Duration_Report `json:"simulation"`,
	build:      Perf_Duration_Report `json:"build"`,
	record:     Perf_Duration_Report `json:"record"`,
	present:    Perf_Duration_Report `json:"present"`,
}

Perf_Gpu_Report :: struct {
	tlas:    Perf_Duration_Report `json:"tlas"`,
	cluster: Perf_Duration_Report `json:"cluster"`,
	depth:   Perf_Duration_Report `json:"depth"`,
	scene:   Perf_Duration_Report `json:"scene"`,
	taa:     Perf_Duration_Report `json:"taa"`,
	overlay: Perf_Duration_Report `json:"overlay"`,
	total:   Perf_Duration_Report `json:"total"`,
}

Perf_Spread_Report :: struct {
	mean:    f64 `json:"mean"`,
	minimum: f64 `json:"minimum"`,
	maximum: f64 `json:"maximum"`,
	spread:  f64 `json:"spread"`,
}

Perf_Delta_Report :: struct {
	interval_rounds: []f64                   `json:"interval_rounds"`,
	interval_p50:  Perf_Spread_Report        `json:"interval_p50"`,
	gpu_rounds:    []f64                     `json:"gpu_rounds,omitempty"`,
	gpu_total_p50: Maybe(Perf_Spread_Report) `json:"gpu_total_p50,omitempty"`,
}

Perf_Variant_Report :: struct {
	name:     string                  `json:"name"`,
	baseline: bool                    `json:"baseline"`,
	measured: int                     `json:"measured"`,
	interval: Perf_Interval_Report    `json:"interval"`,
	cpu:      Perf_Cpu_Report         `json:"cpu"`,
	gpu:      Maybe(Perf_Gpu_Report)  `json:"gpu,omitempty"`,
	delta:    Maybe(Perf_Delta_Report) `json:"delta,omitempty"`,
}

Perf_Report :: struct {
	name:             string                `json:"name"`,
	measured:         int                   `json:"measured"`,
	warmup:           int                   `json:"warmup"`,
	prime_seconds:    f64                   `json:"prime_seconds"`,
	prime_frames:     int                   `json:"prime_frames"`,
	prime_once:       bool                  `json:"prime_once"`,
	spikes:           int                   `json:"spikes"`,
	rounds:           int                   `json:"rounds"`,
	discard:          int                   `json:"discard"`,
	discarded:        int                   `json:"discarded"`,
	baseline:         string                `json:"baseline,omitempty"`,
	variants:         []Perf_Variant_Report `json:"variants,omitempty"`,
	timestamp_period: Maybe(f64)           `json:"timestamp_period,omitempty"`,
	gpu_clock_start:  Perf_Clock            `json:"gpu_clock_start"`,
	gpu_clock_end:    Perf_Clock            `json:"gpu_clock_end"`,
	load_start:       Perf_Load             `json:"load_start"`,
	load_end:         Perf_Load             `json:"load_end"`,
	warnings:         []string              `json:"warnings,omitempty"`,
	interval:         Perf_Interval_Report  `json:"interval"`,
	cpu:              Perf_Cpu_Report       `json:"cpu"`,
	gpu:              Maybe(Perf_Gpu_Report) `json:"gpu,omitempty"`,
}

// One measured window in the order it ran. `first` and `count` index the run's
// sample list, so the report never copies a sample.
Perf_Window :: struct {
	order:   int,
	round:   int,
	variant: int,
	first:   int,
	count:   int,
	stats:   perf.Stats,
}

Perf_Report_Input :: struct {
	name:                 string,
	command:              Perf_Command,
	windows:              []Perf_Window,
	samples:              []perf.Sample,
	prime_frames:         int,
	timestamp_period:     Maybe(f64),
	clock_start:          Perf_Clock,
	clock_end:            Perf_Clock,
	load_start:           Perf_Load,
	load_end:             Perf_Load,
	warnings:             []string,
}

perf_report_build :: proc(input: Perf_Report_Input, allocator: mem.Allocator) -> Perf_Report {
	command := input.command
	discarded := min(command.discard, command.rounds - 1)
	report := Perf_Report {
		name             = input.name,
		warmup           = command.warmup,
		prime_seconds    = command.prime,
		prime_frames     = input.prime_frames,
		prime_once       = command.prime_once,
		rounds           = command.rounds,
		discard          = command.discard,
		discarded        = discarded,
		gpu_clock_start  = input.clock_start,
		gpu_clock_end    = input.clock_end,
		load_start       = input.load_start,
		load_end         = input.load_end,
	}
	if period, has := input.timestamp_period.?; has {
		report.timestamp_period = period
	}
	report.warnings = make([]string, len(input.warnings), allocator)
	copy(report.warnings, input.warnings)

	if len(command.variants) == 0 {
		samples := pooled_samples(input, -1, discarded, allocator)
		defer delete(samples, allocator)
		stats := perf.stats_from_samples(samples)
		perf_report_fill(&report, stats)
		return report
	}

	baseline := perf_baseline_index(command)
	report.baseline = strings.clone(command.variants[baseline].name, allocator)
	report.variants = make([]Perf_Variant_Report, len(command.variants), allocator)
	for variant, index in command.variants {
		samples := pooled_samples(input, index, discarded, allocator)
		stats := perf.stats_from_samples(samples)
		delete(samples, allocator)
		entry := &report.variants[index]
		entry.name = strings.clone(variant.name, allocator)
		entry.baseline = index == baseline
		entry.measured = stats.count
		perf_variant_fill(entry, stats)
	}
	for index in 0 ..< len(command.variants) {
		if index == baseline {
			continue
		}
		report.variants[index].delta = perf_delta_build(
			input,
			index,
			baseline,
			discarded,
			allocator,
		)
	}
	perf_report_fill(&report, pooled_stats(input, baseline, discarded, allocator))
	return report
}

@(private)
pooled_samples :: proc(
	input: Perf_Report_Input,
	variant, discard: int,
	allocator: mem.Allocator,
) -> []perf.Sample {
	samples := make([dynamic]perf.Sample, 0, len(input.samples), allocator)
	for window in input.windows {
		if window.round < discard || (variant >= 0 && window.variant != variant) {
			continue
		}
		append(&samples, ..input.samples[window.first:window.first + window.count])
	}
	return samples[:]
}

@(private)
pooled_stats :: proc(
	input: Perf_Report_Input,
	variant, discard: int,
	allocator: mem.Allocator,
) -> perf.Stats {
	samples := pooled_samples(input, variant, discard, allocator)
	defer delete(samples, allocator)
	return perf.stats_from_samples(samples)
}
