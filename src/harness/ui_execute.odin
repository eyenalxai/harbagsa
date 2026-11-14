#+vet explicit-allocators
package harness

import "core:fmt"
import "core:math"
import "core:mem"

import "src:game"
import "src:renderer"
import "src:uiaction"

execute_ui :: proc(session: ^Session, command: Command, reply: ^Reply) -> string {
	if session.render.backend == nil {
		return format_error("%s", "ui requires rendering")
	}
	renderer.ui_actions_clear()
	ui := command.ui
	if ui.has_click {
		if error := ui_click(ui.click); error != "" {
			return error
		}
	} else if ui.has_drag {
		if error := ui_drag(ui.drag); error != "" {
			return error
		}
		if len(renderer.ui_actions_slice()) == 0 && !ui.drag.hold && !ui.drag.cancel {
			return format_error("%s", "the UI drag produced no action")
		}
	} else if ui.has_wheel {
		if error := ui_wheel(ui.wheel); error != "" {
			return error
		}
	} else if ui.has_focus {
		if !renderer.ui_set_focus(ui.focus) {
			return format_error("%s", "the UI focus change failed")
		}
	}
	actions := renderer.ui_actions_slice()
	session_ui_set_actions(session, actions)
	renderer.ui_actions_clear()
	for action in session.ui_actions {
		result := uiaction.apply(
			{
				sim = &session.runtime.sim,
				debug = &session.runtime.debug,
				menu = &session.runtime.hud.menu,
				captured = false,
			},
			action,
		)
		if !result.handled {
			return format_error("unknown UI action kind %d", action.kind)
		}
		if !result.applied {
			message := game.edit_reason_message(result.reason)
			if message == "" {
				message = "the UI action made no change"
			}
			return format_error("%s", message)
		}
	}
	if ui.has_expect {
		asserted := false
		for action in session.ui_actions {
			if ui_action_matches(ui.expect, action) {
				asserted = true
				break
			}
		}
		if !asserted {
			return format_error(
				"the UI action %s was not emitted",
				ui_action_kind_name(ui.expect.kind),
			)
		}
	}
	return ui_check_state(session, ui.expect_state)
}

@(private)
ui_click :: proc(target: Ui_Target) -> string {
	x, y: f32
	if target.point {
		x, y = target.x, target.y
	} else {
		key := target.key
		found_x, found_y, ok := renderer.ui_find_element(ui_key_text(&key))
		if !ok {
			return format_error("the UI element %q was not found", ui_key_text(&key))
		}
		x, y = found_x, found_y
	}
	if len(renderer.ui_click_at(x, y)) == 0 {
		return format_error("%s", "the UI click produced no action")
	}
	return ""
}

@(private)
ui_drag :: proc(drag: Ui_Drag) -> string {
	if drag.target.point {
		if !renderer.ui_drag_point(
			drag.target.x,
			drag.target.y,
			drag.dx,
			drag.dy,
			drag.steps,
			drag.hold,
			drag.cancel,
		) {
			return format_error("%s", "the UI drag failed")
		}
		return ""
	}
	key := drag.target.key
	text := ui_key_text(&key)
	if !renderer.ui_drag_key(text, drag.dx, drag.dy, drag.steps, drag.hold, drag.cancel) {
		return format_error("the UI element %q was not found", text)
	}
	return ""
}

@(private)
ui_wheel :: proc(wheel: Ui_Wheel) -> string {
	if wheel.target.point {
		if !renderer.ui_wheel_point(wheel.target.x, wheel.target.y, wheel.dx, wheel.dy) {
			return format_error("%s", "the UI wheel failed")
		}
		return ""
	}
	key := wheel.target.key
	text := ui_key_text(&key)
	if !renderer.ui_wheel_key(text, wheel.dx, wheel.dy) {
		return format_error("the UI element %q was not found", text)
	}
	return ""
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
ui_check_state :: proc(session: ^Session, expects: []Ui_State_Expect) -> string {
	if len(expects) == 0 {
		return ""
	}
	state := session_observe(session, state_all_sections())
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
