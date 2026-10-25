#+vet explicit-allocators
#+vet !unused-procedures // the harness reads and writes this; the game binary does not
package renderer

// A release build rejects the debug command unless the harness is started with
// its explicit debug flag. The define keeps the override surface out of a
// shipped renderer.
RENDERER_DEBUG_ENABLED :: #config(ENABLE_RENDERER_DEBUG, false)

// A clip at this height keeps every scene fragment. The plan view lowers it to
// discard the roof and the upper walls.
DEBUG_CLIP_HEIGHT_MAX :: 1000.0

// The overrides cover TAA, the point-light path, the sky, ambient occlusion,
// and the plan-view clip.
Renderer_Debug :: struct {
	active:              bool,
	taa:                 bool,
	jitter:              bool,
	history_weight:      f32,
	clamp:               bool,
	force_depth_trust:   bool,
	freeze_shadow_phase: bool,
	shadow_phase:        u32,
	light_shadows:       bool,
	synthetic_lights:    int,
	sky:                 bool,
	gi:                  bool,
	ao:                  bool,
	ao_radius:           f32,
	ao_strength:         f32,
	clip_height:         f32,
}

// A sparse override set. The JSON keys are the harness keys, so a scene
// snapshot, a repro file, and a live debug command share one shape.
Renderer_Debug_Patch :: struct {
	taa:                 Maybe(bool) `json:"taa,omitempty"`,
	jitter:              Maybe(bool) `json:"jitter,omitempty"`,
	history_weight:      Maybe(f32)  `json:"history_weight,omitempty"`,
	clamp:               Maybe(bool) `json:"clamp,omitempty"`,
	depth_trust:         Maybe(bool) `json:"depth_trust,omitempty"`,
	freeze_shadow_phase: Maybe(bool) `json:"freeze_shadow_phase,omitempty"`,
	shadow_phase:        Maybe(int)  `json:"shadow_phase,omitempty"`,
	light_shadows:       Maybe(bool) `json:"light_shadows,omitempty"`,
	synthetic_lights:    Maybe(int)  `json:"synthetic_lights,omitempty"`,
	sky:                 Maybe(bool) `json:"sky,omitempty"`,
	gi:                  Maybe(bool) `json:"gi,omitempty"`,
	ao:                  Maybe(bool) `json:"ao,omitempty"`,
	ao_radius:           Maybe(f32)  `json:"ao_radius,omitempty"`,
	ao_strength:         Maybe(f32)  `json:"ao_strength,omitempty"`,
	clip_height:         Maybe(f32)  `json:"clip_height,omitempty"`,
}

renderer_debug_default :: proc() -> Renderer_Debug {
	return {
		taa = true,
		jitter = true,
		history_weight = -1,
		clamp = true,
		light_shadows = true,
		sky = true,
		gi = true,
		ao = true,
		ao_radius = AO_RADIUS,
		ao_strength = AO_STRENGTH,
		clip_height = DEBUG_CLIP_HEIGHT_MAX,
	}
}

// A snapshot names every effective field. The automatic history weight has no
// value to restore, so a negative weight stays out of the patch.
renderer_debug_patch :: proc(debug: Renderer_Debug) -> Renderer_Debug_Patch {
	patch := Renderer_Debug_Patch {
		taa                 = debug.taa,
		jitter              = debug.jitter,
		clamp               = debug.clamp,
		depth_trust         = debug.force_depth_trust,
		freeze_shadow_phase = debug.freeze_shadow_phase,
		shadow_phase        = int(debug.shadow_phase),
		light_shadows       = debug.light_shadows,
		synthetic_lights    = debug.synthetic_lights,
		sky                 = debug.sky,
		gi                  = debug.gi,
		ao                  = debug.ao,
		ao_radius           = debug.ao_radius,
		ao_strength         = debug.ao_strength,
		clip_height         = debug.clip_height,
	}
	if debug.history_weight >= 0 {
		patch.history_weight = debug.history_weight
	}
	return patch
}

renderer_debug_apply_patch :: proc(debug: Renderer_Debug, patch: Renderer_Debug_Patch) -> Renderer_Debug {
	updated := debug
	if value, has := patch.taa.?; has {
		updated.taa = value
	}
	if value, has := patch.jitter.?; has {
		updated.jitter = value
	}
	if value, has := patch.history_weight.?; has {
		updated.history_weight = value
	}
	if value, has := patch.clamp.?; has {
		updated.clamp = value
	}
	if value, has := patch.depth_trust.?; has {
		updated.force_depth_trust = value
	}
	if value, has := patch.freeze_shadow_phase.?; has {
		updated.freeze_shadow_phase = value
	}
	if value, has := patch.shadow_phase.?; has {
		updated.shadow_phase = u32(value)
	}
	if value, has := patch.light_shadows.?; has {
		updated.light_shadows = value
	}
	if value, has := patch.synthetic_lights.?; has {
		updated.synthetic_lights = value
	}
	if value, has := patch.sky.?; has {
		updated.sky = value
	}
	if value, has := patch.gi.?; has {
		updated.gi = value
	}
	if value, has := patch.ao.?; has {
		updated.ao = value
	}
	if value, has := patch.ao_radius.?; has {
		updated.ao_radius = value
	}
	if value, has := patch.ao_strength.?; has {
		updated.ao_strength = value
	}
	if value, has := patch.clip_height.?; has {
		updated.clip_height = value
	}
	return updated
}

renderer_debug :: proc(r: ^Renderer) -> Renderer_Debug {
	debug := r.taa.debug
	if !debug.active {
		debug = renderer_debug_default()
		debug.taa = r.taa.enabled
		debug.shadow_phase = taa_shadow_phase(r)
	}
	return debug
}

set_renderer_debug :: proc(r: ^Renderer, debug: Renderer_Debug) -> bool {
	previous := r.taa.debug
	changed := previous != debug
	r.taa.debug = debug
	if debug.active {
		r.taa.enabled = debug.taa
	}
	if changed {
		reset_history(r, .Debug_Override)
	}
	return changed
}

clear_renderer_debug :: proc(r: ^Renderer) {
	r.taa.debug = renderer_debug_default()
	r.taa.enabled = true
	reset_history(r, .Debug_Override)
}

taa_shadow_phase :: proc(r: ^Renderer) -> u32 {
	if r.taa.debug.active && r.taa.debug.freeze_shadow_phase {
		return r.taa.debug.shadow_phase
	}
	return r.taa.enabled ? r.frame_count % 64 : 0
}
