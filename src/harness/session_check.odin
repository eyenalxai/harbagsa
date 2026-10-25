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
		session.renderer_report,
		session.render_digest_text,
		{frames = session.settle_frames, converged = session.settle_converged},
		sections,
		session.allocator,
	)
	window := check_capture_window(session.captures[:], command)
	analysis := session.has_analysis ? &session.analysis : nil
	result := check_evaluate(command, state, window, analysis, session.allocator)
	state_destroy(&state, session.allocator)
	append(&session.checks, result)
	reply.check = &session.checks[len(session.checks) - 1]
	reply.ok = result.ok
	if !result.ok {
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
	return ""
}
