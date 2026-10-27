#+vet explicit-allocators
package harness

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
	probe:   Perf_Duration_Report `json:"probe"`,
	depth:   Perf_Duration_Report `json:"depth"`,
	scene:   Perf_Duration_Report `json:"scene"`,
	taa:     Perf_Duration_Report `json:"taa"`,
	overlay: Perf_Duration_Report `json:"overlay"`,
	total:   Perf_Duration_Report `json:"total"`,
}

Perf_Report :: struct {
	name:          string                   `json:"name"`,
	measured:      int                      `json:"measured"`,
	warmup:        int                      `json:"warmup"`,
	prime_seconds: f64                      `json:"prime_seconds"`,
	prime_frames:  int                      `json:"prime_frames"`,
	spikes:        int                      `json:"spikes"`,
	interval:      Perf_Interval_Report     `json:"interval"`,
	cpu:           Perf_Cpu_Report          `json:"cpu"`,
	gpu:           Maybe(Perf_Gpu_Report)   `json:"gpu,omitempty"`,
}

perf_report_fill :: proc(
	out: ^Perf_Report,
	summary: perf.Summary,
	name: string,
	prime_seconds: f64,
	prime_frames: int,
) {
	out^ = Perf_Report {
		name          = name,
		measured      = summary.measured,
		warmup        = summary.warmup,
		prime_seconds = prime_seconds,
		prime_frames  = prime_frames,
		spikes        = summary.stats.spikes,
		interval      = {
			p50     = summary.stats.interval.p50,
			p95     = summary.stats.interval.p95,
			p99     = summary.stats.interval.p99,
			minimum = summary.stats.interval.minimum,
			maximum = summary.stats.interval.maximum,
			mean    = summary.stats.interval.mean,
		},
		cpu = {
			events     = perf_duration(summary.stats.phases[.Events]),
			simulation = perf_duration(summary.stats.phases[.Simulation]),
			build      = perf_duration(summary.stats.phases[.Build]),
			record     = perf_duration(summary.stats.phases[.Record]),
			present    = perf_duration(summary.stats.phases[.Present]),
		},
	}
	if summary.stats.gpu.available {
		out.gpu = Perf_Gpu_Report {
			tlas    = perf_duration(summary.stats.gpu.passes[.Tlas]),
			cluster = perf_duration(summary.stats.gpu.passes[.Cluster]),
			probe   = perf_duration(summary.stats.gpu.passes[.Probe]),
			depth   = perf_duration(summary.stats.gpu.passes[.Depth]),
			scene   = perf_duration(summary.stats.gpu.passes[.Scene]),
			taa     = perf_duration(summary.stats.gpu.passes[.Taa]),
			overlay = perf_duration(summary.stats.gpu.passes[.Overlay]),
			total   = perf_duration(summary.stats.gpu.total),
		}
	}
}

@(private)
perf_duration :: proc(distribution: perf.Distribution) -> Perf_Duration_Report {
	return {p50 = distribution.p50, p95 = distribution.p95, mean = distribution.mean}
}
