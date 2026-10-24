#+vet explicit-allocators
package harness

import "src:renderer"

session_renderer_debug :: proc(session: ^Session, command: Renderer_Debug_Command) -> string {
	if !renderer.RENDERER_DEBUG_ENABLED && !session.debug_renderer {
		return format_error(
			"renderer debug needs a build with ENABLE_RENDERER_DEBUG or the --debug-renderer flag",
		)
	}
	if session.backend == nil || session.backend.set_debug == nil {
		return format_error("renderer debug requires rendering; add a capture or a perf run")
	}
	if command.clear {
		session.backend.clear_debug(session.backend.ctx)
		session_refresh_renderer(session)
		return ""
	}
	debug := session.backend.get_debug(session.backend.ctx)
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
			debug.shadow_phase = session.renderer_report.shadow_phase
		}
	}
	if command.has_light_shadows {
		debug.light_shadows = command.light_shadows
	}
	if command.has_synthetic_lights {
		debug.synthetic_lights = command.synthetic_lights
	}
	session.backend.set_debug(session.backend.ctx, debug)
	session_refresh_renderer(session)
	return ""
}
