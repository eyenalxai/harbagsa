#+vet explicit-allocators
package harness

import "core:fmt"

// One namespace per check. The check resolver reads the same names, so a check
// never asks `state_build` for a document it will not address.
@(private)
check_sections :: proc(field: string) -> State_Sections {
	head, _, _ := split_field(field)
	switch head {
	case "player":
		return {.Player}
	case "camera":
		return {.Camera}
	case "objects":
		return {.Objects}
	case "settings":
		return {.Settings}
	case "debug", "sun":
		return {.Debug}
	case "menu":
		return {.Menu}
	case "rows":
		return {.Rows}
	case "settle":
		return {.Settle}
	case "renderer":
		return {.Renderer}
	case "render_digest":
		return {.Render_Digest}
	case "digest":
		return ALL_STATE_SECTIONS
	case "capture", "analysis":
		return {}
	}
	return {}
}

session_check_command :: proc(
	session: ^Session,
	command: Check_Command,
	reply: ^Reply,
) -> string {
	state := state_build_sections(
		&session.sim,
		session.frame,
		&session.hud,
		&session.debug,
		session_camera(session),
		session.renderer_report,
		session.render_digest_text,
		{frames = session.settle_frames, converged = session.settle_converged},
		check_sections(command.field),
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
		message := fmt.aprintf(
			"check failed: %s %s %s (actual %s)",
			result.field,
			result.op,
			result.expected,
			result.actual,
			allocator = session.allocator,
		)
		session_failure(session, message)
		delete(message, session.allocator)
	}
	return ""
}
