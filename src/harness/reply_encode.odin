#+vet explicit-allocators
package harness

import "core:encoding/json"
import "core:fmt"

// The state and every nested object carry their JSON names in the struct tags.
// The reply envelope owns its own optional fields, so a nil pointer is omitted
// without asking json.marshal to dereference it.
encode_reply :: proc(reply: Reply) -> []u8 {
	out := make([dynamic]u8, 0, 256, context.allocator)
	append(&out, `{"ok":`)
	append(&out, reply.ok ? "true" : "false")
	append(&out, `,"cmd":`)
	append_json(&out, reply.cmd)
	frame_text := fmt.aprintf("%d", reply.frame, allocator = context.temp_allocator)
	append(&out, `,"frame":`)
	append(&out, frame_text)
	if reply.error != "" {
		append(&out, `,"error":`)
		append_json(&out, reply.error)
	}
	if reply.state != nil {
		append(&out, `,"state":`)
		append_json(&out, reply.state^)
	}
	if reply.capture != nil {
		append(&out, `,"capture":`)
		append_json(&out, reply.capture^)
	}
	if reply.check != nil {
		append(&out, `,"check":`)
		append_json(&out, reply.check^)
	}
	if reply.recorded != "" {
		append(&out, `,"recorded":`)
		append_json(&out, reply.recorded)
	}
	if reply.written != "" {
		append(&out, `,"written":`)
		append_json(&out, reply.written)
	}
	if reply.placed != 0 {
		append(&out, `,"placed":`)
		append_json(&out, reply.placed)
	}
	if reply.get != nil {
		append(&out, `,"field":`)
		append_json(&out, reply.get.field)
		append(&out, `,"value":`)
		switch reply.get.value.kind {
		case .Number:
			number := fmt.aprintf("%g", reply.get.value.number, allocator = context.temp_allocator)
			append(&out, number)
		case .Bool:
			append_json(&out, reply.get.value.boolean)
		case .String:
			append_json(&out, reply.get.value.text)
		}
	}
	if reply.replay != nil {
		append(&out, `,"replay":`)
		append_json(&out, reply.replay^)
	}
	if reply.perf != nil {
		append(&out, `,"perf":`)
		append_json(&out, reply.perf^)
	}
	if reply.trace != "" {
		append(&out, `,"trace":`)
		append_json(&out, reply.trace)
	}
	if reply.reference != nil {
		append(&out, `,"reference":`)
		append_json(&out, reply.reference^)
	}
	if reply.rows != nil {
		append(&out, `,"rows":`)
		append_json(&out, reply.rows^)
	}
	if reply.displays != nil {
		append(&out, `,"displays":`)
		append_json(&out, reply.displays^)
	}
	append(&out, "}")
	return out[:]
}

@(private)
append_json :: proc(out: ^[dynamic]u8, value: any) {
	data, marshal_error := json.marshal(value, {}, context.allocator)
	if marshal_error != nil {
		append(out, "null")
		return
	}
	defer delete(data, context.allocator)
	append(out, ..data)
}
