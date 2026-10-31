#+vet explicit-allocators
#+vet !unused-procedures // the statistics are called through the game loop
package perf

import "core:math"
import "core:slice"
import "core:time"

SPIKE_FACTOR :: 1.5

Distribution :: struct {
	p50:     f64,
	p95:     f64,
	p99:     f64,
	minimum: f64,
	maximum: f64,
	mean:    f64,
}

Gpu_Stats :: struct {
	available: bool,
	passes:    [Pass]Distribution,
	total:     Distribution,
	top:       Pass,
}

Stats :: struct {
	count:    int,
	interval: Distribution,
	cpu:      Distribution,
	phases:   [Phase]Distribution,
	gpu:      Gpu_Stats,
	spikes:   int,
}

SCRATCH_FLOATS_PER_SAMPLE :: 3 + PASS_COUNT + 1

stats_from_ring :: proc(ring: ^Ring) -> Stats {
	return stats_from_samples(ring.samples[:ring.count])
}

stats_from_samples :: proc(samples: []Sample) -> Stats {
	result: Stats
	count := len(samples)
	if count == 0 {
		return result
	}
	result.count = count

	// The live ring fits the stack buffer. A harness window can pool past the
	// ring, so a longer input borrows the heap instead of being clipped.
	stack: [RING_CAPACITY * SCRATCH_FLOATS_PER_SAMPLE]f64
	scratch: []f64
	heap_scratch: []f64
	defer if heap_scratch != nil {
		delete(heap_scratch, context.allocator)
	}
	if count <= RING_CAPACITY {
		scratch = stack[:count * SCRATCH_FLOATS_PER_SAMPLE]
	} else {
		scratch = make([]f64, count * SCRATCH_FLOATS_PER_SAMPLE, context.allocator)
		heap_scratch = scratch
	}
	intervals := scratch[0:count]
	cpus := scratch[count:2 * count]
	values := scratch[2 * count:3 * count]
	gpu_values := scratch[3 * count:3 * count + PASS_COUNT * count]
	gpu_totals := scratch[3 * count + PASS_COUNT * count:]

	for sample, index in samples {
		intervals[index] = milliseconds(sample.interval)
		cpus[index] = milliseconds(cpu_total(sample))
	}
	result.interval = distribution(intervals)
	result.cpu = distribution(cpus)

	for i in 0 ..< PHASE_COUNT {
		phase := Phase(i)
		for sample, index in samples {
			values[index] = milliseconds(sample.phases[phase])
		}
		result.phases[phase] = distribution(values)
	}

	gpu_count := 0
	for sample in samples {
		if !sample.gpu.available {
			continue
		}
		for i in 0 ..< PASS_COUNT {
			gpu_values[i * count + gpu_count] = milliseconds(sample.gpu.passes[Pass(i)])
		}
		gpu_totals[gpu_count] = milliseconds(sample.gpu.total)
		gpu_count += 1
	}
	if gpu_count > 0 {
		result.gpu.available = true
		for i in 0 ..< PASS_COUNT {
			result.gpu.passes[Pass(i)] = distribution(gpu_values[i * count:i * count + gpu_count])
		}
		result.gpu.total = distribution(gpu_totals[:gpu_count])

		top_mean: f64 = -1
		for i in 0 ..< PASS_COUNT {
			pass := Pass(i)
			if result.gpu.passes[pass].mean > top_mean {
				top_mean = result.gpu.passes[pass].mean
				result.gpu.top = pass
			}
		}
	}

	if result.interval.p50 > 0 {
		threshold := result.interval.p50 * SPIKE_FACTOR
		for value in intervals[:count] {
			if value > threshold {
				result.spikes += 1
			}
		}
	}
	return result
}

distribution :: proc(values: []f64) -> Distribution {
	if len(values) == 0 {
		return {}
	}
	slice.sort(values)

	sum: f64
	for value in values {
		sum += value
	}
	return {
		p50 = percentile(values, 50),
		p95 = percentile(values, 95),
		p99 = percentile(values, 99),
		minimum = values[0],
		maximum = values[len(values) - 1],
		mean = sum / f64(len(values)),
	}
}

// Nearest rank, so a percentile always reports a value a frame actually had.
percentile :: proc(sorted: []f64, percent: f64) -> f64 {
	if len(sorted) == 0 {
		return 0
	}
	rank := int(math.ceil(percent * f64(len(sorted)) / 100.0)) - 1
	return sorted[clamp(rank, 0, len(sorted) - 1)]
}

cpu_total :: proc(sample: Sample) -> time.Duration {
	total: time.Duration
	for i in 0 ..< PHASE_COUNT {
		total += sample.phases[Phase(i)]
	}
	return total
}

milliseconds :: proc(duration: time.Duration) -> f64 {
	return f64(time.duration_nanoseconds(duration)) / 1_000_000.0
}
