#+vet explicit-allocators
package harness

import "core:strings"

import "src:game"
import "src:perf"

Perf_Interval_Report :: struct {
	p50:     f64 `json:"p50"`,
	p95:     f64 `json:"p95"`,
	p99:     f64 `json:"p99"`,
	minimum: f64 `json:"minimum"`,
	maximum: f64 `json:"maximum"`,
	mean:    f64 `json:"mean"`,
}

Perf_Cpu_Report :: struct {
	events:     f64 `json:"events"`,
	simulation: f64 `json:"simulation"`,
	build:      f64 `json:"build"`,
	record:     f64 `json:"record"`,
	present:    f64 `json:"present"`,
}

Perf_Gpu_Report :: struct {
	tlas:    f64 `json:"tlas"`,
	scene:   f64 `json:"scene"`,
	taa:     f64 `json:"taa"`,
	overlay: f64 `json:"overlay"`,
	total:   f64 `json:"total"`,
}

Perf_Report :: struct {
	measured: int                    `json:"measured"`,
	warmup:   int                    `json:"warmup"`,
	spikes:   int                    `json:"spikes"`,
	interval: Perf_Interval_Report   `json:"interval"`,
	cpu:      Perf_Cpu_Report        `json:"cpu"`,
	gpu:      Maybe(Perf_Gpu_Report) `json:"gpu,omitempty"`,
}

// The run owns its samples, so a window longer than the live ring is not
// clipped. The warmup frames fill the swapchain and the timestamp slots.
session_perf :: proc(session: ^Session, command: Perf_Command) -> string {
	if session.hud.menu.open {
		return format_error("menu is open; close the menu to run perf")
	}
	session.perf_report = {}
	session.has_perf_report = false
	if session.has_trace {
		delete(session.trace_name, session.allocator)
		delete(session.trace_path, session.allocator)
		delete(session.trace_samples)
		session.trace_name = ""
		session.trace_path = ""
		session.trace_samples = nil
		session.has_trace = false
	}

	samples := make([dynamic]perf.Sample, 0, command.frames, session.allocator)
	defer delete(samples)

	// One priming frame always runs. Its sample is dropped because it has no
	// previous frame, so every measured frame has a real interval.
	total := command.warmup + command.frames + 1
	for index in 0 ..< total {
		perf.begin_frame(&session.perf)
		perf.mark(&session.perf, .Events)
		input := session.input
		game.simulation_step(&session.sim, input, game.SIMULATION_STEP)
		session.input.jump_pressed = false
		session.frame += 1
		perf.mark(&session.perf, .Simulation)
		if session.backend != nil {
			draw_error := session_draw(session, {})
			if draw_error != "" {
				return draw_error
			}
			perf.set_gpu(&session.perf, session.backend.gpu_times(session.backend.ctx))
		} else {
			perf.mark(&session.perf, .Build)
			perf.mark(&session.perf, .Record)
		}
		perf.mark(&session.perf, .Present)
		perf.end_frame(&session.perf)
		if session.quit {
			break
		}
		if index > command.warmup {
			if sample, ok := perf.last_sample(&session.perf); ok &&
			   sample.frame == session.perf.frame {
				append(&samples, sample)
			}
		}
	}

	if len(samples) == 0 {
		return format_error("perf measured no frames")
	}
	if command.has_trace {
		session.trace_name = strings.clone(command.trace, session.allocator)
		session.trace_samples = make([dynamic]perf.Sample, 0, len(samples), session.allocator)
		append(&session.trace_samples, ..samples[:])
		session.has_trace = true
	}
	summary := perf.Summary {
		measured = len(samples),
		warmup   = command.warmup,
		stats    = perf.stats_from_samples(samples[:]),
	}
	session.perf_report = {}
	perf_report_fill(&session.perf_report, summary)
	session.has_perf_report = true
	return ""
}

perf_report_fill :: proc(out: ^Perf_Report, summary: perf.Summary) {
	out^ = Perf_Report {
		measured = summary.measured,
		warmup   = summary.warmup,
		spikes   = summary.stats.spikes,
		interval = {
			p50     = summary.stats.interval.p50,
			p95     = summary.stats.interval.p95,
			p99     = summary.stats.interval.p99,
			minimum = summary.stats.interval.minimum,
			maximum = summary.stats.interval.maximum,
			mean    = summary.stats.interval.mean,
		},
		cpu = {
			events     = summary.stats.phases[.Events].mean,
			simulation = summary.stats.phases[.Simulation].mean,
			build      = summary.stats.phases[.Build].mean,
			record     = summary.stats.phases[.Record].mean,
			present    = summary.stats.phases[.Present].mean,
		},
	}
	if summary.stats.gpu.available {
		out.gpu = Perf_Gpu_Report {
			tlas    = summary.stats.gpu.passes[.Tlas].mean,
			scene   = summary.stats.gpu.passes[.Scene].mean,
			taa     = summary.stats.gpu.passes[.Taa].mean,
			overlay = summary.stats.gpu.passes[.Overlay].mean,
			total   = summary.stats.gpu.total.mean,
		}
	}
}
