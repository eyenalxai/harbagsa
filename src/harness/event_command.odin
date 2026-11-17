#+vet explicit-allocators
package harness

import "core:encoding/json"
import "core:mem"

import "src:platform"

Event_Form :: enum {
	Key,
	Pointer,
	Wheel,
	Focus,
	Gamepad,
}

Event_Key_State :: enum {
	Down,
	Up,
	Repeat,
}

Event_Pointer_State :: enum {
	Move,
	Down,
	Up,
}

Event_Button :: enum {
	Left,
	Right,
}

// One raw frame; the engine route decides the sink.
Event_Command :: struct {
	form:          Event_Form,
	key:           platform.Key,
	key_state:     Event_Key_State,
	mods:          platform.Modifiers,
	pointer:       [2]f32,
	has_pointer:   bool,
	look:          [2]f32,
	has_look:      bool,
	pointer_state: Event_Pointer_State,
	button:        Event_Button,
	wheel:         f32,
	focused:       bool,
	captured:      bool,
	has_captured:  bool,
	pad_connected: bool,
	has_connected: bool,
	pad_button:    platform.Gamepad_Button,
	has_button:    bool,
	pad_down:      bool,
	pad_left:      [2]f32,
	has_left:      bool,
	pad_right:     [2]f32,
	has_right:     bool,
	expect:        Ui_Expect,
	has_expect:    bool,
	no_action:     bool,
	expect_state:  []State_Expect,
}

parse_event :: proc(object: json.Object, allocator: mem.Allocator) -> (Command, string) {
	allowed := []string {
		"cmd",
		"key",
		"state",
		"mods",
		"pointer",
		"look",
		"button",
		"wheel",
		"focus",
		"captured",
		"gamepad",
		"expect",
		"expect_no_action",
		"expect_state",
	}
	if key, unknown := json_unknown_key(object, allowed); unknown {
		return {}, format_error("unknown key %q", key)
	}
	command := Command{kind = .Event}
	_, has_key := json_get(object, "key")
	_, has_wheel := json_get(object, "wheel")
	_, has_focus := json_get(object, "focus")
	_, has_pad := json_get(object, "gamepad")
	_, has_pointer := json_get(object, "pointer")

	forms := 0
	if has_key {
		forms += 1
	}
	if has_wheel {
		forms += 1
	}
	if has_focus {
		forms += 1
	}
	if has_pad {
		forms += 1
	}
	if has_pointer {
		forms += 1
	}
	if forms != 1 {
		return {}, format_error(
			"%s",
			"event needs exactly one of key, pointer, wheel, focus, or gamepad",
		)
	}
	form := Event_Form.Key
	switch {
	case has_wheel:
		form = .Wheel
	case has_focus:
		form = .Focus
	case has_pad:
		form = .Gamepad
	case has_pointer:
		form = .Pointer
	}
	switch form {
	case .Key:
		if field_error := reject_event_keys(object, {"button"}); field_error != "" {
			return {}, field_error
		}
	case .Pointer:
		if field_error := reject_event_keys(object, {"mods"}); field_error != "" {
			return {}, field_error
		}
	case .Wheel, .Focus, .Gamepad:
		if field_error := reject_event_keys(object, {"state", "button", "mods"}); field_error != "" {
			return {}, field_error
		}
	}
	if form != .Focus {
		if field_error := reject_event_keys(object, {"captured"}); field_error != "" {
			return {}, field_error
		}
	}
	if form != .Pointer {
		if field_error := reject_event_keys(object, {"look"}); field_error != "" {
			return {}, field_error
		}
	}
	command.event.form = form

	if has_key {
		name, ok := string_field(object, "key")
		if !ok {
			return {}, format_error("%s", "'key' must be a string")
		}
		key, found := key_from_name(name)
		if !found {
			return {}, format_error("unknown key %q", name)
		}
		command.event.key = key
		state_name, has_state, state_error := event_string(object, "state")
		if state_error != "" {
			return {}, state_error
		}
		if has_state {
			state, state_ok := parse_key_state(state_name)
			if !state_ok {
				return {}, format_error("%s", "'state' must be down, up, or repeat")
			}
			command.event.key_state = state
		}
		mods, mods_error := parse_event_mods(object)
		if mods_error != "" {
			return {}, mods_error
		}
		command.event.mods = mods
	}
	if has_pointer {
		pointer, pointer_ok := vec2_field(object, "pointer")
		if !pointer_ok {
			return {}, format_error("%s", "'pointer' must be [x, y] in view points")
		}
		command.event.pointer = pointer
		command.event.has_pointer = true
		command.event.pointer_state = .Move
		state_name, has_state, state_error := event_string(object, "state")
		if state_error != "" {
			return {}, state_error
		}
		if has_state {
			state, state_ok := parse_pointer_state(state_name)
			if !state_ok {
				return {}, format_error("%s", "'state' must be move, down, or up")
			}
			command.event.pointer_state = state
		}
		if _, has_look := json_get(object, "look"); has_look {
			look, look_ok := vec2_field(object, "look")
			if !look_ok {
				return {}, format_error("%s", "'look' must be [dx, dy]")
			}
			command.event.look = look
			command.event.has_look = true
		}
		command.event.button = .Left
		button_name, has_button, button_error := event_string(object, "button")
		if button_error != "" {
			return {}, button_error
		}
		if has_button {
			switch button_name {
			case "left":
			case "right":
				command.event.button = .Right
			case:
				return {}, format_error("%s", "'button' must be left or right")
			}
		}
		if command.event.pointer_state == .Move && command.event.button != .Left {
			return {}, format_error("%s", "a move carries no button")
		}
	}
	if has_wheel {
		wheel, ok := number_field(object, "wheel")
		if !ok {
			return {}, format_error("%s", "'wheel' must be a number of notches")
		}
		command.event.wheel = f32(wheel)
	}
	if has_focus {
		focused, ok := json_boolean(json_get_required(object, "focus"))
		if !ok {
			return {}, format_error("%s", "'focus' must be a boolean")
		}
		command.event.focused = focused
		if field_error := json_optional_bool(
			object,
			"captured",
			&command.event.captured,
			&command.event.has_captured,
		); field_error != "" {
			return {}, field_error
		}
	}
	if has_pad {
		pad, pad_error := parse_event_gamepad(object)
		if pad_error != "" {
			return {}, pad_error
		}
		command.event.pad_connected = pad.connected
		command.event.has_connected = pad.has_connected
		command.event.pad_button = pad.button
		command.event.has_button = pad.has_button
		command.event.pad_down = pad.down
		command.event.pad_left = pad.left
		command.event.has_left = pad.has_left
		command.event.pad_right = pad.right
		command.event.has_right = pad.has_right
	}
	if expect_value, has_expect := json_get(object, "expect"); has_expect {
		expect, expect_error := parse_ui_expect(expect_value)
		if expect_error != "" {
			return {}, expect_error
		}
		command.event.expect = expect
		command.event.has_expect = true
	}
	if field_error := json_bool(object, "expect_no_action", &command.event.no_action); field_error != "" {
		return {}, field_error
	}
	if expect_state_value, has_expect_state := json_get(object, "expect_state"); has_expect_state {
		expects, expect_error := parse_state_expects(expect_state_value, allocator)
		if expect_error != "" {
			return {}, expect_error
		}
		command.event.expect_state = expects
	}
	return command, ""
}

@(private)
event_string :: proc(object: json.Object, key: string) -> (value: string, has: bool, error: string) {
	raw, present := json_get(object, key)
	if !present {
		return "", false, ""
	}
	text, ok := json_string(raw)
	if !ok {
		return "", true, format_error("'%s' must be a string", key)
	}
	return text, true, ""
}

@(private)
reject_event_keys :: proc(object: json.Object, names: []string) -> string {
	for name in names {
		if _, has := json_get(object, name); has {
			return format_error("'%s' does not apply to this event form", name)
		}
	}
	return ""
}

@(private)
parse_key_state :: proc(name: string) -> (Event_Key_State, bool) {
	switch name {
	case "down":
		return .Down, true
	case "up":
		return .Up, true
	case "repeat":
		return .Repeat, true
	}
	return .Down, false
}

@(private)
parse_pointer_state :: proc(name: string) -> (Event_Pointer_State, bool) {
	switch name {
	case "move":
		return .Move, true
	case "down":
		return .Down, true
	case "up":
		return .Up, true
	}
	return .Move, false
}

@(private)
parse_event_mods :: proc(object: json.Object) -> (platform.Modifiers, string) {
	mods: platform.Modifiers
	value, has_mods := json_get(object, "mods")
	if !has_mods {
		return mods, ""
	}
	array, array_ok := json_array(value)
	if !array_ok {
		return mods, format_error("%s", "'mods' must be an array")
	}
	for item in array {
		name, name_ok := json_string(item)
		if !name_ok {
			return mods, format_error("%s", "'mods' must hold names")
		}
		modifier, found := modifier_from_name(name)
		if !found {
			return mods, format_error("unknown modifier %q", name)
		}
		mods += {modifier}
	}
	return mods, ""
}
