#+vet explicit-allocators
package harness

import "core:fmt"
import "core:strings"

@(private)
renderer_field :: proc(renderer: Renderer_State, path: string) -> (Check_Value, string) {
	if strings.has_prefix(path, "debug.") {
		return renderer_debug_field(renderer.debug, path[len("debug."):])
	}
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

@(private)
renderer_debug_field :: proc(debug: Renderer_Debug_State, path: string) -> (Check_Value, string) {
	switch path {
	case "active":
		return {kind = .Bool, boolean = debug.active}, ""
	case "taa":
		return {kind = .Bool, boolean = debug.taa}, ""
	case "jitter":
		return {kind = .Bool, boolean = debug.jitter}, ""
	case "history_weight":
		return {kind = .Number, number = f64(debug.history_weight)}, ""
	case "clamp":
		return {kind = .Bool, boolean = debug.clamp}, ""
	case "depth_trust":
		return {kind = .Bool, boolean = debug.depth_trust}, ""
	case "shadow_phase_frozen":
		return {kind = .Bool, boolean = debug.shadow_phase_frozen}, ""
	case "shadow_phase":
		return {kind = .Number, number = f64(debug.shadow_phase)}, ""
	case "sky":
		return {kind = .Bool, boolean = debug.sky}, ""
	case "ao":
		return {kind = .Bool, boolean = debug.ao}, ""
	}
	return {}, fmt.aprintf("unknown renderer debug field %q", path, allocator = context.allocator)
}
