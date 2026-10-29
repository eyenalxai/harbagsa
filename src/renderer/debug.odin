#+vet explicit-allocators
#+vet !unused-procedures // the harness reads and writes this; the game binary does not
package renderer

RENDERER_DEBUG_ENABLED :: #config(ENABLE_RENDERER_DEBUG, false)
DEBUG_CLIP_HEIGHT_MAX :: 1000.0

Renderer_Debug :: struct {
	active:            bool,
	taa:               bool,
	jitter:            bool,
	history_weight:    f32,
	clamp:             bool,
	force_depth_trust: bool,
	synthetic_lights:  int,
	clip_height:       f32,
	light_shadows:     bool,
	lightmap:          bool,
	probes:            bool,
}

Renderer_Debug_Patch :: struct {
	taa:              Maybe(bool) `json:"taa,omitempty"`,
	jitter:           Maybe(bool) `json:"jitter,omitempty"`,
	history_weight:   Maybe(f32)  `json:"history_weight,omitempty"`,
	clamp:            Maybe(bool) `json:"clamp,omitempty"`,
	depth_trust:      Maybe(bool) `json:"depth_trust,omitempty"`,
	synthetic_lights: Maybe(int)  `json:"synthetic_lights,omitempty"`,
	clip_height:      Maybe(f32)  `json:"clip_height,omitempty"`,
	light_shadows:    Maybe(bool) `json:"light_shadows,omitempty"`,
	lightmap:         Maybe(bool) `json:"lightmap,omitempty"`,
	probes:           Maybe(bool) `json:"probes,omitempty"`,
}

renderer_debug_default :: proc() -> Renderer_Debug {
	return {
		taa = true,
		jitter = true,
		history_weight = -1,
		clamp = true,
		clip_height = DEBUG_CLIP_HEIGHT_MAX,
		light_shadows = true,
		lightmap = true,
		probes = true,
	}
}

renderer_debug_patch :: proc(debug: Renderer_Debug) -> Renderer_Debug_Patch {
	patch := Renderer_Debug_Patch {
		taa = debug.taa,
		jitter = debug.jitter,
		clamp = debug.clamp,
		depth_trust = debug.force_depth_trust,
		synthetic_lights = debug.synthetic_lights,
		clip_height = debug.clip_height,
		light_shadows = debug.light_shadows,
		lightmap = debug.lightmap,
		probes = debug.probes,
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
	if value, has := patch.synthetic_lights.?; has {
		updated.synthetic_lights = value
	}
	if value, has := patch.clip_height.?; has {
		updated.clip_height = value
	}
	if value, has := patch.light_shadows.?; has {
		updated.light_shadows = value
	}
	if value, has := patch.lightmap.?; has {
		updated.lightmap = value
	}
	if value, has := patch.probes.?; has {
		updated.probes = value
	}
	return updated
}

renderer_debug :: proc(r: ^Renderer) -> Renderer_Debug {
	debug := r.debug
	if !debug.active {
		debug = renderer_debug_default()
		debug.taa = r.taa.enabled
	}
	return debug
}

set_renderer_debug :: proc(r: ^Renderer, debug: Renderer_Debug) -> bool {
	previous := r.debug
	changed := previous != debug
	r.debug = debug
	if debug.active {
		r.taa.enabled = debug.taa
	}
	if changed {
		reset_history(r, .Debug_Override)
	}
	return changed
}

clear_renderer_debug :: proc(r: ^Renderer) {
	r.debug = renderer_debug_default()
	r.taa.enabled = true
	reset_history(r, .Debug_Override)
}

