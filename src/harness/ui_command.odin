#+vet explicit-allocators
package harness

import "core:encoding/json"
import "core:mem"

import "src:game"
import "src:renderer"
import "src:uiaction"

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

Ui_Command :: struct {
	x:   f32,
	y:   f32,
	key: Ui_Key,
}

parse_ui :: proc(object: json.Object, _allocator: mem.Allocator) -> (Command, string) {
	if key, unknown := json_unknown_key(object, {"cmd", "x", "y", "key"}); unknown {
		return {}, format_error("unknown key %q", key)
	}
	command := Command{kind = .Ui}
	x_value, has_x := json_get(object, "x")
	y_value, has_y := json_get(object, "y")
	value, has_key := json_get(object, "key")
	if has_key {
		if has_x || has_y {
			return {}, format_error("%s", "ui takes 'key' or 'x' and 'y', not both")
		}
		text, ok := json_string(value)
		if !ok {
			return {}, format_error("%s", "'key' must be a string")
		}
		key, stored := ui_key_from_text(text)
		if !stored {
			return {}, format_error("'key' must be a non-empty string shorter than %d bytes", UI_KEY_BYTES)
		}
		command.ui.key = key
		return command, ""
	}
	if !has_x || !has_y {
		return {}, format_error("%s", "ui needs 'key' or both 'x' and 'y'")
	}
	x, x_ok := json_number(x_value)
	if !x_ok {
		return {}, format_error("%s", "'x' must be a number")
	}
	y, y_ok := json_number(y_value)
	if !y_ok {
		return {}, format_error("%s", "'y' must be a number")
	}
	command.ui = {x = f32(x), y = f32(y)}
	return command, ""
}

execute_ui :: proc(session: ^Session, command: Command, reply: ^Reply) -> string {
	if session.render.backend == nil {
		return format_error("%s", "ui requires rendering")
	}
	ui := command.ui
	actions: []renderer.Ui_Action
	if ui.key.length > 0 {
		key := ui.key
		actions = renderer.ui_click_key(ui_key_text(&key))
	} else {
		actions = renderer.ui_click_at(ui.x, ui.y)
	}
	if len(actions) == 0 {
		return format_error("%s", "the UI click produced no action")
	}
	for action in actions {
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
			renderer.ui_actions_clear()
			return format_error("unknown UI action kind %d", action.kind)
		}
		if !result.applied {
			renderer.ui_actions_clear()
			message := game.edit_reason_message(result.reason)
			if message == "" {
				message = "the UI action made no change"
			}
			return format_error("%s", message)
		}
	}
	renderer.ui_actions_clear()
	return ""
}
