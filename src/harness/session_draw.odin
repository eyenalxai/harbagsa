#+vet explicit-allocators
package harness

import "core:strings"

@(private)
session_finish_frame :: proc(session: ^Session) -> string {
	due := make([dynamic]int, 0, 4, context.temp_allocator)
	defer delete(due)
	for pending, index in session.capture.pending {
		if pending.frame <= session.frame {
			append(&due, index)
		}
	}
	if (session.render.present || session.render.every_step) && len(due) == 0 {
		return session_draw_group(session, nil)
	}
	render_error := ""
	for index in due {
		pending := session.capture.pending[index]
		error := session_draw_group(session, pending.requests)
		if error != "" && render_error == "" {
			render_error = error
		}
	}
	for cursor := len(due) - 1; cursor >= 0; cursor -= 1 {
		index := due[cursor]
		pending_capture_destroy(&session.capture.pending[index], session.allocator)
		ordered_remove(&session.capture.pending, index)
	}
	return render_error
}

session_draw_group :: proc(session: ^Session, requests: []Capture_Request) -> string {
	if session.render.backend == nil {
		if len(requests) > 0 {
			return format_error("capture requires rendering")
		}
		return ""
	}
	results, error := session.render.backend.render(session.render.backend.ctx, session, requests)
	if error != "" {
		session.render.failed = true
		session_failure(session, error)
		return error
	}
	if len(requests) > 0 {
		// The digest names the frame the group just wrote, so refresh the
		// renderer snapshot before the captures join the list.
		session_refresh_renderer(session)
		for &result in results {
			result.render_digest = strings.clone(session.render.digest_text, session.allocator)
			result.renderer = session.render.report
			append(&session.capture.captures, result)
		}
	}
	delete(results, context.allocator)
	session_refresh_renderer(session)
	return ""
}
