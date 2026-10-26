#+vet explicit-allocators
package harness

import "core:fmt"

session_check_command :: proc(
	session: ^Session,
	command: Check_Command,
	reply: ^Reply,
) -> string {
	sections := state_section_for_field(command.field)
	if command.has_other {
		sections |= state_section_for_field(command.other)
	}
	if .Menu in sections || .Notice in sections || .Rows in sections {
		session_refresh_hud(session)
	}
	state := state_build_sections(
		&session.sim,
		session.frame,
		&session.hud,
		&session.debug,
		session_camera(session),
		session.render.report,
		session.render.digest_text,
		{frames = session.settle.frames, converged = session.settle.converged},
		sections,
		session.allocator,
	)
	window := check_capture_window(session.capture.captures[:], command)
	analysis := session.analysis.has_summary ? &session.analysis.summary : nil
	result := check_evaluate(command, state, window, analysis, session.allocator)
	state_destroy(&state, session.allocator)
	append(&session.checks, result)
	reply.check = &session.checks[len(session.checks) - 1]
	// An advisory miss is not a command error; an advisory field error is.
	advisory_miss := command.advisory && result.error == ""
	reply.ok = result.ok || advisory_miss
	if !result.ok && !advisory_miss {
		if result.error != "" {
			message := fmt.aprintf(
				"check failed: %s: %s",
				result.field,
				result.error,
				allocator = session.allocator,
			)
			session_failure(session, message)
			delete(message, session.allocator)
		} else {
			tolerance := check_tolerance_note(result, session.allocator)
			message := fmt.aprintf(
				"check failed: %s %s %s%s (actual %s)",
				result.field,
				result.op,
				result.expected,
				tolerance,
				result.actual,
				allocator = session.allocator,
			)
			session_failure(session, message)
			delete(tolerance, session.allocator)
			delete(message, session.allocator)
		}
	}
	return ""
}
