#+vet explicit-allocators
#+vet !unused-procedures // the harness reads this; the game binary does not
package renderer

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
	active:              bool   `json:"active"`,
	frame_count:         u32    `json:"frame_count"`,
	taa_enabled:         bool   `json:"taa_enabled"`,
	jitter_index:        int    `json:"jitter_index"`,
	history_valid:       bool   `json:"history_valid"`,
	convergence_frames:  int    `json:"convergence_frames"`,
	history_read:        int    `json:"history_read"`,
	history_weight:      f32    `json:"history_weight"`,
	reset_count:         int    `json:"reset_count"`,
	last_reset:          string `json:"last_reset"`,
	shadow_phase:        u32    `json:"shadow_phase"`,
	light_count:         int    `json:"light_count"`,
	atlas_weight:        f32    `json:"atlas_weight"`,
	text_truncated_runs: int    `json:"text_truncated_runs"`,
	text_font_drops:     int    `json:"text_font_drops"`,
	debug:               Debug_Report `json:"debug"`,
}

Debug_Report :: struct {
	active:              bool `json:"active"`,
	taa:                 bool `json:"taa"`,
	jitter:              bool `json:"jitter"`,
	history_weight:      f32  `json:"history_weight"`,
	clamp:               bool `json:"clamp"`,
	depth_trust:         bool `json:"depth_trust"`,
	shadow_phase_frozen: bool `json:"shadow_phase_frozen"`,
	shadow_phase:        u32  `json:"shadow_phase"`,
	light_shadows:       bool `json:"light_shadows"`,
	synthetic_lights:    int  `json:"synthetic_lights"`,
	sky:                 bool `json:"sky"`,
	ao:                  bool `json:"ao"`,
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
	ao_samples:      int,
	ao_radius:       f32,
	ao_strength:     f32,
}

renderer_report :: proc(r: ^Renderer) -> Renderer_Report {
	debug_effective := renderer_debug(r)
	report := Renderer_Report {
		active             = r.device != nil,
		frame_count        = r.frame_count,
		taa_enabled        = r.taa.enabled,
		jitter_index       = r.taa.applied_jitter_index,
		history_valid      = r.taa.history_valid,
		convergence_frames = r.taa.convergence_frames,
		history_read       = r.taa.applied_history_read,
		reset_count        = r.taa.reset_count,
		last_reset         = reset_reason_name(r.taa.last_reset),
		shadow_phase       = r.taa.shadow_phase,
		light_count        = r.light_count,
		atlas_weight       = text_atlas_applied_weight(r),
		text_truncated_runs = r.overlay.atlas.caps.truncated_runs,
		text_font_drops     = r.overlay.atlas.caps.dropped_fonts,
		debug = {
			active = r.taa.debug.active,
			taa = r.taa.enabled,
			jitter = r.taa.debug.active ? r.taa.debug.jitter : r.taa.enabled,
			history_weight = r.taa.debug.history_weight,
			clamp = r.taa.debug.active ? r.taa.debug.clamp : true,
			depth_trust = r.taa.debug.active && r.taa.debug.force_depth_trust,
			shadow_phase_frozen = r.taa.debug.active && r.taa.debug.freeze_shadow_phase,
			shadow_phase = r.taa.debug.shadow_phase,
			light_shadows = r.taa.debug.active ? r.taa.debug.light_shadows : true,
			synthetic_lights = r.taa.debug.active ? r.taa.debug.synthetic_lights : 0,
			sky = debug_effective.sky,
			ao = debug_effective.ao,
		},
	}
	if r.taa.debug.active && r.taa.debug.history_weight >= 0 {
		report.history_weight = r.taa.debug.history_weight
	} else if r.taa.enabled && r.taa.history_valid && r.taa.convergence_frames > 0 {
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
		ao_samples = AO_SAMPLES,
		ao_radius = AO_RADIUS,
		ao_strength = AO_STRENGTH,
	}
}
