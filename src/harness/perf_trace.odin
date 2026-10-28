#+vet explicit-allocators
package harness

import "core:fmt"
import "core:mem"
import "core:os"
import "core:path/filepath"
import "core:strings"

import "src:perf"

perf_trace_path :: proc(name, run_dir: string, allocator: mem.Allocator) -> string {
	if filepath.is_abs(name) {
		return strings.clone(name, allocator)
	}
	return join_path({run_dir, name}, allocator)
}

write_session_trace :: proc(session: ^Session, run_dir: string) -> string {
	if !session.perf.has_trace {
		return ""
	}
	path := perf_trace_path(session.perf.trace_name, run_dir, session.allocator)
	if write_error := write_perf_trace(path, session.perf.trace_samples[:]); write_error != "" {
		delete(path, session.allocator)
		return write_error
	}
	if session.perf.trace_path != "" {
		delete(session.perf.trace_path, session.allocator)
	}
	session.perf.trace_path = path
	return ""
}

// A run may measure more than one side in one scenario, so every perf command
// that asks for a trace keeps its own file.
write_session_traces :: proc(session: ^Session, run_dir: string) -> string {
	for &trace in session.perf.traces {
		path := perf_trace_path(trace.name, run_dir, session.allocator)
		if write_error := write_perf_trace(path, trace.samples); write_error != "" {
			delete(path, session.allocator)
			return write_error
		}
		if session.perf.trace_path != "" {
			delete(session.perf.trace_path, session.allocator)
		}
		session.perf.trace_path = path
	}
	return ""
}

write_perf_trace :: proc(path: string, samples: []perf.Sample) -> string {
	out := make([dynamic]u8, 0, len(samples) * 250, context.allocator)
	defer delete(out)

	line: [768]u8
	for sample in samples {
		builder := strings.builder_from_bytes(line[:])
		fmt.sbprintf(
			&builder,
			`{{"frame":%d,"interval":%.3f,"cpu":{{"events":%.4f,"simulation":%.4f,"build":%.4f,"record":%.4f,"present":%.4f}}`,
			sample.frame,
			perf.milliseconds(sample.interval),
			perf.milliseconds(sample.phases[.Events]),
			perf.milliseconds(sample.phases[.Simulation]),
			perf.milliseconds(sample.phases[.Build]),
			perf.milliseconds(sample.phases[.Record]),
			perf.milliseconds(sample.phases[.Present]),
		)
		if sample.gpu.available {
			fmt.sbprintf(
				&builder,
				`,"gpu":{{"tlas":%.3f,"cluster":%.3f,"depth":%.3f,"scene":%.3f,"taa":%.3f,"overlay":%.3f,"total":%.3f}}`,
				perf.milliseconds(sample.gpu.passes[.Tlas]),
				perf.milliseconds(sample.gpu.passes[.Cluster]),
				perf.milliseconds(sample.gpu.passes[.Depth]),
				perf.milliseconds(sample.gpu.passes[.Scene]),
				perf.milliseconds(sample.gpu.passes[.Taa]),
				perf.milliseconds(sample.gpu.passes[.Overlay]),
				perf.milliseconds(sample.gpu.total),
			)
		}
		fmt.sbprintf(&builder, "}\n")
		text := strings.to_string(builder)
		append(&out, ..line[:len(text)])
	}

	if write_error := os.write_entire_file(path, out[:]); write_error != nil {
		return format_error("cannot write %s: %v", path, write_error)
	}
	return ""
}
