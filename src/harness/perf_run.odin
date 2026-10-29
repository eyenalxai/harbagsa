#+vet explicit-allocators
package harness

import "core:fmt"
import "core:strings"
import "core:time"

import "src:game"
import "src:perf"
import "src:renderer"

// The run owns its samples, so a window longer than the live ring is not
// clipped. Prime and warmup frames fill the swapchain, the timestamp slots, and
// the device clocks before the measured window starts.
session_perf :: proc(session: ^Session, command: Perf_Command) -> string {
	if session.hud.menu.open {
		return format_error("menu is open; close the menu to run perf")
	}
	// One trace per run keeps the trace file and the report aligned. A second
	// trace would overwrite the first one's samples.
	if session.perf.has_trace && command.has_trace {
		return format_error("a run holds one perf trace; use a trace on one perf command")
	}
	// The readback incident: a perf frame that still has a queued capture would
	// measure the readback of another command.
	if len(session.capture.pending) > 0 {
		return format_error("perf cannot run while a capture is pending")
	}
	if len(command.variants) > 0 && !renderer.RENDERER_DEBUG_ENABLED && !session.debug_renderer {
		return format_error(
			"perf variants need a build with ENABLE_RENDERER_DEBUG or the --debug-renderer flag",
		)
	}
	total_frames := command.frames * perf_slot_count(command) * command.rounds
	if total_frames > MAX_PERF_TOTAL_FRAMES {
		return format_error(
			"perf would measure %d frames; the limit is %d",
			total_frames,
			MAX_PERF_TOTAL_FRAMES,
		)
	}
	if frame_error := session_perf_frame(session); frame_error != "" {
		return frame_error
	}

	has_variants := len(command.variants) > 0
	base_debug: renderer.Renderer_Debug
	if has_variants {
		if session.render.backend == nil ||
		   session.render.backend.get_debug == nil ||
		   session.render.backend.set_debug == nil {
			return format_error("perf variants require a renderer that accepts debug state")
		}
		base_debug = session.render.backend.get_debug(session.render.backend.ctx)
		defer session_debug_set(session, base_debug)
	}

	device := ""
	if session.render.backend != nil && session.render.backend.setup != nil {
		device = session.render.backend.setup(session.render.backend.ctx).device
	}
	clock_start, clock_warning := gpu_clock_probe(session.allocator, device)
	load_start, load_warning := load_average_probe(session.allocator)
	warnings := make([dynamic]string, 0, 2, session.allocator)
	warnings_owned := false
	defer {
		if !warnings_owned {
			for warning in warnings {
				delete(warning, session.allocator)
			}
		}
		delete(warnings)
	}
	if clock_warning != "" {
		append(&warnings, clock_warning)
	}
	if load_warning != "" {
		append(&warnings, load_warning)
	}
	for warning in warnings {
		fmt.eprintf("perf %s: %s\n", command.name, warning)
	}

	slots := perf_slot_count(command)
	samples := make([dynamic]perf.Sample, 0, total_frames, session.allocator)
	defer delete(samples)
	windows := make([dynamic]Perf_Window, 0, slots * command.rounds, session.allocator)
	defer delete(windows)
	prime_frames := 0
	primed := false

	for round in 0 ..< command.rounds {
		for slot in 0 ..< slots {
			if session.quit {
				break
			}
			variant := perf_slot_variant(command, slot)
			if variant >= 0 {
				variant_state := command.variants[variant]
				session_debug_variant(
					session,
					base_debug,
					variant_state.patch,
					variant_state.reset,
				)
			}
			window, window_error := perf_window(
				session,
				command,
				round,
				variant,
				len(windows),
				&prime_frames,
				&primed,
				&samples,
			)
			if window_error != "" {
				return window_error
			}
			append(&windows, window)
		}
		if session.quit {
			break
		}
	}

	if len(samples) == 0 {
		return format_error("perf measured no frames")
	}
	if command.has_trace {
		perf_record_trace(session, command, samples[:])
	}

	clock_end, end_clock_warning := gpu_clock_probe(session.allocator, device)
	if end_clock_warning != "" {
		append(&warnings, end_clock_warning)
		fmt.eprintf("perf %s: %s\n", command.name, end_clock_warning)
	}
	load_end, end_load_warning := load_average_probe(session.allocator)
	if end_load_warning != "" {
		append(&warnings, end_load_warning)
		fmt.eprintf("perf %s: %s\n", command.name, end_load_warning)
	}

	timestamp_period: Maybe(f64)
	if period := session.render.report.timestamp_period; period > 0 {
		timestamp_period = f64(period)
	}
	report := perf_report_build(
		{
			name                 = strings.clone(command.name, session.allocator),
			command              = command,
			windows              = windows[:],
			samples              = samples[:],
			prime_frames         = prime_frames,
			timestamp_period     = timestamp_period,
			clock_start          = clock_start,
			clock_end            = clock_end,
			load_start           = load_start,
			load_end             = load_end,
			warnings             = warnings[:],
		},
		session.allocator,
	)
	append(&session.perf.reports, report)
	warnings_owned = true
	return ""
}

@(private)
perf_slot_count :: proc(command: Perf_Command) -> int {
	if len(command.variants) == 0 {
		return 1
	}
	return 1 + 2 * (len(command.variants) - 1)
}

// The round opens on the baseline, then every other variant with a baseline
// window after it, so each variant is bracketed by two baseline windows.
@(private)
perf_slot_variant :: proc(command: Perf_Command, slot: int) -> int {
	if len(command.variants) == 0 {
		return -1
	}
	baseline := perf_baseline_index(command)
	if slot == 0 {
		return baseline
	}
	if slot % 2 == 1 {
		wanted := (slot - 1) / 2
		seen := 0
		for variant in 0 ..< len(command.variants) {
			if variant == baseline {
				continue
			}
			if seen == wanted {
				return variant
			}
			seen += 1
		}
	}
	return baseline
}

@(private)
perf_window :: proc(
	session: ^Session,
	command: Perf_Command,
	round, variant, order: int,
	prime_frames: ^int,
	primed: ^bool,
	samples: ^[dynamic]perf.Sample,
) -> (Perf_Window, string) {
	if command.prime > 0 && (!command.prime_once || !primed^) {
		frames, prime_error := perf_prime(session, command.prime)
		prime_frames^ += frames
		primed^ = true
		if prime_error != "" {
			return {}, prime_error
		}
	}
	for _ in 0 ..< command.warmup {
		if session.quit {
			break
		}
		if frame_error := session_perf_frame(session); frame_error != "" {
			return {}, frame_error
		}
	}

	first := len(samples^)
	for _ in 0 ..< command.frames {
		if session.quit {
			break
		}
		if frame_error := session_perf_frame(session); frame_error != "" {
			return {}, frame_error
		}
		if sample, ok := perf.last_sample(&session.perf.state); ok && sample.frame == session.perf.state.frame {
			append(samples, sample)
		}
	}
	window := Perf_Window {
		order   = order,
		round   = round,
		variant = variant,
		first   = first,
		count   = len(samples^) - first,
	}
	if window.count > 0 {
		window.stats = perf.stats_from_samples(samples^[first:])
	}
	return window, ""
}

@(private)
perf_prime :: proc(session: ^Session, seconds: f64) -> (int, string) {
	start := time.tick_now()
	frames := 0
	for frames < MAX_PERF_PRIME_FRAMES {
		elapsed := time.duration_seconds(time.tick_diff(start, time.tick_now()))
		if elapsed >= seconds {
			break
		}
		if frame_error := session_perf_frame(session); frame_error != "" {
			return frames, frame_error
		}
		frames += 1
		if session.quit {
			break
		}
	}
	return frames, ""
}

@(private)
perf_record_trace :: proc(session: ^Session, command: Perf_Command, samples: []perf.Sample) {
	session.perf.trace_name = strings.clone(command.trace, session.allocator)
	session.perf.trace_samples = make([dynamic]perf.Sample, 0, len(samples), session.allocator)
	append(&session.perf.trace_samples, ..samples)
	session.perf.has_trace = true
	record := Trace_Record {
		name    = strings.clone(command.trace, session.allocator),
		samples = make([]perf.Sample, len(samples), session.allocator),
	}
	copy(record.samples, samples)
	append(&session.perf.traces, record)
}

@(private)
session_perf_frame :: proc(session: ^Session) -> string {
	if timeout := session_check_timeout(session); timeout != "" {
		return timeout
	}
	perf.begin_frame(&session.perf.state)
	perf.mark(&session.perf.state, .Events)
	input := session.input
	game.simulation_step(&session.sim, input, game.SIMULATION_STEP)
	session.input.jump_pressed = false
	session.input.sprint_pressed = false
	session.frame += 1
	perf.mark(&session.perf.state, .Simulation)
	if session.render.backend != nil {
		if draw_error := session_draw_group(session, nil); draw_error != "" {
			return draw_error
		}
		perf.set_gpu(&session.perf.state, session.render.backend.gpu_times(session.render.backend.ctx))
	} else {
		perf.mark(&session.perf.state, .Build)
		perf.mark(&session.perf.state, .Record)
	}
	perf.mark(&session.perf.state, .Present)
	perf.end_frame(&session.perf.state)
	return ""
}
