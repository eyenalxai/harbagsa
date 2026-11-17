#+vet explicit-allocators
package harness

import "core:encoding/json"

import "src:platform"

Gamepad_Command :: struct {
	connected:     bool,
	has_connected: bool,
	button:        platform.Gamepad_Button,
	has_button:    bool,
	down:          bool,
	left:          [2]f32,
	has_left:      bool,
	right:         [2]f32,
	has_right:     bool,
}

@(private)
parse_event_gamepad :: proc(object: json.Object) -> (Gamepad_Command, string) {
	value, _ := json_get(object, "gamepad")
	fields, fields_ok := json_object(value)
	if !fields_ok {
		return {}, format_error("%s", "'gamepad' must be an object")
	}
	if key, unknown := json_unknown_key(
		fields,
		{"connected", "button", "state", "left", "right"},
	); unknown {
		return {}, format_error("unknown gamepad key %q", key)
	}
	pad: Gamepad_Command
	if field_error := json_optional_bool(
		fields,
		"connected",
		&pad.connected,
		&pad.has_connected,
	); field_error != "" {
		return {}, field_error
	}
	state_name, has_state, state_error := event_string(fields, "state")
	if state_error != "" {
		return {}, state_error
	}
	button_name, has_button, button_error := event_string(fields, "button")
	if button_error != "" {
		return {}, button_error
	}
	pad.down = true
	if has_state {
		switch state_name {
		case "down":
			pad.down = true
		case "up":
			pad.down = false
		case:
			return {}, format_error("%s", "'gamepad.state' must be down or up")
		}
		if !has_button {
			return {}, format_error("%s", "'gamepad.state' needs 'gamepad.button'")
		}
	}
	if has_button {
		button, found := gamepad_button_from_name(button_name)
		if !found {
			return {}, format_error("unknown gamepad button %q", button_name)
		}
		pad.button = button
		pad.has_button = true
	}
	if _, has_left := json_get(fields, "left"); has_left {
		left, left_ok := vec2_field(fields, "left")
		if !left_ok {
			return {}, format_error("%s", "'gamepad.left' must be [x, y]")
		}
		pad.left = left
		pad.has_left = true
	}
	if _, has_right := json_get(fields, "right"); has_right {
		right, right_ok := vec2_field(fields, "right")
		if !right_ok {
			return {}, format_error("%s", "'gamepad.right' must be [x, y]")
		}
		pad.right = right
		pad.has_right = true
	}
	if !pad.has_connected && !pad.has_button && !pad.has_left && !pad.has_right {
		return {}, format_error(
			"%s",
			"gamepad needs 'connected', 'button', 'left', or 'right'",
		)
	}
	return pad, ""
}
