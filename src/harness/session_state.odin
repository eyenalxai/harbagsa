#+vet explicit-allocators
package harness

import "core:math"

import "src:digest"
import "src:frame"
import "src:game"

@(private)
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

// The report names the view the renderer uses, in the order frame.build picks
// it. `overridden` says the player view is not the one on screen.
@(private)
session_camera :: proc(session: ^Session) -> Camera_State {
	if session.has_camera_override {
		camera := session.camera_override
		return {
			position = vec_state(camera.position),
			yaw_deg = f32(math.to_degrees(camera.yaw)),
			pitch_deg = f32(math.to_degrees(camera.pitch)),
			fov_deg = f32(math.to_degrees(camera.fov_x)),
			source = "override",
			overridden = true,
		}
	}
	if session.debug.active {
		camera := session.debug.camera
		return {
			position = vec_state(camera.position),
			yaw_deg = f32(math.to_degrees(camera.yaw)),
			pitch_deg = f32(math.to_degrees(camera.pitch)),
			fov_deg = f32(math.to_degrees(frame.PLAYER_FOV_X)),
			source = "debug",
			overridden = true,
		}
	}
	snapshot := game.simulation_snapshot(&session.sim)
	return {
		position = vec_state(snapshot.eye_position),
		yaw_deg = f32(math.to_degrees(snapshot.yaw)),
		pitch_deg = f32(math.to_degrees(snapshot.pitch)),
		fov_deg = f32(math.to_degrees(frame.PLAYER_FOV_X)),
		source = "player",
	}
}
