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
	ao:                  bool,
	ao_radius:           f32,
	ao_strength:         f32,
	clip_height:         f32,
}

renderer_debug_default :: proc() -> Renderer_Debug {
	return {
		taa = true,
		jitter = true,
		history_weight = -1,
		clamp = true,
		light_shadows = true,
		sky = true,
		ao = true,
		ao_radius = AO_RADIUS,
		ao_strength = AO_STRENGTH,
		clip_height = DEBUG_CLIP_HEIGHT_MAX,
	}
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
