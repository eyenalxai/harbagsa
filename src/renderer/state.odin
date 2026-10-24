#+vet explicit-allocators
#+vet !unused-procedures // the harness reads this; the game binary does not
package renderer

import "src:digest"

History_Reset_Reason :: enum {
	None,
	Create,
	Extent,
	Toggle,
	Teleport,
	Scene_Change,
	Debug_Override,
	Player_Reset,
	Scene_Reset,
}

reset_reason_name :: proc(reason: History_Reset_Reason) -> string {
	switch reason {
	case .None:
		return "none"
	case .Create:
		return "create"
	case .Extent:
		return "extent"
	case .Toggle:
		return "toggle"
	case .Teleport:
		return "teleport"
	case .Scene_Change:
		return "scene_change"
	case .Debug_Override:
		return "debug_override"
	case .Player_Reset:
		return "player_reset"
	case .Scene_Reset:
		return "scene_reset"
	}
	return "none"
}

Renderer_Report :: struct {
	active:             bool,
	frame_count:        u32,
	taa_enabled:        bool,
	jitter_index:       int,
	history_valid:      bool,
	convergence_frames: int,
	history_read:       int,
	history_weight:     f32,
	reset_count:        int,
	last_reset:         History_Reset_Reason,
	shadow_phase:       u32,
}

Setup_Report :: struct {
	target:          Target_Kind,
	width:           u32,
	height:          u32,
	device:          string,
	taa:             bool,
	frames_in_flight: int,
	jitter_samples:  int,
	history_images:  int,
	max_samples:     int,
}

renderer_report :: proc(r: ^Renderer) -> Renderer_Report {
	report := Renderer_Report {
		active             = r.device != nil,
		frame_count        = r.frame_count,
		taa_enabled        = r.taa.enabled,
		jitter_index       = r.taa.applied_jitter_index,
		history_valid      = r.taa.history_valid,
		convergence_frames = r.taa.convergence_frames,
		history_read       = r.taa.history_read,
		reset_count        = r.taa.reset_count,
		last_reset         = r.taa.last_reset,
		shadow_phase       = r.taa.shadow_phase,
	}
	if r.taa.enabled && r.taa.history_valid && r.taa.convergence_frames > 0 {
		count := f32(r.taa.convergence_frames)
		report.history_weight = count / (count + 1)
	}
	return report
}

setup_report :: proc(r: ^Renderer) -> Setup_Report {
	return {
		target = r.target.kind,
		width = r.target.config.width,
		height = r.target.config.height,
		device = string(r.device_name[:r.device_name_len]),
		taa = r.taa.enabled,
		frames_in_flight = frames_in_flight(r.target.kind),
		jitter_samples = TAA_JITTER_SAMPLES,
		history_images = TAA_HISTORY_IMAGES,
		max_samples = TAA_MAX_SAMPLES,
	}
}

last_render_digest :: proc(r: ^Renderer) -> (value: digest.FNV, has: bool) {
	return r.render_digest, r.has_render_digest
}
