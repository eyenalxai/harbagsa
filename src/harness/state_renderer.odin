#+vet explicit-allocators
package harness

import "core:fmt"

@(private)
renderer_field :: proc(renderer: Renderer_State, path: string) -> (Check_Value, string) {
	switch path {
	case "active":
		return {kind = .Bool, boolean = renderer.active}, ""
	case "frame_count":
		return {kind = .Number, number = f64(renderer.frame_count)}, ""
	case "taa_enabled":
		return {kind = .Bool, boolean = renderer.taa_enabled}, ""
	case "jitter_index":
		return {kind = .Number, number = f64(renderer.jitter_index)}, ""
	case "history_valid":
		return {kind = .Bool, boolean = renderer.history_valid}, ""
	case "convergence_frames":
		return {kind = .Number, number = f64(renderer.convergence_frames)}, ""
	case "history_read":
		return {kind = .Number, number = f64(renderer.history_read)}, ""
	case "history_weight":
		return {kind = .Number, number = f64(renderer.history_weight)}, ""
	case "reset_count":
		return {kind = .Number, number = f64(renderer.reset_count)}, ""
	case "last_reset":
		return {kind = .String, text = renderer.last_reset}, ""
	case "shadow_phase":
		return {kind = .Number, number = f64(renderer.shadow_phase)}, ""
	}
	return {}, fmt.aprintf("unknown renderer field %q", path, allocator = context.allocator)
}
