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
		return session_draw(session, {})
	}
	render_error := ""
	for index in due {
		pending := session.pending[index]
		request := Capture_Request {
			name      = pending.name,
			alpha     = pending.alpha,
			target    = pending.target,
			format    = pending.format,
			enabled   = true,
			region    = pending.region,
			profile   = pending.profile,
			crop      = pending.crop,
			histogram = pending.histogram,
		}
		error := session_draw(session, request)
		if error != "" && render_error == "" {
			render_error = error
		}
	}
	for cursor := len(due) - 1; cursor >= 0; cursor -= 1 {
		index := due[cursor]
		delete(session.pending[index].name, session.allocator)
		ordered_remove(&session.pending, index)
	}
	return render_error
}

@(private)
session_draw :: proc(session: ^Session, request: Capture_Request) -> string {
	if session.backend == nil {
		if request.enabled {
			return format_error("capture requires rendering")
		}
		return ""
	}
	result, error := session.backend.render(session.backend.ctx, session, request)
	if error != "" {
		session.render_failed = true
		session_failure(session, error)
		return error
	}
	if request.enabled {
		// The digest names the frame this capture just wrote, so refresh the
		// renderer snapshot before the capture joins the list.
		session_refresh_renderer(session)
		result.render_digest = strings.clone(session.render_digest_text, session.allocator)
		append(&session.captures, result)
		session_refresh_analysis(session)
	}
	session_refresh_renderer(session)
	return ""
}
