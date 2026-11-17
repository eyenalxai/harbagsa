#+vet explicit-allocators
package harness

import "core:fmt"
import "core:math"
import "core:mem"

import "src:renderer"

MAX_DRAG_STEPS :: 64
LIVE_WHEEL_POINTS :: 40.0

// execute_ui is a recipe over raw events: every pointer, key, wheel, and focus
// frame it sends goes through the same route the live app uses.
execute_ui :: proc(session: ^Session, command: Command, reply: ^Reply) -> string {
	if session.render.backend == nil {
		return format_error("%s", "ui requires rendering")
	}
	session_actions_begin(session)
	defer session_actions_end(session)
	ui := command.ui
	recipe_error := ""
	if ui.has_click {
		recipe_error = ui_click_recipe(session, ui.click)
	} else if ui.has_drag {
		recipe_error = ui_drag_recipe(session, ui.drag)
	} else if ui.has_wheel {
		recipe_error = ui_wheel_recipe(session, ui.wheel)
	} else if ui.has_focus {
		recipe_error = ui_focus_recipe(session, ui.focus)
	}
	if recipe_error != "" {
		return recipe_error
	}
	// A click and a released drag must change something; a wheel or a focus
	// change has no action to emit.
	if len(session.ui_actions) == 0 {
		if ui.has_click {
			return format_error("%s", "the UI click produced no action")
		}
		if ui.has_drag && !ui.drag.hold {
			return format_error("%s", "the UI drag produced no action")
		}
	}
	if ui.has_expect && !ui_actions_have(session.ui_actions[:], ui.expect) {
		return format_error(
			"the UI action %s was not emitted",
			ui_action_kind_name(ui.expect.kind),
		)
	}
	return check_state_expects(session, ui.expect_state)
}

@(private)
ui_click_recipe :: proc(session: ^Session, target: Ui_Target) -> string {
	point, point_error := ui_target_point(session, target)
	if point_error != "" {
		return point_error
	}
	if event_error := session_event(
		session,
		{form = .Pointer, pointer = point, has_pointer = true, pointer_state = .Down},
	); event_error != "" {
		return event_error
	}
	if event_error := session_event(
		session,
		{form = .Pointer, pointer = point, has_pointer = true, pointer_state = .Up},
	); event_error != "" {
		return event_error
	}
	return session_settle_frame(session)
}

@(private)
ui_drag_recipe :: proc(session: ^Session, drag: Ui_Drag) -> string {
	point, point_error := ui_target_point(session, drag.target)
	if point_error != "" {
		return point_error
	}
	steps := clamp(drag.steps, 1, MAX_DRAG_STEPS)
	if event_error := session_event(
		session,
		{form = .Pointer, pointer = point, has_pointer = true, pointer_state = .Down},
	); event_error != "" {
		return event_error
	}
	for step in 1 ..= steps {
		fraction := f32(step) / f32(steps)
		move := point + {drag.dx * fraction, drag.dy * fraction}
		if event_error := session_event(
			session,
			{form = .Pointer, pointer = move, has_pointer = true, pointer_state = .Move},
		); event_error != "" {
			return event_error
		}
	}
	if drag.hold {
		return session_settle_frame(session)
	}
	end := point + {drag.dx, drag.dy}
	if event_error := session_event(
		session,
		{form = .Pointer, pointer = end, has_pointer = true, pointer_state = .Up},
	); event_error != "" {
		return event_error
	}
	return session_settle_frame(session)
}

@(private)
ui_wheel_recipe :: proc(session: ^Session, wheel: Ui_Wheel) -> string {
	point, point_error := ui_target_point(session, wheel.target)
	if point_error != "" {
		return point_error
	}
	if wheel.dx != 0 {
		return format_error("%s", "the live wheel path carries a vertical notch only")
	}
	if event_error := session_event(
		session,
		{form = .Pointer, pointer = point, has_pointer = true, pointer_state = .Move},
	); event_error != "" {
		return event_error
	}
	// The platform reports SDL notches; the UI step negates and scales them to
	// Rune points, so a command in points converts back.
	notches := -wheel.dy / LIVE_WHEEL_POINTS
	if event_error := session_event(
		session,
		{form = .Wheel, wheel = notches},
	); event_error != "" {
		return event_error
	}
	return session_settle_frame(session)
}

@(private)
ui_focus_recipe :: proc(session: ^Session, focused: bool) -> string {
	if event_error := session_event(
		session,
		{form = .Focus, focused = focused, captured = focused, has_captured = true},
	); event_error != "" {
		return event_error
	}
	return session_settle_frame(session)
}

@(private)
ui_target_point :: proc(session: ^Session, target: Ui_Target) -> ([2]f32, string) {
	if target.point {
		return {target.x, target.y}, ""
	}
	key := target.key
	text := ui_key_text(&key)
	x, y: f32
	if renderer.ui_element_center(raw_data(text), u32(len(text)), &x, &y) != 0 {
		return {}, format_error("the UI element %q was not found", text)
	}
	return {x, y}, ""
}

@(private)
ui_action_matches :: proc(expect: Ui_Expect, action: renderer.Ui_Action) -> bool {
	if action.kind != expect.kind {
		return false
	}
	if expect.has_id && action.id != expect.id {
		return false
	}
	if expect.has_value && action.value != expect.value {
		return false
	}
	if expect.has_scalar && math.abs(action.scalar - expect.scalar) > 0.0001 {
		return false
	}
	return true
}

@(private)
check_state_expects :: proc(session: ^Session, expects: []State_Expect) -> string {
	if len(expects) == 0 {
		return ""
	}
	sections: State_Sections
	for expect in expects {
		sections |= state_section_for_field(expect.path)
	}
	state, state_error := session_observe(session, sections)
	if state_error != "" {
		return state_error
	}
	defer state_destroy(&state, session.allocator)
	for expect in expects {
		value, field_error := field_value(state, session.capture.captures[:], expect.path)
		if field_error != "" {
			return field_error
		}
		if !field_matches(value, expect.value) {
			return format_error(
				"expected %s = %s, got %s",
				expect.path,
				field_text(expect.value, context.temp_allocator),
				field_text(value, context.temp_allocator),
			)
		}
	}
	return ""
}

@(private)
field_matches :: proc(value, expected: Field_Value) -> bool {
	if value.kind != expected.kind {
		return false
	}
	switch value.kind {
	case .Number:
		return math.abs(value.number - expected.number) < 0.05
	case .Bool:
		return value.boolean == expected.boolean
	case .String:
		return value.text == expected.text
	}
	return false
}

@(private)
field_text :: proc(value: Field_Value, allocator: mem.Allocator) -> string {
	switch value.kind {
	case .Number:
		return fmt.aprintf("%g", value.number, allocator = allocator)
	case .Bool:
		return value.boolean ? "true" : "false"
	case .String:
		return fmt.aprintf("%q", value.text, allocator = allocator)
	}
	return "?"
}
