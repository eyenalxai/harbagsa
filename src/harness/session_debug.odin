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
	debug = renderer.renderer_debug_apply_patch(debug, command.patch)
	if _, has_phase := command.shadow_phase.?; has_phase {
		debug.freeze_shadow_phase = true
	}
	if freeze, has_freeze := command.freeze_shadow_phase.?; has_freeze {
		debug.freeze_shadow_phase = freeze
		if freeze {
			if _, has_phase := command.shadow_phase.?; !has_phase {
				debug.shadow_phase = session.render.report.shadow_phase
			}
		}
	}
	debug = renderer.renderer_debug_apply_patch(debug, renderer_debug_reset_patch(command.reset))
	session.render.backend.set_debug(session.render.backend.ctx, debug)
	session_refresh_renderer(session)
	return ""
}
