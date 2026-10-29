#+vet explicit-allocators
package harness

import "core:mem"

import "src:perf"

@(private)
perf_delta_build :: proc(
	input: Perf_Report_Input,
	variant, baseline, discard: int,
	allocator: mem.Allocator,
) -> Maybe(Perf_Delta_Report) {
	interval_deltas := make([dynamic]f64, 0, input.command.rounds, context.temp_allocator)
	defer delete(interval_deltas)
	gpu_deltas := make([dynamic]f64, 0, input.command.rounds, context.temp_allocator)
	defer delete(gpu_deltas)

	for round in discard ..< input.command.rounds {
		window, found := perf_round_window(input.windows, round, variant)
		if !found {
			continue
		}
		before, has_before := perf_bracket_window(
			input.windows,
			round,
			window.order,
			baseline,
			-1,
		)
		after, has_after := perf_bracket_window(
			input.windows,
			round,
			window.order,
			baseline,
			1,
		)
		interval_bracket, has_interval := perf_bracket_value(before, has_before, after, has_after, false)
		if has_interval {
			append(&interval_deltas, window.stats.interval.p50 - interval_bracket)
		}
		gpu_bracket, has_gpu := perf_bracket_value(before, has_before, after, has_after, true)
		if has_gpu && window.stats.gpu.available {
			append(&gpu_deltas, window.stats.gpu.total.p50 - gpu_bracket)
		}
	}
	if len(interval_deltas) == 0 {
		return nil
	}
	delta := Perf_Delta_Report {
		interval_rounds = make([]f64, len(interval_deltas), allocator),
		interval_p50  = perf_spread(interval_deltas[:]),
	}
	copy(delta.interval_rounds, interval_deltas[:])
	if len(gpu_deltas) > 0 {
		delta.gpu_rounds = make([]f64, len(gpu_deltas), allocator)
		copy(delta.gpu_rounds, gpu_deltas[:])
		delta.gpu_total_p50 = perf_spread(gpu_deltas[:])
	}
	return delta
}

@(private)
perf_round_window :: proc(
	windows: []Perf_Window,
	round, variant: int,
) -> (Perf_Window, bool) {
	for window in windows {
		if window.round == round && window.variant == variant {
			return window, true
		}
	}
	return {}, false
}

@(private)
perf_bracket_window :: proc(
	windows: []Perf_Window,
	round, order, baseline, direction: int,
) -> (Perf_Window, bool) {
	best: Perf_Window
	found := false
	for window in windows {
		if window.round != round || window.variant != baseline {
			continue
		}
		if direction < 0 && window.order < order && (!found || window.order > best.order) {
			best = window
			found = true
		}
		if direction > 0 && window.order > order && (!found || window.order < best.order) {
			best = window
			found = true
		}
	}
	return best, found
}

@(private)
perf_bracket_value :: proc(
	before: Perf_Window,
	has_before: bool,
	after: Perf_Window,
	has_after: bool,
	gpu: bool,
) -> (f64, bool) {
	if gpu {
		sum: f64
		count := 0
		if has_before && before.stats.gpu.available {
			sum += before.stats.gpu.total.p50
			count += 1
		}
		if has_after && after.stats.gpu.available {
			sum += after.stats.gpu.total.p50
			count += 1
		}
		if count == 0 {
			return 0, false
		}
		return sum / f64(count), true
	}
	switch {
	case has_before && has_after:
		return (before.stats.interval.p50 + after.stats.interval.p50) * 0.5, true
	case has_before:
		return before.stats.interval.p50, true
	case has_after:
		return after.stats.interval.p50, true
	}
	return 0, false
}

@(private)
perf_spread :: proc(values: []f64) -> Perf_Spread_Report {
	if len(values) == 0 {
		return {}
	}
	minimum := values[0]
	maximum := values[0]
	sum: f64
	for value in values {
		sum += value
		minimum = min(minimum, value)
		maximum = max(maximum, value)
	}
	return {
		mean    = sum / f64(len(values)),
		minimum = minimum,
		maximum = maximum,
		spread  = maximum - minimum,
	}
}

@(private)
perf_report_fill :: proc(target: ^Perf_Report, stats: perf.Stats) {
	target.measured = stats.count
	target.spikes = stats.spikes
	perf_interval_fill(&target.interval, stats.interval)
	perf_cpu_fill(&target.cpu, stats)
	if stats.gpu.available {
		target.gpu = perf_gpu_report(stats)
	}
}

@(private)
perf_variant_fill :: proc(target: ^Perf_Variant_Report, stats: perf.Stats) {
	perf_interval_fill(&target.interval, stats.interval)
	perf_cpu_fill(&target.cpu, stats)
	if stats.gpu.available {
		target.gpu = perf_gpu_report(stats)
	}
}

@(private)
perf_interval_fill :: proc(target: ^Perf_Interval_Report, distribution: perf.Distribution) {
	target^ = {
		p50     = distribution.p50,
		p95     = distribution.p95,
		p99     = distribution.p99,
		minimum = distribution.minimum,
		maximum = distribution.maximum,
		mean    = distribution.mean,
	}
}

@(private)
perf_cpu_fill :: proc(out: ^Perf_Cpu_Report, stats: perf.Stats) {
	out^ = {
		events     = perf_duration(stats.phases[.Events]),
		simulation = perf_duration(stats.phases[.Simulation]),
		build      = perf_duration(stats.phases[.Build]),
		record     = perf_duration(stats.phases[.Record]),
		present    = perf_duration(stats.phases[.Present]),
	}
}

@(private)
perf_gpu_report :: proc(stats: perf.Stats) -> Perf_Gpu_Report {
	return {
		tlas    = perf_duration(stats.gpu.passes[.Tlas]),
		cluster = perf_duration(stats.gpu.passes[.Cluster]),
		depth   = perf_duration(stats.gpu.passes[.Depth]),
		scene   = perf_duration(stats.gpu.passes[.Scene]),
		taa     = perf_duration(stats.gpu.passes[.Taa]),
		overlay = perf_duration(stats.gpu.passes[.Overlay]),
		total   = perf_duration(stats.gpu.total),
	}
}

perf_report_destroy :: proc(report: ^Perf_Report, allocator: mem.Allocator) {
	if report.name != "" {
		delete(report.name, allocator)
	}
	if report.baseline != "" {
		delete(report.baseline, allocator)
	}
	for &variant in report.variants {
		if variant.name != "" {
			delete(variant.name, allocator)
		}
		if delta, has := variant.delta.?; has {
			delete(delta.interval_rounds, allocator)
			delete(delta.gpu_rounds, allocator)
		}
	}
	delete(report.variants, allocator)
	for warning in report.warnings {
		delete(warning, allocator)
	}
	delete(report.warnings, allocator)
	report^ = {}
}

@(private)
perf_duration :: proc(distribution: perf.Distribution) -> Perf_Duration_Report {
	return {p50 = distribution.p50, p95 = distribution.p95, mean = distribution.mean}
}
