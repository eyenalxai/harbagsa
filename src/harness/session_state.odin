#+vet explicit-allocators
package harness

import "core:math"

import "src:digest"
import "src:frame"
import "src:game"

@(private)
session_refresh_bake :: proc(session: ^Session) {
	if session.render.backend == nil || session.render.backend.refresh_bake == nil {
		return
	}
	static := game.simulation_bake_input(
		&session.runtime.sim,
		&session.runtime.scratch.bake,
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

// One observation refreshes every derived owner before the build, so a section
// cannot pair a fresh value with a stale HUD.
session_observe :: proc(session: ^Session, sections: State_Sections) -> (State, string) {
	session_refresh_bake(session)
	session_refresh_renderer(session)
	session_refresh_hud(session)
	observation, observation_error := session_ui_observation(session)
	if observation_error != "" {
		return {}, observation_error
	}
	return state_build_sections(
		&session.runtime.sim,
		session.frame,
		&session.runtime.hud,
		&session.runtime.debug,
		session_camera(session),
		session.render.report,
		session.render.digest_text,
		{frames = session.settle.frames, converged = session.settle.converged},
		observation,
		sections,
		session.allocator,
	), ""
}

session_state :: proc(session: ^Session) -> (State, string) {
	return session_observe(session, state_all_sections())
}

// The report resolves at the alpha of the last frame the renderer built, so a
// capture at a non-unit alpha and the state after it agree.
@(private)
session_camera :: proc(session: ^Session) -> Camera_State {
	view := frame.camera_view(
		&session.runtime.sim,
		&session.runtime.debug,
		session_override_camera(session),
		session_view_alpha(session),
	)
	return {
		position = vec_state(view.camera.position),
		yaw_deg = f32(math.to_degrees(view.camera.yaw)),
		pitch_deg = f32(math.to_degrees(view.camera.pitch)),
		fov_deg = f32(math.to_degrees(view.camera.fov_x)),
		source = view.source,
		overridden = view.source != "third_person",
	}
}
