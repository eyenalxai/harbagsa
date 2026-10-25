#+vet explicit-allocators
package harness

import "core:math"

import "src:digest"
import "src:frame"
import "src:game"

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
	session_refresh_hud(session)
	return state_build(
		&session.sim,
		session.frame,
		&session.hud,
		&session.debug,
		session_camera(session),
		session.renderer_report,
		session.render_digest_text,
		{ frames = session.settle_frames, converged = session.settle_converged },
		session.allocator,
	)
}

@(private)
session_camera :: proc(session: ^Session) -> Camera_State {
	if session.has_camera_override {
		camera := session.camera_override
		return {
			position = vec_state(camera.position),
			yaw = camera.yaw,
			pitch = camera.pitch,
			fov = math.to_degrees(camera.fov_x),
			overridden = true,
		}
	}
	snapshot := game.simulation_snapshot(&session.sim)
	return {
		position = vec_state(snapshot.eye_position),
		yaw = snapshot.yaw,
		pitch = snapshot.pitch,
		fov = math.to_degrees(frame.PLAYER_FOV_X),
	}
}
