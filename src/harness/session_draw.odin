#+vet explicit-allocators
package harness

import "core:strings"

@(private)
session_finish_frame :: proc(session: ^Session) -> string {
	due := make([dynamic]int, 0, 4, context.temp_allocator)
	defer delete(due)
	for pending, index in session.pending {
		if pending.frame <= session.frame {
			append(&due, index)
		}
	}
	if (session.present || session.render_every_step) && len(due) == 0 {
		return session_draw_group(session, nil)
	}
	render_error := ""
	for index in due {
		pending := session.pending[index]
		error := session_draw_group(session, pending.requests)
		if error != "" && render_error == "" {
			render_error = error
		}
	}
	for cursor := len(due) - 1; cursor >= 0; cursor -= 1 {
		index := due[cursor]
		session_pending_destroy(session, &session.pending[index])
		ordered_remove(&session.pending, index)
	}
	return render_error
}

@(private)
session_draw :: proc(session: ^Session, request: Capture_Request) -> string {
	requests := [1]Capture_Request{request}
	return session_draw_group(session, requests[:])
}

session_draw_group :: proc(session: ^Session, requests: []Capture_Request) -> string {
	if session.backend == nil {
		if len(requests) > 0 {
			return format_error("capture requires rendering")
		}
		return ""
	}
	results, error := session.backend.render(session.backend.ctx, session, requests)
	if error != "" {
		session.render_failed = true
		session_failure(session, error)
		return error
	}
	if len(requests) > 0 {
		// The digest names the frame the group just wrote, so refresh the
		// renderer snapshot before the captures join the list.
		session_refresh_renderer(session)
		for &result in results {
			result.render_digest = strings.clone(session.render_digest_text, session.allocator)
			append(&session.captures, result)
		}
		session_refresh_analysis(session)
	}
	delete(results, context.allocator)
	session_refresh_renderer(session)
	return ""
}
