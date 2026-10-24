#+vet explicit-allocators
#+vet !unused-procedures // the harness reads and writes this; the game binary does not
package renderer

// A release build rejects the debug command unless the harness is started with
// its explicit debug flag. The define keeps the override surface out of a
// shipped renderer.
RENDERER_DEBUG_ENABLED :: #config(ENABLE_RENDERER_DEBUG, false)

TAA_Debug :: struct {
	active:             bool,
	taa:                bool,
	jitter:             bool,
	history_weight:     f32,
	clamp:              bool,
	force_depth_trust:  bool,
	freeze_shadow_phase: bool,
	shadow_phase:       u32,
}

taa_debug_default :: proc() -> TAA_Debug {
	return {
		taa = true,
		jitter = true,
		history_weight = -1,
		clamp = true,
	}
}

taa_debug :: proc(r: ^Renderer) -> TAA_Debug {
	debug := r.taa.debug
	if !debug.active {
		debug = taa_debug_default()
		debug.taa = r.taa.enabled
		debug.shadow_phase = taa_shadow_phase(r)
	}
	return debug
}

// Any change to the override struct is a TAA input change: the resolve reads
// every nonzero field. A new shadow phase therefore resets history too.
set_taa_debug :: proc(r: ^Renderer, debug: TAA_Debug) -> bool {
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

clear_taa_debug :: proc(r: ^Renderer) {
	r.taa.debug = taa_debug_default()
	r.taa.enabled = true
	reset_history(r, .Debug_Override)
}

taa_shadow_phase :: proc(r: ^Renderer) -> u32 {
	if r.taa.debug.active && r.taa.debug.freeze_shadow_phase {
		return r.taa.debug.shadow_phase
	}
	return r.taa.enabled ? r.frame_count % 64 : 0
}
