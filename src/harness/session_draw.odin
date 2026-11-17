#+vet explicit-allocators
package harness

import "core:strings"

import "src:appframe"
import "src:game"
import "src:platform"
import "src:renderer"

session_frame_events :: proc(session: ^Session) -> platform.Events {
	events := platform.Events {
		move_forward = session.held.move_forward,
		move_right   = session.held.move_right,
		sprint_held  = session.held.sprint_held,
		captured     = session.captured,
		gamepad      = session.pad,
	}
	if session.pending_jump {
		push_session_event(&events, {kind = .Key_Down, key = .Space})
		push_session_event(&events, {kind = .Key_Up, key = .Space})
		session.pending_jump = false
	}
	if session.pending_sprint {
		push_session_event(&events, {kind = .Key_Down, key = .LShift})
		push_session_event(&events, {kind = .Key_Up, key = .LShift})
		session.pending_sprint = false
	}
	return events
}

session_frame :: proc(
	session: ^Session,
	events: platform.Events,
	steps: int,
	alpha: f32,
	requests: []Capture_Request,
	settle_ui := false,
	skip_draw := false,
	draw_only := false,
) -> string {
	frame_events := events
	if session.render.present && session.render.backend != nil {
		polled, polled_ok := session.render.backend.poll(
			session.render.backend.ctx,
			session,
		)
		if !polled_ok {
			return ""
		}
		frame_events = merge_events(frame_events, polled)
	}
	capture := frame_capture_for(requests)
	options := appframe.Options {
		alpha      = alpha,
		debug_view = session_debug_view(session),
		fx_view    = session.view.fx,
		hud        = session.view.hud,
		capture    = capture,
		perf       = &session.perf.state,
		settle_ui  = settle_ui,
		skip_draw  = skip_draw,
		draw_only  = draw_only,
	}
	result := appframe.run(
		&session.app,
		{events = frame_events, delta = game.SIMULATION_STEP, steps = steps},
		options,
		{},
	)
	switch result.status {
	case .Ok:
	case .Skipped:
		return format_error("%s", "frame skipped")
	case .Fatal:
		return format_error("%s", "render failed")
	}
	if !skip_draw && session.app.renderer != nil {
		session.drawn_alpha = alpha
		session.drawn_frame = session.frame
	}
	if session.app.routed.overflow {
		return format_error("%s", "the input route dropped an event; a queue is full")
	}
	if session.collect_actions {
		append(&session.ui_actions, ..session.app.actions[:session.app.action_count])
		for index in 0 ..< session.app.action_count {
			if session.app.action_applied[index] {
				continue
			}
			message := game.edit_reason_message(session.app.action_reason[index])
			if message == "" {
				message = "the UI action made no change"
			}
			return format_error("%s", message)
		}
	}
	session_refresh_renderer(session)
	if len(requests) > 0 {
		return session_collect_captures(session, requests, capture)
	}
	return ""
}

session_draw_group :: proc(session: ^Session, requests: []Capture_Request) -> string {
	alpha := session.default_alpha
	if len(requests) > 0 {
		alpha = requests[0].alpha
	}
	return session_frame(
		session,
		session_frame_events(session),
		0,
		alpha,
		requests,
		draw_only = true,
	)
}

session_settle_frame :: proc(session: ^Session) -> string {
	return session_frame(
		session,
		session_frame_events(session),
		0,
		session.default_alpha,
		nil,
		true,
		draw_only = true,
	)
}

@(private)
frame_capture_for :: proc(requests: []Capture_Request) -> renderer.Frame_Capture {
	capture: renderer.Frame_Capture
	for request in requests {
		if view, has_view := request.view.?; has_view && renderer.capture_view_is_term(view) {
			capture.views |= {view}
		} else {
			capture.targets |= {request.target}
		}
	}
	return capture
}

@(private)
session_collect_captures :: proc(
	session: ^Session,
	requests: []Capture_Request,
	capture: renderer.Frame_Capture,
) -> string {
	backend := session.render.backend
	results := make([dynamic]Capture_Result, 0, len(requests), context.allocator)
	defer delete(results)
	for request in requests {
		slot := renderer.capture_target_slot(capture, request.target)
		if view, has_view := request.view.?; has_view && renderer.capture_view_is_term(view) {
			slot = renderer.capture_view_slot(capture, view)
		}
		if slot < 0 {
			return format_error("%s", "capture has no readback slot")
		}
		result, error := backend.read_capture(backend.ctx, session, request, slot)
		if error != "" {
			for &written in results {
				capture_result_destroy(&written, session.allocator)
			}
			return error
		}
		append(&results, result)
	}
	// The digest names the frame the group just wrote, so refresh the renderer
	// snapshot before the captures join the list.
	session_refresh_renderer(session)
	for &result in results {
		result.render_digest = strings.clone(session.render.digest_text, session.allocator)
		result.renderer = session.render.report
		append(&session.capture.captures, result)
	}
	return ""
}

// merge_events keeps a live window's events beside the harness ones, so a
// --present session still sees the pointer and the resize it got.
@(private)
merge_events :: proc(events, polled: platform.Events) -> platform.Events {
	merged := events
	merged.quit = merged.quit || polled.quit
	merged.resized = merged.resized || polled.resized
	merged.overflow = merged.overflow || polled.overflow
	merged.captured = polled.captured
	for index in 0 ..< polled.raw_count {
		if merged.raw_count >= len(merged.raw) {
			merged.overflow = true
			break
		}
		merged.raw[merged.raw_count] = polled.raw[index]
		merged.raw_count += 1
	}
	if polled.raw_count > 0 {
		merged.look_delta = polled.look_delta
		merged.pointer = polled.pointer
		merged.primary_pressed = polled.primary_pressed
		merged.primary_released = polled.primary_released
		merged.secondary_pressed = polled.secondary_pressed
		merged.wheel_delta = polled.wheel_delta
	}
	if polled.gamepad.connected || polled.gamepad.left != {} || polled.gamepad.right != {} {
		merged.gamepad = polled.gamepad
	}
	return merged
}
