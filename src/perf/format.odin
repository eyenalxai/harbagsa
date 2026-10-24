#+vet explicit-allocators
#+vet !unused-procedures // the HUD calls the formatters
package perf

import "core:fmt"
import "core:strings"

format_summary :: proc(buffer: []byte, summary: Stats) -> string {
	if summary.count == 0 {
		return fmt.bprintf(buffer, "perf --")
	}
	fps: f64
	if summary.interval.mean > 0 {
		fps = 1000.0 / summary.interval.mean
	}
	builder := strings.builder_from_bytes(buffer)
	fmt.sbprintf(
		&builder,
		"perf %.1f fps  %.2f ms  cpu %.2f  p95 %.2f  spike %d",
		fps,
		summary.interval.mean,
		summary.cpu.mean,
		summary.interval.p95,
		summary.spikes,
	)
	if summary.gpu.available {
		fmt.sbprintf(
			&builder,
			"  gpu %.2f  top %s",
			summary.gpu.total.mean,
			pass_name(summary.gpu.top),
		)
	}
	return strings.to_string(builder)
}

// The GPU numbers belong to the last completed frame, not the frame being
// recorded, so the line says so.
format_passes :: proc(buffer: []byte, summary: Stats) -> string {
	if !summary.gpu.available {
		return fmt.bprintf(buffer, "gpu --")
	}
	return fmt.bprintf(
		buffer,
		"last  tlas %.2f  depth %.2f  scene %.2f  taa %.2f  overlay %.2f",
		summary.gpu.passes[.Tlas].mean,
		summary.gpu.passes[.Depth].mean,
		summary.gpu.passes[.Scene].mean,
		summary.gpu.passes[.Taa].mean,
		summary.gpu.passes[.Overlay].mean,
	)
}

pass_name :: proc(pass: Pass) -> string {
	switch pass {
	case .Tlas:
		return "tlas"
	case .Depth:
		return "depth"
	case .Scene:
		return "scene"
	case .Taa:
		return "taa"
	case .Overlay:
		return "overlay"
	}
	return "none"
}
