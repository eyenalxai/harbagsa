#+vet explicit-allocators
package harness

import "core:math"

import "src:digest"
import "src:frame"
import "src:game"
import "src:renderer"

@(private)
session_refresh_bake :: proc(session: ^Session) {
	if session.render.backend == nil || session.render.backend.refresh_bake == nil {
		return
	}
	static := game.simulation_bake_input(
		&session.sim,
		&session.scratch.bake,
		session.allocator,
	)
	session.render.backend.refresh_bake(session.render.backend.ctx, static)
}

session_refresh_renderer :: proc(session: ^Session) {
	if session.render.backend == nil || session.render.backend.snapshot == nil {
		return
	}
	if session.render.backend.get_debug != nil {
		session.render.debug = session.render.backend.get_debug(session.render.backend.ctx)
	}
	snapshot := session.render.backend.snapshot(session.render.backend.ctx)
	session.render.report = snapshot.report
	session.render.has_digest = snapshot.has_digest
	session.render.digest = snapshot.digest
	if !snapshot.has_digest {
		return
	}
	if session.render.digest_text != "" {
		delete(session.render.digest_text, session.allocator)
	}
	session.render.digest_text = digest.hex(snapshot.digest, session.allocator)
}

session_state :: proc(session: ^Session) -> State {
	session_refresh_bake(session)
	session_refresh_renderer(session)
	session_refresh_hud(session)
	return state_build(
		&session.sim,
		session.frame,
		&session.hud,
		&session.debug,
		session_camera(session),
		session.render.report,
		session.render.digest_text,
		{ frames = session.settle.frames, converged = session.settle.converged },
		session.allocator,
	)
}

@(private)
session_override_camera :: proc(session: ^Session) -> ^renderer.Camera {
	if session.has_camera_override {
		return &session.camera_override
	}
	return nil
}

// The report resolves at the alpha of the last frame the renderer built, so a
// capture at a non-unit alpha and the state after it agree.
@(private)
session_camera :: proc(session: ^Session) -> Camera_State {
	view := frame.camera_view(
		&session.sim,
		&session.debug,
		session_override_camera(session),
		session.drawn_alpha,
	)
	_, has_player := view.player.?
	return {
		position = vec_state(view.camera.position),
		yaw_deg = f32(math.to_degrees(view.camera.yaw)),
		pitch_deg = f32(math.to_degrees(view.camera.pitch)),
		fov_deg = f32(math.to_degrees(view.camera.fov_x)),
		source = view.source,
		overridden = !has_player,
	}
}
