#+vet explicit-allocators
package harness

import "core:encoding/json"
import "core:mem"
import "core:strconv"
import "core:strings"

Resize_Command :: struct {
	width:        u32,
	height:       u32,
	expect_state: []State_Expect,
}

parse_resize :: proc(object: json.Object, allocator: mem.Allocator) -> (Command, string) {
	if key, unknown := json_unknown_key(object, {"cmd", "size", "expect_state"}); unknown {
		return {}, format_error("unknown key %q", key)
	}
	size, has_size := string_field(object, "size")
	if !has_size {
		return {}, format_error("%s", "resize needs 'size' as WIDTHxHEIGHT")
	}
	width, height, parsed := parse_resize_size(size)
	if !parsed {
		return {}, format_error("'size' must be WIDTHxHEIGHT, got %q", size)
	}
	command := Command{kind = .Resize, resize = {width = width, height = height}}
	if expect_state_value, has_expect_state := json_get(object, "expect_state"); has_expect_state {
		expects, expect_error := parse_state_expects(expect_state_value, allocator)
		if expect_error != "" {
			return {}, expect_error
		}
		command.resize.expect_state = expects
	}
	return command, ""
}

execute_resize :: proc(session: ^Session, command: Command, reply: ^Reply) -> string {
	if !session.render.enabled {
		return format_error("%s", "resize requires rendering")
	}
	backend := session.render.backend
	if backend == nil || backend.resize == nil {
		return format_error("%s", "resize requires the offscreen renderer")
	}
	if !backend.resize(backend.ctx, command.resize.width, command.resize.height) {
		return format_error("%s", "the backend rejected the new extent")
	}
	if frame_error := session_frame(
		session,
		{resized = true, captured = session.captured},
		0,
		session.default_alpha,
		nil,
	); frame_error != "" {
		return frame_error
	}
	return check_state_expects(session, command.resize.expect_state)
}

destroy_resize :: proc(command: ^Command, allocator: mem.Allocator) {
	state_expects_destroy(command.resize.expect_state, allocator)
	command.resize.expect_state = nil
	command^ = {}
}

@(private)
parse_resize_size :: proc(size: string) -> (width, height: u32, ok: bool) {
	cross := strings.index_byte(size, 'x')
	if cross <= 0 || cross >= len(size) - 1 {
		return 0, 0, false
	}
	width_value, width_ok := strconv.parse_u64(size[:cross])
	height_value, height_ok := strconv.parse_u64(size[cross + 1:])
	if !width_ok || !height_ok {
		return 0, 0, false
	}
	if width_value == 0 || height_value == 0 ||
	   width_value > u64(max(u32)) || height_value > u64(max(u32)) {
		return 0, 0, false
	}
	return u32(width_value), u32(height_value), true
}
