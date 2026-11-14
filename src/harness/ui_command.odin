#+vet explicit-allocators
package harness

import "core:encoding/json"
import "core:mem"

UI_KEY_BYTES :: 32

Ui_Key :: struct {
	bytes:  [UI_KEY_BYTES]u8,
	length: u8,
}

ui_key_from_text :: proc(text: string) -> (Ui_Key, bool) {
	if text == "" || len(text) >= UI_KEY_BYTES {
		return {}, false
	}
	key: Ui_Key
	key.length = u8(len(text))
	copy(key.bytes[:], text)
	return key, true
}

ui_key_text :: proc(key: ^Ui_Key) -> string {
	return string(key.bytes[:key.length])
}

Ui_Target :: struct {
	key:   Ui_Key,
	x:     f32,
	y:     f32,
	point: bool,
}

Ui_Drag :: struct {
	target: Ui_Target,
	dx:     f32,
	dy:     f32,
	steps:  int,
	hold:   bool,
	cancel: bool,
}

Ui_Wheel :: struct {
	target: Ui_Target,
	dx:     f32,
	dy:     f32,
}

Ui_Expect :: struct {
	kind:      u32,
	id:        u32,
	value:     i32,
	scalar:    f32,
	has_id:    bool,
	has_value: bool,
	has_scalar: bool,
}

Ui_State_Expect :: struct {
	path:  string,
	value: Field_Value,
}

Ui_Command :: struct {
	click:        Ui_Target,
	drag:         Ui_Drag,
	wheel:        Ui_Wheel,
	focus:        bool,
	expect:       Ui_Expect,
	expect_state: []Ui_State_Expect,
	has_click:    bool,
	has_drag:     bool,
	has_wheel:    bool,
	has_focus:    bool,
	has_expect:   bool,
}

parse_ui :: proc(object: json.Object, allocator: mem.Allocator) -> (Command, string) {
	allowed := []string {
		"cmd",
		"click",
		"key",
		"x",
		"y",
		"drag",
		"wheel",
		"focus",
		"expect",
		"expect_state",
	}
	if key, unknown := json_unknown_key(object, allowed); unknown {
		return {}, format_error("unknown key %q", key)
	}
	command := Command{kind = .Ui}
	forms := 0
	if click_value, has_click := json_get(object, "click"); has_click {
		if _, has_key := json_get(object, "key"); has_key {
			return {}, format_error("%s", "ui takes 'click' or 'key', not both")
		}
		if _, has_x := json_get(object, "x"); has_x {
			return {}, format_error("%s", "ui takes 'click' or 'x' and 'y', not both")
		}
		if _, has_y := json_get(object, "y"); has_y {
			return {}, format_error("%s", "ui takes 'click' or 'x' and 'y', not both")
		}
		target, target_error := parse_ui_target(click_value, "click")
		if target_error != "" {
			return {}, target_error
		}
		command.ui.click = target
		command.ui.has_click = true
		forms += 1
	} else if legacy_target, has_legacy, legacy_error := parse_legacy_click(object); legacy_error != "" {
		return {}, legacy_error
	} else if has_legacy {
		command.ui.click = legacy_target
		command.ui.has_click = true
		forms += 1
	}
	if drag_value, has_drag := json_get(object, "drag"); has_drag {
		drag, drag_error := parse_ui_drag(drag_value)
		if drag_error != "" {
			return {}, drag_error
		}
		command.ui.drag = drag
		command.ui.has_drag = true
		forms += 1
	}
	if wheel_value, has_wheel := json_get(object, "wheel"); has_wheel {
		wheel, wheel_error := parse_ui_wheel(wheel_value)
		if wheel_error != "" {
			return {}, wheel_error
		}
		command.ui.wheel = wheel
		command.ui.has_wheel = true
		forms += 1
	}
	if focus_value, has_focus := json_get(object, "focus"); has_focus {
		focus, ok := json_boolean(focus_value)
		if !ok {
			return {}, format_error("%s", "'focus' must be a boolean")
		}
		command.ui.focus = focus
		command.ui.has_focus = true
		forms += 1
	}
	if forms != 1 {
		return {}, format_error("%s", "ui needs exactly one of click, drag, wheel, or focus")
	}
	if expect_value, has_expect := json_get(object, "expect"); has_expect {
		expect, expect_error := parse_ui_expect(expect_value)
		if expect_error != "" {
			return {}, expect_error
		}
		command.ui.expect = expect
		command.ui.has_expect = true
	}
	if expect_state_value, has_expect_state := json_get(object, "expect_state"); has_expect_state {
		expects, expect_error := parse_ui_expect_state(expect_state_value, allocator)
		if expect_error != "" {
			return {}, expect_error
		}
		command.ui.expect_state = expects
	}
	return command, ""
}

@(private)
parse_legacy_click :: proc(object: json.Object) -> (target: Ui_Target, has: bool, error: string) {
	key_value, has_key := json_get(object, "key")
	x_value, has_x := json_get(object, "x")
	y_value, has_y := json_get(object, "y")
	if !has_key && !has_x && !has_y {
		return {}, false, ""
	}
	if has_key {
		if has_x || has_y {
			return {}, false, format_error("%s", "ui takes 'key' or 'x' and 'y', not both")
		}
		text, ok := json_string(key_value)
		if !ok {
			return {}, false, format_error("%s", "'key' must be a string")
		}
		key, stored := ui_key_from_text(text)
		if !stored {
			return {}, false, format_error("'key' must be a non-empty string shorter than %d bytes", UI_KEY_BYTES)
		}
		return {key = key}, true, ""
	}
	if !has_x || !has_y {
		return {}, false, format_error("%s", "ui needs 'key' or both 'x' and 'y'")
	}
	x, x_ok := json_number(x_value)
	if !x_ok {
		return {}, false, format_error("%s", "'x' must be a number")
	}
	y, y_ok := json_number(y_value)
	if !y_ok {
		return {}, false, format_error("%s", "'y' must be a number")
	}
	return {x = f32(x), y = f32(y), point = true}, true, ""
}

@(private)
parse_ui_target :: proc(value: json.Value, field: string) -> (Ui_Target, string) {
	if text, ok := json_string(value); ok {
		key, stored := ui_key_from_text(text)
		if !stored {
			return {}, format_error("'%s' must be a non-empty key shorter than %d bytes", field, UI_KEY_BYTES)
		}
		return {key = key}, ""
	}
	if array, ok := json_array(value); ok {
		if len(array) != 2 {
			return {}, format_error("'%s' point must be [x, y]", field)
		}
		x, x_ok := json_number(array[0])
		y, y_ok := json_number(array[1])
		if !x_ok || !y_ok {
			return {}, format_error("'%s' point must be [x, y]", field)
		}
		return {x = f32(x), y = f32(y), point = true}, ""
	}
	return {}, format_error("'%s' must be an element key or [x, y]", field)
}

destroy_ui :: proc(command: ^Command, allocator: mem.Allocator) {
	for &expect in command.ui.expect_state {
		delete(expect.path, allocator)
		if expect.value.kind == .String {
			delete(expect.value.text, allocator)
		}
	}
	if command.ui.expect_state != nil {
		delete(command.ui.expect_state, allocator)
	}
	command.ui.expect_state = nil
	command^ = {}
}
