#+vet explicit-allocators
package harness

import "src:digest"
import "src:renderer"

@(private)
session_refresh_renderer :: proc(session: ^Session) {
	if session.backend == nil || session.backend.snapshot == nil {
		return
	}
	snapshot := session.backend.snapshot(session.backend.ctx)
	session.renderer_report = snapshot.report
	session.has_render_digest = snapshot.has_digest
	session.render_digest = snapshot.digest
	if !snapshot.has_digest {
		return
	}
	if session.render_digest_text != "" {
		delete(session.render_digest_text, session.allocator)
	}
	session.render_digest_text = digest.hex(snapshot.digest, session.allocator)
}

session_state :: proc(session: ^Session) -> State {
	report := session.renderer_report
	renderer_state := Renderer_State {
		active             = report.active,
		frame_count        = report.frame_count,
		taa_enabled        = report.taa_enabled,
		jitter_index       = report.jitter_index,
		history_valid      = report.history_valid,
		convergence_frames = report.convergence_frames,
		history_read       = report.history_read,
		history_weight     = report.history_weight,
		reset_count        = report.reset_count,
		last_reset         = renderer.reset_reason_name(report.last_reset),
		shadow_phase       = report.shadow_phase,
		debug = {
			active              = report.debug.active,
			taa                 = report.debug.taa,
			jitter              = report.debug.jitter,
			history_weight      = report.debug.history_weight,
			clamp               = report.debug.clamp,
			depth_trust         = report.debug.depth_trust,
			shadow_phase_frozen = report.debug.shadow_phase_frozen,
			shadow_phase        = report.debug.shadow_phase,
		},
	}
	return state_build(
		&session.sim,
		session.frame,
		&session.hud.menu,
		&session.debug,
		renderer_state,
		session.render_digest_text,
		session.allocator,
	)
}
