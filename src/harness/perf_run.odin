#+vet explicit-allocators
package harness

import "core:strings"
import "core:time"

import "src:game"
import "src:perf"

// The run owns its samples, so a window longer than the live ring is not
// clipped. Prime and warmup frames fill the swapchain, the timestamp slots, and
// the device clocks before the measured window starts.
session_perf :: proc(session: ^Session, command: Perf_Command) -> string {
	if session.hud.menu.open {
		return format_error("menu is open; close the menu to run perf")
	}
	// One trace per run keeps the trace file and the report aligned. A second
	// trace would overwrite the first one's samples.
	if session.has_trace && command.has_trace {
		return format_error("a run holds one perf trace; use a trace on one perf command")
	}
	session.perf_report = {}
	session.has_perf_report = false

	if frame_error := session_perf_frame(session); frame_error != "" {
		return frame_error
	}
	prime_start := time.tick_now()
	prime_frames: int
	if command.prime > 0 {
		for prime_frames < MAX_PERF_PRIME_FRAMES {
			elapsed := time.duration_seconds(time.tick_diff(prime_start, time.tick_now()))
			if elapsed >= command.prime {
				break
			}
			if frame_error := session_perf_frame(session); frame_error != "" {
				return frame_error
			}
			prime_frames += 1
			if session.quit {
				break
			}
		}
	}
	for _ in 0 ..< command.warmup {
		if frame_error := session_perf_frame(session); frame_error != "" {
			return frame_error
		}
		if session.quit {
			break
		}
	}

	samples := make([dynamic]perf.Sample, 0, command.frames, session.allocator)
	defer delete(samples)
	for _ in 0 ..< command.frames {
		if frame_error := session_perf_frame(session); frame_error != "" {
			return frame_error
		}
		if sample, ok := perf.last_sample(&session.perf); ok && sample.frame == session.perf.frame {
			append(&samples, sample)
		}
		if session.quit {
			break
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
	report: Perf_Report
	perf_report_fill(
		&report,
		summary,
		strings.clone(command.name, session.allocator),
		command.prime,
		prime_frames,
	)
	append(&session.perf_reports, report)
	session.perf_report = session.perf_reports[len(session.perf_reports) - 1]
	session.has_perf_report = true
	return ""
}

@(private)
session_perf_frame :: proc(session: ^Session) -> string {
	perf.begin_frame(&session.perf)
	perf.mark(&session.perf, .Events)
	input := session.input
	game.simulation_step(&session.sim, input, game.SIMULATION_STEP)
	session.input.jump_pressed = false
	session.frame += 1
	perf.mark(&session.perf, .Simulation)
	if session.backend != nil {
		if draw_error := session_draw(session, {}); draw_error != "" {
			return draw_error
		}
		perf.set_gpu(&session.perf, session.backend.gpu_times(session.backend.ctx))
	} else {
		perf.mark(&session.perf, .Build)
		perf.mark(&session.perf, .Record)
	}
	perf.mark(&session.perf, .Present)
	perf.end_frame(&session.perf)
	return ""
}
