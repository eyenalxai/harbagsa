#+vet explicit-allocators
package harness

import "src:renderer"

session_renderer_debug :: proc(session: ^Session, command: Renderer_Debug_Command) -> string {
	if !renderer.RENDERER_DEBUG_ENABLED && !session.debug_renderer {
		return format_error(
			"renderer debug needs a build with ENABLE_RENDERER_DEBUG or the --debug-renderer flag",
		)
	}
	if session.render.backend == nil || session.render.backend.set_debug == nil {
		return format_error("renderer debug requires rendering; add a capture or a perf run")
	}
	if command.clear {
		session.render.backend.clear_debug(session.render.backend.ctx)
		session_refresh_renderer(session)
		return ""
	}
	debug := session.render.backend.get_debug(session.render.backend.ctx)
	debug.active = true
	if command.has_taa {
		debug.taa = command.taa
	}
	if command.has_jitter {
		debug.jitter = command.jitter
	}
	if command.has_history_weight {
		debug.history_weight = command.history_weight
	}
	if command.has_clamp {
		debug.clamp = command.clamp
	}
	if command.has_depth_trust {
		debug.force_depth_trust = command.depth_trust
	}
	if command.has_shadow_phase {
		debug.shadow_phase = u32(command.shadow_phase)
		debug.freeze_shadow_phase = true
	}
	if command.has_freeze_shadow_phase {
		debug.freeze_shadow_phase = command.freeze_shadow_phase
		if command.freeze_shadow_phase && !command.has_shadow_phase {
			debug.shadow_phase = session.render.report.shadow_phase
		}
	}
	if command.has_light_shadows {
		debug.light_shadows = command.light_shadows
	}
	if command.has_synthetic_lights {
		debug.synthetic_lights = command.synthetic_lights
	}
	if command.has_sky {
		debug.sky = command.sky
	}
	if command.has_ao {
		debug.ao = command.ao
	}
	defaults := renderer.renderer_debug_default()
	for field in command.reset {
		switch field {
		case .TAA:
			debug.taa = defaults.taa
		case .Jitter:
			debug.jitter = defaults.jitter
		case .History_Weight:
			debug.history_weight = defaults.history_weight
		case .Clamp:
			debug.clamp = defaults.clamp
		case .Depth_Trust:
			debug.force_depth_trust = defaults.force_depth_trust
		case .Freeze_Shadow_Phase:
			debug.freeze_shadow_phase = defaults.freeze_shadow_phase
		case .Shadow_Phase:
			debug.shadow_phase = defaults.shadow_phase
		case .Light_Shadows:
			debug.light_shadows = defaults.light_shadows
		case .Synthetic_Lights:
			debug.synthetic_lights = defaults.synthetic_lights
		case .Sky:
			debug.sky = defaults.sky
		case .AO:
			debug.ao = defaults.ao
		}
	}
	session.render.backend.set_debug(session.render.backend.ctx, debug)
	session_refresh_renderer(session)
	return ""
}
