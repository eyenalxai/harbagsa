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
	debug = renderer.renderer_debug_apply_patch(debug, renderer_debug_reset_patch(command.reset))
	session_debug_set(session, debug)
	return ""
}

// A perf variant is a patch on the state the run started from, so a variant
// cannot inherit the one that ran before it.
session_debug_variant :: proc(
	session: ^Session,
	base: renderer.Renderer_Debug,
	patch: renderer.Renderer_Debug_Patch,
	reset: Renderer_Debug_Resets,
) {
	debug := renderer.renderer_debug_apply_patch(base, patch)
	debug = renderer.renderer_debug_apply_patch(debug, renderer_debug_reset_patch(reset))
	debug.active = true
	session_debug_set(session, debug)
}

session_debug_set :: proc(session: ^Session, debug: renderer.Renderer_Debug) {
	if session.render.backend == nil || session.render.backend.set_debug == nil {
		return
	}
	session.render.backend.set_debug(session.render.backend.ctx, debug)
	session_refresh_renderer(session)
}
