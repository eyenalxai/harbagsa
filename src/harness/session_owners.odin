#+vet explicit-allocators
package harness

import "core:mem"

import "src:digest"
import "src:perf"
import "src:renderer"

Pending_Capture :: struct {
	frame:    int,
	requests: []Capture_Request,
}

pending_capture_destroy :: proc(pending: ^Pending_Capture, allocator: mem.Allocator) {
	for request in pending.requests {
		if request.name != "" {
			delete(request.name, allocator)
		}
		if request.note != "" {
			delete(request.note, allocator)
		}
	}
	delete(pending.requests, allocator)
	pending^ = {}
}

Capture_Run :: struct {
	pending:  [dynamic]Pending_Capture,
	captures: [dynamic]Capture_Result,
}

capture_run_create :: proc(allocator: mem.Allocator) -> Capture_Run {
	return {
		pending = make([dynamic]Pending_Capture, 0, 8, allocator),
		captures = make([dynamic]Capture_Result, 0, 8, allocator),
	}
}

capture_run_destroy :: proc(run: ^Capture_Run, allocator: mem.Allocator) {
	capture_run_clear_pending(run, allocator)
	delete(run.pending)
	for &capture in run.captures {
		capture_result_destroy(&capture, allocator)
	}
	delete(run.captures)
	run^ = {}
}

capture_run_clear_pending :: proc(run: ^Capture_Run, allocator: mem.Allocator) {
	for &pending in run.pending {
		pending_capture_destroy(&pending, allocator)
	}
	clear(&run.pending)
}

Recorder :: struct {
	recording:               bool,
	path:                    string,
	start_frame:             int,
	recorded:                [dynamic]string,
	recorded_renderer_debug: bool,
}

recorder_create :: proc(allocator: mem.Allocator) -> Recorder {
	return {recorded = make([dynamic]string, 0, 16, allocator)}
}

recorder_clear :: proc(recorder: ^Recorder, allocator: mem.Allocator) {
	for line in recorder.recorded {
		delete(line, allocator)
	}
	clear(&recorder.recorded)
	if recorder.path != "" {
		delete(recorder.path, allocator)
	}
	recorder.recording = false
	recorder.path = ""
	recorder.start_frame = 0
	recorder.recorded_renderer_debug = false
}

recorder_destroy :: proc(recorder: ^Recorder, allocator: mem.Allocator) {
	recorder_clear(recorder, allocator)
	delete(recorder.recorded)
}

Trace_Record :: struct {
	name:    string,
	samples: []perf.Sample,
}

Perf_Run :: struct {
	state:         perf.State,
	reports:       [dynamic]Perf_Report,
	trace_name:    string,
	trace_samples: [dynamic]perf.Sample,
	trace_path:    string,
	has_trace:     bool,
	traces:        [dynamic]Trace_Record,
}

perf_run_create :: proc(allocator: mem.Allocator) -> Perf_Run {
	return {
		reports = make([dynamic]Perf_Report, 0, 4, allocator),
		traces = make([dynamic]Trace_Record, 0, 2, allocator),
	}
}

perf_run_destroy :: proc(run: ^Perf_Run, allocator: mem.Allocator) {
	if run.trace_name != "" {
		delete(run.trace_name, allocator)
	}
	delete(run.trace_samples)
	if run.trace_path != "" {
		delete(run.trace_path, allocator)
	}
	for trace in run.traces {
		delete(trace.name, allocator)
		delete(trace.samples, allocator)
	}
	delete(run.traces)
	for &report in run.reports {
		if report.name != "" {
			delete(report.name, allocator)
		}
	}
	delete(run.reports)
	run^ = {}
}

Analysis_Run :: struct {
	config:      Analysis_Config,
	summary:     Analysis_Summary,
	has_summary: bool,
}

analysis_run_create :: proc() -> Analysis_Run {
	return {config = analysis_config_default()}
}

// Analysis_Summary holds no allocation of its own.
analysis_run_destroy :: proc(run: ^Analysis_Run) {
	run^ = {}
}

Settle :: struct {
	frames:    int,
	converged: bool,
}

// One backend policy for the batch run and the live session. The provider is
// called only when a row needs a renderer and rendering is enabled.
Backend_Provider :: struct {
	ctx:    rawptr,
	ensure: proc(ctx: rawptr) -> string,
}

Render_State :: struct {
	backend:     ^Backend,
	provider:    Backend_Provider,
	enabled:     bool,
	present:     bool,
	every_step:  bool,
	failed:      bool,
	report:      renderer.Renderer_Report,
	debug:       renderer.Renderer_Debug,
	digest:      digest.FNV,
	has_digest:  bool,
	digest_text: string,
}

render_state_create :: proc() -> Render_State {
	return {
		enabled = true,
		report = {last_reset = "none"},
	}
}

// The backend belongs to the run or the session runtime, so this owner never
// frees it.
render_state_destroy :: proc(state: ^Render_State, allocator: mem.Allocator) {
	if state.digest_text != "" {
		delete(state.digest_text, allocator)
	}
	state^ = {}
}
