#+vet explicit-allocators
#+vet !unused-procedures // @(test) procs are called by the test runner, not by name
package perf_test

import "core:strings"
import "core:testing"
import "core:time"

import "src:perf"

@(test)
ring_wraps :: proc(t: ^testing.T) {
	ring: perf.Ring
	for index in 0 ..< perf.RING_CAPACITY + 1 {
		perf.ring_push(&ring, {frame = u64(index)})
	}
	testing.expect_value(t, ring.count, perf.RING_CAPACITY)
	testing.expect_value(t, ring.next, 1)
	testing.expect_value(t, ring.samples[0].frame, u64(perf.RING_CAPACITY))
	testing.expect_value(t, ring.samples[1].frame, u64(1))
}

@(test)
percentiles_use_real_values :: proc(t: ^testing.T) {
	samples := [4]perf.Sample {
		make_sample(10, 1, 1, 1, 1, 1),
		make_sample(20, 1, 1, 1, 1, 1),
		make_sample(30, 1, 1, 1, 1, 3),
		make_sample(40, 1, 1, 1, 1, 1),
	}
	stats := perf.stats_from_samples(samples[:])
	testing.expect_value(t, stats.count, 4)
	expect_near(t, stats.interval.p50, 20, "p50")
	expect_near(t, stats.interval.p95, 40, "p95")
	expect_near(t, stats.interval.p99, 40, "p99")
	expect_near(t, stats.interval.minimum, 10, "minimum")
	expect_near(t, stats.interval.maximum, 40, "maximum")
	expect_near(t, stats.interval.mean, 25, "mean")
	expect_near(t, stats.cpu.mean, 5.5, "cpu mean")
}

@(test)
percentiles_cover_one_and_odd_counts :: proc(t: ^testing.T) {
	one := [1]perf.Sample{make_sample(16, 1, 1, 1, 1, 1)}
	single := perf.stats_from_samples(one[:])
	testing.expect_value(t, single.count, 1)
	expect_near(t, single.interval.p50, 16, "single p50")
	expect_near(t, single.interval.p99, 16, "single p99")

	odd := [3]perf.Sample {
		make_sample(10, 1, 1, 1, 1, 1),
		make_sample(20, 1, 1, 1, 1, 1),
		make_sample(30, 1, 1, 1, 1, 1),
	}
	stats := perf.stats_from_samples(odd[:])
	expect_near(t, stats.interval.p50, 20, "odd p50")
	expect_near(t, stats.interval.p95, 30, "odd p95")
}

@(test)
spikes_count_frames_above_the_median :: proc(t: ^testing.T) {
	samples := [4]perf.Sample {
		make_sample(10, 1, 1, 1, 1, 1),
		make_sample(20, 1, 1, 1, 1, 1),
		make_sample(30, 1, 1, 1, 1, 1),
		make_sample(40, 1, 1, 1, 1, 1),
	}
	stats := perf.stats_from_samples(samples[:])
	testing.expect_value(t, stats.spikes, 1)
}

@(test)
gpu_stats_aggregate_available_samples :: proc(t: ^testing.T) {
	with_gpu := make_sample(16, 1, 1, 1, 1, 1)
	with_gpu.gpu.available = true
	with_gpu.gpu.passes[.Tlas] = 1 * time.Millisecond
	with_gpu.gpu.passes[.Depth] = 1 * time.Millisecond
	with_gpu.gpu.passes[.Scene] = 4 * time.Millisecond
	with_gpu.gpu.passes[.Taa] = 2 * time.Millisecond
	with_gpu.gpu.passes[.Overlay] = 1 * time.Millisecond
	with_gpu.gpu.total = 9 * time.Millisecond

	samples := [2]perf.Sample{with_gpu, make_sample(16, 1, 1, 1, 1, 1)}
	stats := perf.stats_from_samples(samples[:])
	testing.expect(t, stats.gpu.available, "GPU stats are missing")
	expect_near(t, stats.gpu.passes[.Depth].mean, 1, "depth mean")
	expect_near(t, stats.gpu.passes[.Scene].mean, 4, "scene mean")
	expect_near(t, stats.gpu.total.mean, 9, "gpu total")
	testing.expect_value(t, stats.gpu.top, perf.Pass.Scene)
}

@(test)
gpu_fields_appear_in_the_overlay_text :: proc(t: ^testing.T) {
	summary := perf.Stats {
		count    = 1,
		interval = {mean = 16.6667, p95 = 17.1},
		cpu      = {mean = 0.42},
	}
	summary.gpu.available = true
	summary.gpu.passes[.Depth] = perf.Distribution{mean = 0.30}
	summary.gpu.passes[.Scene] = perf.Distribution{mean = 2.70}
	summary.gpu.total = perf.Distribution{mean = 3.10}
	summary.gpu.top = .Scene

	buffer: [96]u8
	line := perf.format_summary(buffer[:], summary)
	testing.expect(t, len(line) > 0 && len(line) < len(buffer), "summary did not fit")
	testing.expect(t, strings.contains(line, "gpu"), "summary has no GPU total")

	pass_line := perf.format_passes(buffer[:], summary)
	testing.expect(t, strings.contains(pass_line, "depth"), "pass line has no depth entry")
	testing.expect(t, strings.contains(pass_line, "scene"), "pass line has no scene entry")
	testing.expect(t, len(pass_line) < len(buffer), "pass line did not fit")
	testing.expect_value(t, perf.format_passes(buffer[:], perf.Stats{}), "gpu --")
}

@(test)
empty_samples_have_no_stats :: proc(t: ^testing.T) {
	stats := perf.stats_from_samples(nil)
	testing.expect_value(t, stats.count, 0)
	buffer: [16]u8
	line := perf.format_summary(buffer[:], stats)
	testing.expect_value(t, line, "perf --")
}

@(test)
format_never_overflows_the_line :: proc(t: ^testing.T) {
	stats := perf.Stats {
		count = 1,
		interval = {mean = 16.6667, p95 = 17.1},
		cpu = {mean = 0.42},
	}
	full: [96]u8
	line := perf.format_summary(full[:], stats)
	testing.expect(t, len(line) > 0 && len(line) < len(full), "summary did not fit")

	short: [8]u8
	clipped := perf.format_summary(short[:], stats)
	testing.expect(t, len(clipped) <= len(short), "summary overflowed a short buffer")
}

@(test)
complete_marks_make_one_sample :: proc(t: ^testing.T) {
	state: perf.State
	perf.begin_frame(&state)
	mark_remaining(&state)
	perf.end_frame(&state)
	testing.expect_value(t, state.ring.count, 0)

	perf.begin_frame(&state)
	mark_remaining(&state)
	perf.end_frame(&state)
	testing.expect_value(t, state.ring.count, 1)
	testing.expect(t, state.ring.samples[0].interval > 0, "interval was not measured")
}

@(test)
a_missing_mark_drops_the_sample :: proc(t: ^testing.T) {
	state: perf.State
	perf.begin_frame(&state)
	perf.mark(&state, .Events)
	perf.mark(&state, .Simulation)
	perf.mark(&state, .Build)
	perf.end_frame(&state)
	testing.expect_value(t, state.ring.count, 0)
}

@(test)
out_of_order_marks_drop_the_sample :: proc(t: ^testing.T) {
	state: perf.State
	perf.begin_frame(&state)
	mark_remaining(&state)
	perf.end_frame(&state)

	perf.begin_frame(&state)
	perf.mark(&state, .Present)
	perf.mark(&state, .Events)
	perf.mark(&state, .Simulation)
	perf.mark(&state, .Build)
	perf.mark(&state, .Record)
	perf.end_frame(&state)
	testing.expect_value(t, state.ring.count, 0)
}

@(private)
mark_remaining :: proc(state: ^perf.State) {
	perf.mark(state, .Events)
	perf.mark(state, .Simulation)
	perf.mark(state, .Build)
	perf.mark(state, .Record)
	perf.mark(state, .Present)
}

@(private)
make_sample :: proc(
	interval_ms, events_ms, simulation_ms, build_ms, record_ms, present_ms: int,
) -> perf.Sample {
	sample := perf.Sample {
		interval = time.Duration(interval_ms) * time.Millisecond,
	}
	sample.phases[.Events] = time.Duration(events_ms) * time.Millisecond
	sample.phases[.Simulation] = time.Duration(simulation_ms) * time.Millisecond
	sample.phases[.Build] = time.Duration(build_ms) * time.Millisecond
	sample.phases[.Record] = time.Duration(record_ms) * time.Millisecond
	sample.phases[.Present] = time.Duration(present_ms) * time.Millisecond
	return sample
}

@(private)
expect_near :: proc(t: ^testing.T, actual, expected: f64, what: string) {
	testing.expectf(
		t,
		actual >= expected - 0.001 && actual <= expected + 0.001,
		"%s: got %v, want %v",
		what,
		actual,
		expected,
	)
}
