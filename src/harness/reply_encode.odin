#+vet explicit-allocators
package harness

import "core:encoding/json"
import "core:fmt"

encode_reply :: proc(reply: Reply) -> []u8 {
	out := make([dynamic]u8, 0, 256, context.allocator)
	append_text(&out, `{"ok":`)
	append_text(&out, reply.ok ? "true" : "false")
	append_text(&out, `,"cmd":`)
	append_json(&out, reply.cmd)
	frame_text := fmt.aprintf("%d", reply.frame, allocator = context.temp_allocator)
	append_text(&out, `,"frame":`)
	append_text(&out, frame_text)
	if reply.error != "" {
		append_text(&out, `,"error":`)
		append_json(&out, reply.error)
	}
	if reply.state != nil {
		append_text(&out, `,"state":`)
		append_json(&out, reply.state^)
	}
	if reply.capture != nil {
		append_text(&out, `,"capture":`)
		append_json(&out, reply.capture^)
	}
	if reply.check != nil {
		append_text(&out, `,"check":`)
		append_json(&out, reply.check^)
	}
	if reply.recorded != "" {
		append_text(&out, `,"recorded":`)
		append_json(&out, reply.recorded)
	}
	if reply.replay != nil {
		append_text(&out, `,"replay":`)
		append_json(&out, reply.replay^)
	}
	append_text(&out, "}")
	return out[:]
}

@(private)
append_text :: proc(out: ^[dynamic]u8, text: string) {
	append(out, text)
}

@(private)
append_json :: proc(out: ^[dynamic]u8, value: any) {
	data, marshal_error := json.marshal(value, {}, context.allocator)
	if marshal_error != nil {
		append_text(out, "null")
		return
	}
	defer delete(data, context.allocator)
	append(out, ..data)
}
