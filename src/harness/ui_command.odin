#+vet explicit-allocators
package harness

import "core:encoding/json"
import "core:mem"

import "src:renderer"

Ui_Command :: struct {
	x: f32,
	y: f32,
}

parse_ui :: proc(object: json.Object, allocator: mem.Allocator) -> (Command, string) {
	if key, unknown := json_unknown_key(object, {"cmd", "x", "y"}); unknown {
		return {}, format_error("unknown key %q", key)
	}
	command := Command{kind = .Ui}
	value, has := json_get(object, "x")
	if !has {
		return {}, format_error("%s", "ui needs 'x'")
	}
	x, x_ok := json_number(value)
	if !x_ok {
		return {}, format_error("%s", "'x' must be a number")
	}
	value, has = json_get(object, "y")
	if !has {
		return {}, format_error("%s", "ui needs 'y'")
	}
	y, y_ok := json_number(value)
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
	data := cast(^Backend_Data) session.render.backend.ctx
	actions := renderer.ui_click(&data.renderer, command.ui.x, command.ui.y)
	if len(actions) == 0 {
		return format_error("%s", "the UI click produced no action")
	}
	return ""
}
