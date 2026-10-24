#+vet explicit-allocators
package harness

import "src:renderer"

// Settle renders every step without writing a screenshot, so a scenario can
// reach a steady temporal state before it starts capturing.
session_settle :: proc(session: ^Session, command: Settle_Command) -> string {
	if command.converged {
		return session_settle_converged(session)
	}
	session.settle_frames = command.frames
	session.settle_converged = false
	session.render_every_step = true
	defer session.render_every_step = false
	return session_step(session, command.frames)
}

// The convergence cap is fixed, so a waiting settle always ends: either the
// count reaches the cap or a scene change keeps resetting it and the hard
// frame limit stops the loop.
@(private)
session_settle_converged :: proc(session: ^Session) -> string {
	if session.backend == nil || !session.backend.ready {
		return format_error("%s", "settle until converged requires rendering")
	}
	session.render_every_step = true
	defer session.render_every_step = false
	frames := 0
	for frames < MAX_SETTLE_FRAMES {
		if step_error := session_step(session, 1); step_error != "" {
			return step_error
		}
		frames += 1
		if session.renderer_report.convergence_frames >= renderer.TAA_MAX_SAMPLES {
			break
		}
	}
	session.settle_frames = frames
	session.settle_converged = session.renderer_report.convergence_frames >= renderer.TAA_MAX_SAMPLES
	return ""
}
