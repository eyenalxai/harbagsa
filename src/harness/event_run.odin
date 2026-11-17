#+vet explicit-allocators
package harness

import "src:platform"
import "src:renderer"

execute_event :: proc(session: ^Session, command: Command, reply: ^Reply) -> string {
	session_actions_begin(session)
	defer session_actions_end(session)
	if event_error := session_event(session, command.event); event_error != "" {
		return event_error
	}
	if command.event.no_action && len(session.ui_actions) > 0 {
		return format_error(
			"the event emitted %d UI actions; expected none",
			len(session.ui_actions),
		)
	}
	if command.event.has_expect && !ui_actions_have(session.ui_actions[:], command.event.expect) {
		return format_error(
			"the UI action %s was not emitted",
			ui_action_kind_name(command.event.expect.kind),
		)
	}
	return check_state_expects(session, command.event.expect_state)
}

@(private)
session_event :: proc(session: ^Session, event: Event_Command) -> string {
	events := session_frame_events(session)
	switch event.form {
	case .Key:
		kind := platform.Input_Kind.Key_Down
		switch event.key_state {
		case .Down:
		case .Up:
			kind = .Key_Up
		case .Repeat:
			kind = .Key_Repeat
		}
		push_session_event(&events, {kind = kind, key = event.key, mods = event.mods})
	case .Pointer:
		if event.has_pointer {
			session.pointer = event.pointer
		}
		point := session_pointer_normalized(session, session.pointer)
		push_session_event(&events, {kind = .Pointer_Move, pointer = point})
		events.pointer = point
		switch event.pointer_state {
		case .Move:
		case .Down:
			push_session_event(&events, {kind = .Pointer_Down, pointer = point})
			if event.button == .Right {
				events.secondary_pressed = true
			} else {
				events.primary_pressed = true
			}
		case .Up:
			push_session_event(&events, {kind = .Pointer_Up, pointer = point})
			if event.button == .Left {
				events.primary_released = true
			}
		}
	case .Wheel:
		if event.has_pointer {
			session.pointer = event.pointer
		}
		point := session_pointer_normalized(session, session.pointer)
		push_session_event(&events, {kind = .Wheel, pointer = point, wheel = event.wheel})
		events.pointer = point
		events.wheel_delta += event.wheel
	case .Focus:
		kind := platform.Input_Kind.Focus_Gained
		if !event.focused {
			kind = .Focus_Lost
		}
		push_session_event(&events, {kind = kind})
		session.captured = event.has_captured ? event.captured : event.focused
		events.captured = session.captured
	case .Gamepad:
		if event.has_connected {
			session.pad.connected = event.pad_connected
		}
		if event.has_button {
			if event.pad_down {
				session.pad.pressed += {event.pad_button}
			} else {
				session.pad.released += {event.pad_button}
			}
		}
		if event.has_left {
			session.pad.left = event.pad_left
		}
		if event.has_right {
			session.pad.right = event.pad_right
		}
		events.gamepad = session.pad
	}
	error := session_frame(session, events, 0, session.default_alpha, nil)
	session.pad.pressed = {}
	session.pad.released = {}
	return error
}

@(private)
push_session_event :: proc(events: ^platform.Events, event: platform.Input_Event) {
	if events.raw_count >= len(events.raw) {
		events.overflow = true
		return
	}
	events.raw[events.raw_count] = event
	events.raw_count += 1
}

// session_pointer_normalized maps view points to the target's normalized space,
// which is what the platform reports and what the UI step scales back.
@(private)
session_pointer_normalized :: proc(session: ^Session, points: [2]f32) -> [2]f32 {
	if session.app.renderer == nil {
		return {}
	}
	width, height := renderer.target_extent(session.app.renderer)
	if width == 0 || height == 0 {
		return {}
	}
	scale := renderer.ui_scale(session.app.renderer)
	return {points.x * scale / f32(width), points.y * scale / f32(height)}
}

@(private)
ui_actions_have :: proc(actions: []renderer.Ui_Action, expect: Ui_Expect) -> bool {
	for action in actions {
		if ui_action_matches(expect, action) {
			return true
		}
	}
	return false
}

session_actions_begin :: proc(session: ^Session) {
	clear(&session.ui_actions)
	session.collect_actions = true
}

session_actions_end :: proc(session: ^Session) {
	session.collect_actions = false
}
